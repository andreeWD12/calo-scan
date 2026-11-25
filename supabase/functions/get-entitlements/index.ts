/**
 * Piano e utilizzo di oggi: { timeZone? } → Entitlements (stesso formato della struct Swift).
 * L'app lo usa solo per mostrare i limiti; i controlli veri sono nelle singole funzioni.
 */
import { errorResponse } from "../_shared/errors.ts";
import { COACH_LIMITS, safeTimeZone, SCAN_LIMITS } from "../_shared/scan.ts";
import { currentPlan } from "../_shared/plan.ts";
import { scanUsage } from "../_shared/usage.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;
  const body = (await readJSON(req, 1024) ?? {}) as { timeZone?: unknown };

  const plan = await currentPlan(admin, auth.userId);
  try {
    const usage = await scanUsage(admin, auth.userId, safeTimeZone(body.timeZone));
    return json({
      plan,
      scansUsedToday: usage.today,
      scansLimitToday: SCAN_LIMITS.daily[plan],
      coachMessagesUsedToday: 0, // il coach arriva con la Fase 7
      coachMessagesLimitToday: COACH_LIMITS[plan],
      expiresAt: null,
      willRenew: false,
    });
  } catch (e) {
    console.error("get-entitlements:", (e as Error).message);
    return errorResponse("internal");
  }
});
