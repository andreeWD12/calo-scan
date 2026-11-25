/**
 * Validazione di profilo e obiettivi prima del salvataggio (funzione save-profile).
 * Stesse regole dell'app: età minima dell'account (AgePolicy), intervalli di BodyMetrics,
 * obiettivo calorico mai sotto la soglia minima né sopra 6000 kcal (isSafeManualTarget).
 * Il server non si fida del client: un obiettivo non sicuro viene rifiutato, non corretto in silenzio.
 */
import {
  type ActivityLevel, type BiologicalSex, type BodyMetrics, type DailyTargets, type DietPreference,
  isSafeManualTarget, type NutritionGoal, validateMetrics,
} from "./nutrition.ts";

/** Uguale ad `AgePolicy.minimumAccountAge` (Swift): soglia più alta tra gli Stati UE (art. 8 GDPR). */
export const MINIMUM_ACCOUNT_AGE = 16;
export const MAX_NOTE_LENGTH = 500;
export const MAX_NAME_LENGTH = 50;

const SEXES: BiologicalSex[] = ["male", "female", "unspecified"];
const ACTIVITIES: ActivityLevel[] = ["sedentary", "lightly_active", "moderately_active", "very_active", "extremely_active"];
const GOALS: NutritionGoal[] = ["lose_weight", "maintain", "gain_muscle", "improve_quality", "track_only"];
const DIETS: DietPreference[] = ["omnivore", "vegetarian", "vegan", "mediterranean", "low_carb", "other"];
const ALLERGENS = [
  "gluten", "milk", "lactose", "eggs", "fish", "shellfish", "molluscs", "peanuts", "tree_nuts", "soy",
  "celery", "mustard", "sesame", "sulphites", "lupin", "other",
];

export type ProfileIssue =
  | "invalid_name" | "invalid_birth_date" | "under_minimum_age" | "invalid_metrics" | "invalid_enum"
  | "note_too_long" | "invalid_targets" | "unsafe_calorie_target";

/** Età compiuta alla data `today` (YYYY-MM-DD), come `BodyMetrics.age` in Swift. */
export function ageOn(birthISO: string, today: string): number | null {
  const b = /^(\d{4})-(\d{2})-(\d{2})/.exec(birthISO);
  const t = /^(\d{4})-(\d{2})-(\d{2})/.exec(today);
  if (!b || !t) return null;
  const [by, bm, bd] = [+b[1], +b[2], +b[3]];
  const [ty, tm, td] = [+t[1], +t[2], +t[3]];
  let age = ty - by;
  if (tm < bm || (tm === bm && td < bd)) age--;
  return age;
}

const isText = (v: unknown, max: number) => v === undefined || v === null || (typeof v === "string" && v.length <= max);
const isWholeNonNegative = (v: unknown) => Number.isInteger(v) && (v as number) >= 0;

/** Ritorna i problemi trovati (vuoto = valido). `today` in formato YYYY-MM-DD. */
export function validateProfilePayload(profile: unknown, targets: unknown, today: string): ProfileIssue[] {
  const issues: ProfileIssue[] = [];
  if (typeof profile !== "object" || profile === null) return ["invalid_metrics"];
  const p = profile as Record<string, unknown>;

  if (typeof p.displayName !== "string" || p.displayName.trim().length === 0 || p.displayName.length > MAX_NAME_LENGTH) {
    issues.push("invalid_name");
  }

  // La data arriva come istante (fuso orario del telefono): un giorno di tolleranza evita di
  // rifiutare per errore chi compie gli anni oggi. Il controllo esatto lo fa già l'app.
  const birth = typeof p.birthDate === "string" ? Date.parse(p.birthDate) : NaN;
  const age = Number.isNaN(birth) ? null : ageOn(new Date(birth - 86_400_000).toISOString(), today);
  if (age === null) issues.push("invalid_birth_date");
  else if (age < MINIMUM_ACCOUNT_AGE) issues.push("under_minimum_age");

  if (!SEXES.includes(p.sex as BiologicalSex) || !ACTIVITIES.includes(p.activity as ActivityLevel)
    || !GOALS.includes(p.goal as NutritionGoal) || !DIETS.includes(p.diet as DietPreference)
    || !Array.isArray(p.allergens) || !p.allergens.every((a) => ALLERGENS.includes(a as string))) {
    issues.push("invalid_enum");
  }

  if (![p.otherDietNote, p.otherAllergyNote, p.dietaryNotes].every((n) => isText(n, MAX_NOTE_LENGTH))) {
    issues.push("note_too_long");
  }

  let metrics: BodyMetrics | null = null;
  if (age !== null && age >= MINIMUM_ACCOUNT_AGE) {
    try {
      metrics = { ageYears: age, sex: p.sex as BiologicalSex, heightCm: p.heightCm as number, weightKg: p.weightKg as number };
      validateMetrics(metrics);
    } catch {
      metrics = null;
      issues.push("invalid_metrics");
    }
  }
  if (p.targetWeightKg !== undefined && p.targetWeightKg !== null
    && !(typeof p.targetWeightKg === "number" && p.targetWeightKg >= 30 && p.targetWeightKg <= 350)) {
    issues.push("invalid_metrics");
  }

  if (typeof targets !== "object" || targets === null) {
    issues.push("invalid_targets");
  } else {
    const t = targets as Record<string, unknown>;
    const ints = [t.bmr, t.tdee, t.calorieTarget, t.proteinG, t.carbsG, t.fatG];
    if (!ints.every(isWholeNonNegative) || typeof t.isAdjustedForSafety !== "boolean") {
      issues.push("invalid_targets");
    } else if (metrics && !isSafeManualTarget(t.calorieTarget as number, metrics)) {
      issues.push("unsafe_calorie_target");
    }
  }
  return [...new Set(issues)];
}

/** Solo i campi attesi di DailyTargets, per non salvare chiavi arbitrarie inviate dal client. */
export function pickTargets(t: DailyTargets): DailyTargets {
  return {
    bmr: t.bmr, tdee: t.tdee, calorieTarget: t.calorieTarget, proteinG: t.proteinG,
    carbsG: t.carbsG, fatG: t.fatG, isAdjustedForSafety: t.isAdjustedForSafety,
  };
}
