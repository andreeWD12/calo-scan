/**
 * "Invita un amico". Regole in _shared/referral.ts (con test) e, per la qualificazione al primo pasto,
 * nel trigger del database (migrazione fase 9).
 *   { action: "status" }  → ReferralStatus (crea il codice personale se manca)
 *   { action: "apply", code, deviceToken?, environment? } → { result: ApplyReferralResult }
 * Chi invita vede solo i conteggi, mai chi sono gli amici.
 */
import { secret } from "../_shared/applejwt.ts";
import { cleanDeviceToken, deviceAlreadyUsed, markDeviceUsed } from "../_shared/devicecheck.ts";
import { errorResponse } from "../_shared/errors.ts";
import { evaluateApply, generateReferralCode, normalizeReferralCode, REFERRAL } from "../_shared/referral.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";

const MAX_ATTEMPTS_PER_DAY = 10;

function shareURL(code: string): string {
  const custom = secret("REFERRAL_SHARE_URL");
  if (custom) return custom.replace("{code}", code);
  const appId = secret("APP_STORE_ID");
  return appId ? `https://apps.apple.com/app/id${appId}` : "https://apps.apple.com/it/search?term=CaloScan";
}

const isoSeconds = (v: string | null | undefined) => v ? new Date(v).toISOString().replace(/\.\d{3}Z$/, "Z") : null;

async function ensureCode(admin: SupabaseClient, userId: string): Promise<string> {
  const { data } = await admin.from("referral_codes").select("code").eq("user_id", userId).maybeSingle();
  if (data?.code) return data.code;
  for (let i = 0; i < 5; i++) {
    const code = generateReferralCode();
    const { error } = await admin.from("referral_codes").insert({ user_id: userId, code });
    if (!error) return code;
    if (error.code !== "23505") throw new Error(`referral_codes ${error.code}`);
    // Conflitto: o il codice esiste già per un altro utente (si riprova) o l'utente l'ha appena creato.
    const again = await admin.from("referral_codes").select("code").eq("user_id", userId).maybeSingle();
    if (again.data?.code) return again.data.code;
  }
  throw new Error("referral_codes: codice non generato");
}

async function status(admin: SupabaseClient, userId: string) {
  const code = await ensureCode(admin, userId);
  // Se il premio non è stato assegnato al primo pasto dell'amico (es. lotto di codici vuoto), ci si riprova qui.
  await admin.rpc("assign_referral_reward", { p_referrer: userId });

  const [invited, qualified, reward, subs, own, user] = await Promise.all([
    admin.from("referrals").select("referred_id", { count: "exact", head: true }).eq("referrer_id", userId),
    admin.from("referrals").select("referred_id", { count: "exact", head: true }).eq("referrer_id", userId).not("qualified_at", "is", null),
    admin.from("referral_rewards").select("offer_code, expires_at, redeemed_at").eq("referrer_id", userId).maybeSingle(),
    admin.from("subscriptions").select("original_transaction_id", { count: "exact", head: true }).eq("user_id", userId),
    admin.from("referrals").select("referred_id").eq("referred_id", userId).maybeSingle(),
    admin.auth.admin.getUserById(userId),
  ]);

  const r = reward.data;
  let state: "waiting" | "available" | "redeemed" | "not_eligible" = "waiting";
  if (r?.redeemed_at) state = "redeemed";
  else if (r && Date.parse(r.expires_at) > Date.now()) state = "available";
  else if (r || (subs.count ?? 0) > 0) state = "not_eligible";

  const createdAt = user.data.user?.created_at ?? new Date().toISOString();
  const withinWindow = (Date.now() - Date.parse(createdAt)) / 86_400_000 <= REFERRAL.applyWindowDays;
  return {
    code,
    shareURL: shareURL(code),
    invitedCount: Math.min(invited.count ?? 0, REFERRAL.maxCountedInvites),
    qualifiedCount: Math.min(qualified.count ?? 0, REFERRAL.maxCountedInvites),
    reward: state,
    offerCode: state === "available" ? r?.offer_code ?? null : null,
    offerExpiresAt: state === "available" ? isoSeconds(r?.expires_at) : null,
    discountLabel: secret("REFERRAL_DISCOUNT_LABEL") ?? "30%",
    canEnterCode: !own.data && withinWindow,
    wasReferred: !!own.data,
  };
}

async function apply(admin: SupabaseClient, userId: string, body: Record<string, unknown>) {
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { count } = await admin.from("referral_attempts").select("id", { count: "exact", head: true })
    .eq("user_id", userId).gte("at", since);
  if ((count ?? 0) >= MAX_ATTEMPTS_PER_DAY) {
    return errorResponse("invalid_input", { message: "Troppi tentativi oggi. Controlla il codice e riprova domani." });
  }
  await admin.from("referral_attempts").insert({ user_id: userId });

  const normalized = normalizeReferralCode(body.code);
  const [owner, existing, user] = await Promise.all([
    normalized ? admin.from("referral_codes").select("user_id").eq("code", normalized).maybeSingle() : Promise.resolve({ data: null }),
    admin.from("referrals").select("referred_id").eq("referred_id", userId).maybeSingle(),
    admin.auth.admin.getUserById(userId),
  ]);
  const result = evaluateApply({
    rawCode: body.code,
    codeOwnerId: (owner.data as { user_id?: string } | null)?.user_id ?? null,
    userId,
    userCreatedAt: user.data.user?.created_at ?? new Date(0).toISOString(),
    now: new Date().toISOString(),
    alreadyReferred: !!existing.data,
  });
  if (result !== "applied") return json({ result });

  // DeviceCheck: lo stesso iPhone conta una volta sola. Se non si può verificare, l'invito vale comunque.
  const deviceToken = cleanDeviceToken(body.deviceToken);
  const env = body.environment === "production" ? "production" : "sandbox";
  let deviceOk = true;
  if (deviceToken) {
    const used = await deviceAlreadyUsed(deviceToken, env);
    deviceOk = used !== true;
  }
  const { error } = await admin.from("referrals").insert({
    referred_id: userId, referrer_id: (owner.data as { user_id: string }).user_id, device_ok: deviceOk,
  });
  if (error) {
    if (error.code === "23505") return json({ result: "already_referred" });
    throw new Error(`referrals ${error.code}`);
  }
  if (deviceToken && deviceOk) await markDeviceUsed(deviceToken, env);
  // L'amico potrebbe aver già registrato pasti prima di inserire il codice: si qualifica subito.
  const { count: meals } = await admin.from("meals").select("id", { count: "exact", head: true }).eq("user_id", userId);
  const { data: profile } = await admin.from("profiles").select("user_id").eq("user_id", userId).maybeSingle();
  if (deviceOk && (meals ?? 0) > 0 && profile) {
    await admin.from("referrals").update({ qualified_at: new Date().toISOString() }).eq("referred_id", userId);
    await admin.rpc("assign_referral_reward", { p_referrer: (owner.data as { user_id: string }).user_id });
  }
  return json({ result });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;
  const body = await readJSON(req, 16_384) as Record<string, unknown> | null;
  try {
    if (body?.action === "status") return json(await status(admin, auth.userId));
    if (body?.action === "apply") return await apply(admin, auth.userId, body);
    return errorResponse("invalid_input");
  } catch (e) {
    console.error("referral:", (e as Error).message);
    return errorResponse("internal");
  }
});
