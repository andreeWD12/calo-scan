/**
 * Invia le notifiche in coda (tabella push_outbox). Chiamata ogni 10 minuti da pg_cron con l'intestazione
 * `x-cron-secret` = segreto PUSH_CRON_SECRET (vedi docs/SETUP.md). Non è richiamabile dall'app.
 */
import { isDeadToken, MAX_ATTEMPTS, payloadFor, type PushKind, PushUnavailableError, sendPush } from "../_shared/apns.ts";
import { bundleId } from "../_shared/appstore.ts";
import { secret } from "../_shared/applejwt.ts";
import { errorResponse } from "../_shared/errors.ts";
import { adminClient, json } from "../_shared/supabase.ts";

function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  const expected = secret("PUSH_CRON_SECRET");
  const given = req.headers.get("x-cron-secret") ?? "";
  if (!expected || expected.length < 24 || !sameSecret(given, expected)) return errorResponse("unauthorized");

  const admin = adminClient();
  const { data: pending, error } = await admin.from("push_outbox")
    .select("id, user_id, kind, attempts").is("sent_at", null).lt("attempts", MAX_ATTEMPTS)
    .order("created_at").limit(100);
  if (error) {
    console.error("push-dispatch: coda non leggibile", error.code);
    return errorResponse("internal");
  }

  let sent = 0, failed = 0;
  try {
    for (const item of pending ?? []) {
      const { data: tokens } = await admin.from("push_tokens").select("token, environment").eq("user_id", item.user_id);
      let delivered = false;
      for (const t of tokens ?? []) {
        const r = await sendPush(t.token, t.environment, payloadFor(item.kind as PushKind), bundleId());
        if (r.status === 200) delivered = true;
        else if (isDeadToken(r.status, r.reason)) await admin.from("push_tokens").delete().eq("token", t.token);
        else console.warn("push-dispatch: APNs", r.status, r.reason ?? "");
      }
      // Senza dispositivi registrati la notifica si considera chiusa: l'utente vedrà il premio aprendo l'app.
      if (delivered || (tokens ?? []).length === 0) {
        await admin.from("push_outbox").update({ sent_at: new Date().toISOString() }).eq("id", item.id);
        sent++;
      } else {
        await admin.from("push_outbox").update({ attempts: item.attempts + 1 }).eq("id", item.id);
        failed++;
      }
    }
  } catch (e) {
    if (e instanceof PushUnavailableError) {
      console.error("push-dispatch:", e.message);
      return errorResponse("internal");
    }
    throw e;
  }
  console.log(`push-dispatch: ${sent} inviate, ${failed} da riprovare`);
  return json({ sent, failed });
});
