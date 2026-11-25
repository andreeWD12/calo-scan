/** Conteggio delle scansioni riuscite (tabella scan_events) per i limiti del piano. */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { SCAN_LIMITS, startOfDay } from "./scan.ts";

export async function scanUsage(admin: SupabaseClient, userId: string, timeZone: string, now = new Date()) {
  const since = (d: Date) => admin.from("scan_events").select("id", { count: "exact", head: true })
    .eq("user_id", userId).gte("created_at", d.toISOString());
  const [today, burst] = await Promise.all([
    since(startOfDay(now, timeZone)),
    since(new Date(now.getTime() - SCAN_LIMITS.burstWindowMinutes * 60_000)),
  ]);
  if (today.error || burst.error) throw new Error(`scan_events: ${(today.error ?? burst.error)?.code}`);
  return { today: today.count ?? 0, burst: burst.count ?? 0 };
}

/** Utilizzi di oggi di una funzione AI del coach (tabella ai_events). */
export async function aiUsageToday(admin: SupabaseClient, userId: string, kind: "coach" | "eating_styles" | "shopping",
  timeZone: string, now = new Date()): Promise<number> {
  const { count, error } = await admin.from("ai_events").select("id", { count: "exact", head: true })
    .eq("user_id", userId).eq("kind", kind).gte("created_at", startOfDay(now, timeZone).toISOString());
  if (error) throw new Error(`ai_events: ${error.code}`);
  return count ?? 0;
}

export async function recordAIEvent(admin: SupabaseClient, userId: string, kind: "coach" | "eating_styles" | "shopping") {
  const { error } = await admin.from("ai_events").insert({ user_id: userId, kind });
  if (error) console.error("ai_events: utilizzo non registrato", error.code);
}
