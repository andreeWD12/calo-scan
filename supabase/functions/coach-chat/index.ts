/**
 * AI Nutrition Coach. Corpo { action, timeZone?, ... }:
 * - "history" → { messages: CoachMessage[] } (ultimi 50)
 * - "send" { text } → CoachMessage (risposta del coach). Plus 30/giorno, Pro 150/giorno; Free: plan_required.
 * - "clear" → 204: cancella la conversazione (non azzera il limite di oggi).
 * - "eating_styles" { request: EatingStyleRequest } → { proposals } (solo Pro, 5/giorno)
 * - "shopping" { request?: string } → { suggestions } (Plus e Pro, 5/giorno)
 *
 * Sicurezza: consenso ai dati sanitari obbligatorio; richieste su autolesionismo, disturbi alimentari o
 * restrizioni estreme ricevono una risposta fissa senza passare dal modello; stili alimentari filtrati con
 * allowedStyles/sanitizeProposals; lista della spesa senza allergeni e, in gravidanza, senza alimenti a rischio.
 * Nei log nessun contenuto dell'utente.
 */
import { errorResponse } from "../_shared/errors.ts";
import { AIUnavailableError, chat, structured } from "../_shared/ai.ts";
import {
  type AIEventKind, activePregnancy, COACH_MESSAGE_MAX, type CoachContext, coachSystemPrompt, effectiveTargets,
  eatingStylePrompt, eatingStyleSchema, EXTRA_AI_LIMITS, localDate, localTime, safetyTopic, SAFETY_REPLIES,
  sanitizeCoachReply, sanitizeShopping, sanitizeUserText, SHOPPING_SCHEMA, shoppingSystemPrompt, type StoredProfile, summarizeMeals, toTurns,
} from "../_shared/coach.ts";
import { allowedStyles, sanitizeProposals, type Screening } from "../_shared/eatingStyle.ts";
import type { DailyTargets, ProfessionalPlan } from "../_shared/nutrition.ts";
import { filterForPregnancy } from "../_shared/pregnancy.ts";
import { ageOn } from "../_shared/profile.ts";
import { COACH_LIMITS, type Plan, safeTimeZone, startOfDay } from "../_shared/scan.ts";
import { type Allergen, filterSuggestions } from "../_shared/shopping.ts";
import { currentPlan } from "../_shared/plan.ts";
import { aiUsageToday, recordAIEvent } from "../_shared/usage.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";

type Body = { action?: unknown; text?: unknown; request?: unknown; timeZone?: unknown };

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;
  const body = await readJSON(req, 16_384) as Body | null;
  if (!body || typeof body.action !== "string") return errorResponse("invalid_input");
  const userId = auth.userId;
  const tz = safeTimeZone(body.timeZone);

  try {
    switch (body.action) {
      case "history": return await history(admin, userId);
      case "clear": {
        const { error } = await admin.from("coach_messages").delete().eq("user_id", userId);
        if (error) throw new Error(`coach_messages: ${error.code}`);
        return new Response(null, { status: 204 });
      }
      case "send": case "eating_styles": case "shopping": break;
      default: return errorResponse("invalid_input");
    }

    // Le funzioni AI usano profilo, obiettivi e pasti: dati sanitari (art. 9 GDPR).
    const { data: consent, error: consentError } = await admin.from("consents")
      .select("health_data_processing").eq("user_id", userId).maybeSingle();
    if (consentError) throw new Error(`consents: ${consentError.code}`);
    if (!consent?.health_data_processing) {
      return errorResponse("invalid_input", { message: "Per usare il coach serve il consenso al trattamento dei dati sulla salute (Profilo › Privacy e account)." });
    }

    const plan = await currentPlan(admin, userId);
    if (body.action === "send") return await send(admin, userId, plan, tz, body.text);
    if (body.action === "eating_styles") return await eatingStyles(admin, userId, plan, tz, body.request);
    return await shopping(admin, userId, plan, tz, body.request);
  } catch (e) {
    if (e instanceof AIUnavailableError) return errorResponse("ai_unavailable");
    console.error("coach-chat:", (e as Error).message);
    return errorResponse("internal");
  }
});

async function history(admin: SupabaseClient, userId: string): Promise<Response> {
  const { data, error } = await admin.from("coach_messages").select("id, role, text, created_at")
    .eq("user_id", userId).order("created_at", { ascending: false }).limit(50);
  if (error) throw new Error(`coach_messages: ${error.code}`);
  return json({ messages: (data ?? []).reverse().map(toMessage) });
}

/** Date ISO 8601 senza millisecondi: è il formato che legge `JSONDecoder.dateDecodingStrategy = .iso8601`. */
const isoSeconds = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, "Z");
const toMessage = (r: { id: string; role: string; text: string; created_at: string }) =>
  ({ id: r.id, role: r.role, text: r.text, createdAt: isoSeconds(new Date(r.created_at)) });

async function checkLimit(admin: SupabaseClient, userId: string, kind: AIEventKind, limit: number, tz: string) {
  return await aiUsageToday(admin, userId, kind, tz) < limit;
}

async function send(admin: SupabaseClient, userId: string, plan: Plan, tz: string, raw: unknown): Promise<Response> {
  if (COACH_LIMITS[plan] === 0) return errorResponse("plan_required", { minimum: "Plus" });
  const text = sanitizeUserText(raw);
  if (!text) return errorResponse("invalid_input", { message: `Scrivi un messaggio di al massimo ${COACH_MESSAGE_MAX} caratteri.` });
  if (!await checkLimit(admin, userId, "coach", COACH_LIMITS[plan], tz)) return errorResponse("quota_exceeded", { plan });

  const { data: past, error } = await admin.from("coach_messages").select("role, text")
    .eq("user_id", userId).order("created_at", { ascending: false }).limit(12);
  if (error) throw new Error(`coach_messages: ${error.code}`);

  const topic = safetyTopic(text);
  let reply: string;
  if (topic) {
    reply = SAFETY_REPLIES[topic];
  } else {
    const ctx = await loadContext(admin, userId, plan, tz);
    const out = await chat(coachSystemPrompt(ctx), toTurns((past ?? []).reverse(), text));
    reply = out === null
      ? "Su questo non posso aiutarti. Posso però rispondere a domande sui tuoi pasti, sugli obiettivi o sulla spesa."
      : sanitizeCoachReply(out);
    await recordAIEvent(admin, userId, "coach"); // le risposte di sicurezza non contano nel limite
  }

  const now = Date.now();
  const { data: rows, error: insertError } = await admin.from("coach_messages").insert([
    { user_id: userId, role: "user", text, created_at: new Date(now).toISOString() },
    { user_id: userId, role: "assistant", text: reply, created_at: new Date(now + 1).toISOString() },
  ]).select("id, role, text, created_at");
  if (insertError) throw new Error(`coach_messages: ${insertError.code}`);
  const assistant = (rows ?? []).find((r) => r.role === "assistant");
  return json(assistant ? toMessage(assistant) : { id: crypto.randomUUID(), role: "assistant", text: reply, createdAt: isoSeconds(new Date(now)) });
}

async function eatingStyles(admin: SupabaseClient, userId: string, plan: Plan, tz: string, raw: unknown): Promise<Response> {
  if (plan !== "pro") return errorResponse("plan_required", { minimum: "Pro" });
  const r = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
  const s = (typeof r.screening === "object" && r.screening !== null ? r.screening : {}) as Record<string, unknown>;
  // In assenza di risposta si assume la condizione più prudente.
  const screening: Screening = {
    pregnantOrBreastfeeding: s.pregnantOrBreastfeeding !== false, diabetesMedication: s.diabetesMedication !== false,
    eatingDisorderHistory: s.eatingDisorderHistory !== false, medicalSupervision: s.medicalSupervision !== false,
  };
  const pick = (v: unknown, allowed: string[], d: string) => (typeof v === "string" && allowed.includes(v) ? v : d);
  const note = r.note == null ? null : sanitizeUserText(r.note, 300);

  if (!await checkLimit(admin, userId, "eating_styles", EXTRA_AI_LIMITS.eating_styles, tz)) return errorResponse("quota_exceeded", { plan });
  const ctx = await loadContext(admin, userId, plan, tz);
  const p = ctx.profile;
  const today = localDate(new Date(), tz);
  const age = p.birthDate ? ageOn(p.birthDate, today) : null;
  if (age === null || !p.heightCm || !p.weightKg) return errorResponse("invalid_input", { message: "Completa il profilo per ricevere proposte." });
  const bmi = p.weightKg / ((p.heightCm / 100) ** 2);
  const allowed = allowedStyles(age, bmi, { ...screening, pregnantOrBreastfeeding: screening.pregnantOrBreastfeeding || ctx.pregnancy !== null },
    ctx.hasProfessionalPlan);
  if (allowed.length === 0) return json({ proposals: [] });

  const out = await structured(eatingStylePrompt(ctx, {
    mealsPerDay: pick(r.mealsPerDay, ["two", "three", "four_or_more"], "three"),
    hunger: pick(r.hunger, ["morning", "evening", "even"], "even"),
    trainsRegularly: r.trainsRegularly === true, note,
  }), [{ type: "text", text: "Proponi gli stili più adatti." }], eatingStyleSchema(allowed)) as { proposals?: unknown } | null;
  await recordAIEvent(admin, userId, "eating_styles");
  return json({ proposals: sanitizeProposals(out?.proposals ?? [], allowed) });
}

async function shopping(admin: SupabaseClient, userId: string, plan: Plan, tz: string, raw: unknown): Promise<Response> {
  if (plan === "free") return errorResponse("plan_required", { minimum: "Plus" });
  const request = raw == null || raw === "" ? null : sanitizeUserText(raw, 200);
  if (raw != null && raw !== "" && !request) return errorResponse("invalid_input", { message: "Richiesta troppo lunga (massimo 200 caratteri)." });
  if (!await checkLimit(admin, userId, "shopping", EXTRA_AI_LIMITS.shopping, tz)) return errorResponse("quota_exceeded", { plan });

  const ctx = await loadContext(admin, userId, plan, tz);
  const out = await structured(shoppingSystemPrompt(ctx), [{
    type: "text", text: request ? `Richiesta dell'utente: <richiesta>${request}</richiesta>` : "Prepara la lista per i prossimi 3-4 giorni.",
  }], SHOPPING_SCHEMA);
  await recordAIEvent(admin, userId, "shopping");
  let list = filterSuggestions(sanitizeShopping(out), (ctx.profile.allergens ?? []) as Allergen[]);
  if (ctx.pregnancy) list = filterForPregnancy(list, ctx.profile.pregnancy?.toxoplasmosisImmune ?? null);
  return json({
    suggestions: list.map((s) => ({ id: crypto.randomUUID(), name: s.name, quantity: s.quantity ?? null,
      category: s.category ?? "other", reason: s.reason ?? null })),
  });
}

/** Profilo, obiettivi effettivi e pasti degli ultimi 7 giorni, nel fuso dell'utente. */
async function loadContext(admin: SupabaseClient, userId: string, plan: Plan, tz: string): Promise<CoachContext> {
  const now = new Date();
  const todayStart = startOfDay(now, tz);
  const weekStart = new Date(todayStart.getTime() - 7 * 86_400_000);
  const [profileRes, planRes, mealsRes] = await Promise.all([
    admin.from("profiles").select("profile, targets").eq("user_id", userId).maybeSingle(),
    admin.from("professional_plans").select("plan").eq("user_id", userId).maybeSingle(),
    admin.from("meals").select("type, items, logged_at").eq("user_id", userId)
      .gte("logged_at", weekStart.toISOString()).order("logged_at").limit(300),
  ]);
  for (const r of [profileRes, planRes, mealsRes]) if (r.error) throw new Error(`context: ${r.error.code}`);

  const profile = (profileRes.data?.profile ?? {}) as StoredProfile;
  const stored = (profileRes.data?.targets ?? null) as DailyTargets | null;
  const professional = (planRes.data?.plan ?? null) as ProfessionalPlan | null;
  const today = localDate(now, tz);
  const meals = (mealsRes.data ?? []) as { type: string; items: unknown; logged_at: string }[];
  const todayMeals = meals.filter((m) => Date.parse(m.logged_at) >= todayStart.getTime());
  const byDay = new Map<string, typeof meals>();
  for (const m of meals) {
    if (Date.parse(m.logged_at) >= todayStart.getTime()) continue;
    const d = localDate(new Date(m.logged_at), tz);
    byDay.set(d, [...(byDay.get(d) ?? []), m]);
  }
  const dayKcal = [...byDay.values()].map((ms) => summarizeMeals(ms).kcal).filter((k) => k > 0);
  return {
    profile,
    targets: effectiveTargets(profile, stored, professional, plan, today),
    today: summarizeMeals(todayMeals),
    weekAverageKcal: dayKcal.length ? Math.round(dayKcal.reduce((a, b) => a + b, 0) / dayKcal.length) : null,
    loggedDaysLastWeek: dayKcal.length,
    hasProfessionalPlan: professional !== null,
    pregnancy: activePregnancy(profile, today),
    localTime: localTime(now, tz),
  };
}
