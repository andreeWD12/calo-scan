/**
 * Piano dell'utente letto dal server: abbonamenti App Store verificati (tabella `subscriptions`, aggiornata da
 * verify-purchase e app-store-notifications). L'app non può mai dichiararsi Plus o Pro da sola.
 *
 * Per i test: il segreto TESTER_USER_IDS (UUID separati da virgola) assegna il piano Pro a quegli account.
 * Si imposta solo dal terminale, mai dall'app. Da svuotare prima della pubblicazione.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { bestPlan, grantsAccess } from "./appstore.ts";
import type { Plan } from "./scan.ts";

export function testerPlan(userId: string, testers: string | undefined): Plan | null {
  const ids = (testers ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  return ids.includes(userId.toLowerCase()) ? "pro" : null;
}

export interface PlanInfo { plan: Plan; expiresAt: string | null; willRenew: boolean }

/** Piano, scadenza e rinnovo automatico dell'abbonamento che dà accesso (il più alto). */
export async function planInfo(admin: SupabaseClient, userId: string): Promise<PlanInfo> {
  const { data, error } = await admin.from("subscriptions").select("plan, status, expires_at, will_renew").eq("user_id", userId);
  if (error) throw new Error(`subscriptions: ${error.code}`);
  const subs = (data ?? []).map((r) => ({ plan: r.plan as Plan, status: r.status as number, expiresAt: r.expires_at as string | null, willRenew: r.will_renew as boolean }));
  const plan = bestPlan(subs);
  const tester = testerPlan(userId, Deno.env.get("TESTER_USER_IDS"));
  if (plan === "free" && tester) return { plan: tester, expiresAt: null, willRenew: false };
  const active = subs.filter((s) => s.plan === plan && grantsAccess(s));
  const latest = active.sort((a, b) => Date.parse(b.expiresAt ?? "") - Date.parse(a.expiresAt ?? ""))[0];
  // ISO senza millisecondi: il formato letto da `JSONDecoder.dateDecodingStrategy = .iso8601` nell'app.
  const expiresAt = latest?.expiresAt ? new Date(latest.expiresAt).toISOString().replace(/\.\d{3}Z$/, "Z") : null;
  return { plan, expiresAt, willRenew: latest?.willRenew ?? false };
}

export async function currentPlan(admin: SupabaseClient, userId: string): Promise<Plan> {
  try {
    return (await planInfo(admin, userId)).plan;
  } catch (e) {
    // In caso di errore del database si applica il piano più restrittivo, mai uno superiore.
    console.error("plan:", (e as Error).message);
    return testerPlan(userId, Deno.env.get("TESTER_USER_IDS")) ?? "free";
  }
}
