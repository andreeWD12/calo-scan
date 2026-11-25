/**
 * Piano dell'utente letto dal server. Gli acquisti (StoreKit 2 verificati con l'App Store Server API)
 * arrivano con la Fase 8: fino ad allora nessuno può aver acquistato un piano, quindi tutti sono Free.
 *
 * Per provare lo scanner prima della Fase 8: il segreto TESTER_USER_IDS (UUID separati da virgola)
 * assegna il piano Pro a quegli account. Si imposta solo dal terminale, mai dall'app.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import type { Plan } from "./scan.ts";

export function testerPlan(userId: string, testers: string | undefined): Plan | null {
  const ids = (testers ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  return ids.includes(userId.toLowerCase()) ? "pro" : null;
}

export function currentPlan(_admin: SupabaseClient, userId: string): Promise<Plan> {
  return Promise.resolve(testerPlan(userId, Deno.env.get("TESTER_USER_IDS")) ?? "free");
}
