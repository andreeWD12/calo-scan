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
