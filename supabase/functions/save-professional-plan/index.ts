/**
 * Salva o elimina il piano del medico o dietista dopo averlo rivalidato (_shared/professionalPlan.ts).
 * Il client può solo leggere `professional_plans` (RLS): la scrittura passa da qui.
 * Corpo: { plan: ProfessionalPlan } per salvare, { delete: true } per tornare agli obiettivi dell'app → 204
 * Salvare richiede Plus o Pro; eliminare è sempre possibile (anche dopo la fine dell'abbonamento).
 */
import { errorResponse } from "../_shared/errors.ts";
import { currentPlan } from "../_shared/plan.ts";
import { validateProfessionalPlanPayload } from "../_shared/professionalPlan.ts";
import { adminClient, readJSON, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;

  // Un piano a rotazione di 4 settimane con tutti i pasti può superare i 32 KB predefiniti.
  const body = await readJSON(req, 262_144) as { plan?: unknown; delete?: unknown } | null;
  if (!body) return errorResponse("invalid_input");

  if (body.delete === true) {
    const { error } = await admin.from("professional_plans").delete().eq("user_id", auth.userId);
    if (error) {
      console.error("save-professional-plan: eliminazione non riuscita", error.code);
      return errorResponse("internal", { message: `db_${error.code ?? "unknown"}` });
    }
    return new Response(null, { status: 204 });
  }

  if (await currentPlan(admin, auth.userId) === "free") return errorResponse("plan_required", { minimum: "Plus" });

  const issues = validateProfessionalPlanPayload(body.plan);
  if (issues.length > 0) return errorResponse("invalid_input", { message: issues.join(",") });

  const { error } = await admin.from("professional_plans").upsert({
    user_id: auth.userId,
    plan: body.plan,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (error) {
    console.error("save-professional-plan: salvataggio non riuscito", error.code);
    return errorResponse("internal", { message: `db_${error.code ?? "unknown"}` });
  }
  return new Response(null, { status: 204 });
});
