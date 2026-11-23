/**
 * Piano dell'utente letto dal server. Gli acquisti (StoreKit 2 verificati con l'App Store Server API)
 * arrivano con la Fase 8: fino ad allora nessuno può aver acquistato un piano, quindi tutti sono Free.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import type { Plan } from "./scan.ts";

export function currentPlan(_admin: SupabaseClient, _userId: string): Promise<Plan> {
  return Promise.resolve("free");
}
