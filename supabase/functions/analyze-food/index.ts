/**
 * Analisi di un pasto: { image?: base64 JPEG, description?: string, timeZone?: string } → ScanResult.
 * - Richiede il consenso ai dati sanitari (art. 9 GDPR) e, per le foto, quello all'analisi delle foto con l'AI.
 * - Rispetta i limiti del piano (scan_events).
 * - L'AI riconosce solo alimenti e grammi; i valori nutrizionali vengono da USDA FoodData Central.
 * - La foto non viene salvata né registrata nei log: esiste solo durante la richiesta.
 * - Le analisi senza alimenti riconosciuti o fallite non contano nel limite giornaliero.
 */
import { errorResponse } from "../_shared/errors.ts";
import { sanitizeFoodDescription } from "../_shared/nutrition.ts";
import { checkScanQuota, decodeJPEG, safeTimeZone } from "../_shared/scan.ts";
import { AIUnavailableError, recognizeMeal } from "../_shared/ai.ts";
import { bestUSDAMatch } from "../_shared/fooddb.ts";
import { currentPlan } from "../_shared/plan.ts";
import { scanUsage } from "../_shared/usage.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;

  const body = await readJSON(req, 3_000_000) as { image?: unknown; description?: unknown; timeZone?: unknown } | null;
  if (!body) return errorResponse("invalid_input");

  const image = body.image === undefined || body.image === null ? null : body.image;
  if (image !== null && !decodeJPEG(image)) return errorResponse("invalid_input", { message: "Immagine non valida." });
  const description = body.description === undefined || body.description === null
    ? null : sanitizeFoodDescription(body.description);
  if (body.description != null && description === null) {
    return errorResponse("invalid_input", { message: "Descrivi il piatto con qualche parola in più." });
  }
  if (image === null && description === null) return errorResponse("invalid_input");

  // Consenso: dati sanitari e invio al fornitore AI (revocabile da Profilo › Privacy).
  const { data: consent, error: consentError } = await admin.from("consents")
    .select("health_data_processing, ai_image_analysis").eq("user_id", auth.userId).maybeSingle();
  if (consentError) return errorResponse("internal", { message: `db_${consentError.code}` });
  if (!consent?.health_data_processing) {
    return errorResponse("invalid_input", { message: "Per analizzare i pasti serve il consenso al trattamento dei dati sulla salute (Profilo › Privacy e account)." });
  }
  // La foto richiede in più il consenso specifico all'invio delle immagini al fornitore AI.
  if (image !== null && !consent.ai_image_analysis) {
    return errorResponse("invalid_input", { message: "Per analizzare le foto attiva il consenso all'analisi delle foto con l'AI (Profilo › Privacy e account)." });
  }

  const plan = await currentPlan(admin, auth.userId);
  let usage;
  try {
    usage = await scanUsage(admin, auth.userId, safeTimeZone(body.timeZone));
  } catch (e) {
    console.error("analyze-food:", (e as Error).message);
    return errorResponse("internal");
  }
  const quota = checkScanQuota(plan, usage.today, usage.burst);
  if (!quota.ok) return errorResponse("quota_exceeded", { plan });

  let result;
  try {
    result = await recognizeMeal(image as string | null, description);
  } catch (e) {
    if (e instanceof AIUnavailableError) return errorResponse("ai_unavailable");
    throw e;
  }

  const matched = await Promise.all(result.items.map((i) => bestUSDAMatch(i.searchQuery, i.name)));
  const items = result.items.map((item, i) => ({
    id: crypto.randomUUID(),
    detectedName: item.name,
    matchedFood: matched[i],
    estimatedGrams: item.grams,
    confidenceScore: item.confidence,
    ingredients: item.ingredients,
  }));

  if (items.length > 0) {
    const { error } = await admin.from("scan_events")
      .insert({ user_id: auth.userId, kind: image ? "photo" : "description", item_count: items.length });
    if (error) console.error("analyze-food: scansione non registrata", error.code);
  }

  return json({
    id: crypto.randomUUID(),
    items,
    questions: result.questions,
    overallConfidenceScore: result.overallConfidence,
  });
});
