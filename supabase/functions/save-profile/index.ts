/**
 * Salva profilo e obiettivi dopo averli rivalidati (stesse regole dell'app, _shared/profile.ts).
 * Il client non può scrivere direttamente la tabella `profiles` (RLS: solo lettura).
 * Corpo: { profile: UserProfile, targets: DailyTargets }  →  204
 */
import { errorResponse } from "../_shared/errors.ts";
import { pickTargets, validateProfilePayload } from "../_shared/profile.ts";
import type { DailyTargets } from "../_shared/nutrition.ts";
import { adminClient, readJSON, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;

  const body = await readJSON(req) as { profile?: unknown; targets?: unknown } | null;
  if (!body) return errorResponse("invalid_input");

  const today = new Date().toISOString().slice(0, 10);
  const issues = validateProfilePayload(body.profile, body.targets, today);
  if (issues.length > 0) return errorResponse("invalid_input", { message: issues.join(",") });

  const { error } = await admin.from("profiles").upsert({
    user_id: auth.userId,
    profile: body.profile,
    targets: pickTargets(body.targets as DailyTargets),
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (error) {
    console.error("save-profile: salvataggio non riuscito", error.code);
    return errorResponse("internal");
  }
  return new Response(null, { status: 204 });
});
