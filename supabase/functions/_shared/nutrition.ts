/**
 * Calcoli energetici lato server. Algoritmo identico a
 * ios/Packages/CaloScanCore/Sources/CaloScanCore/Nutrition/EnergyCalculator.swift.
 * Il server lo usa per validare gli obiettivi salvati dal client (mai sotto le soglie minime).
 */

export type BiologicalSex = "male" | "female" | "unspecified";
export type ActivityLevel =
  | "sedentary" | "lightly_active" | "moderately_active" | "very_active" | "extremely_active";
export type NutritionGoal =
  | "lose_weight" | "maintain" | "gain_muscle" | "improve_quality" | "track_only";
export type DietPreference =
  | "omnivore" | "vegetarian" | "vegan" | "mediterranean" | "low_carb" | "other";

export interface BodyMetrics {
  ageYears: number;
  sex: BiologicalSex;
  heightCm: number;
  weightKg: number;
}

export interface DailyTargets {
  bmr: number;
  tdee: number;
  calorieTarget: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  isAdjustedForSafety: boolean;
}

export const ACTIVITY_MULTIPLIER: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  lightly_active: 1.375,
  moderately_active: 1.55,
  very_active: 1.725,
  extremely_active: 1.9,
};

export function validateMetrics(m: BodyMetrics): void {
  if (!Number.isInteger(m.ageYears) || m.ageYears < 13 || m.ageYears > 100) throw new RangeError("age");
  if (!(m.heightCm >= 100 && m.heightCm <= 250)) throw new RangeError("height");
  if (!(m.weightKg >= 30 && m.weightKg <= 350)) throw new RangeError("weight");
}

export function bmr(m: BodyMetrics): number {
  const base = 10 * m.weightKg + 6.25 * m.heightCm - 5 * m.ageYears;
  switch (m.sex) {
    case "male": return base + 5;
    case "female": return base - 161;
    default: return base - 78;
  }
}

export function calorieFloor(sex: BiologicalSex): number {
  return sex === "male" ? 1500 : sex === "female" ? 1200 : 1350;
}

export function targets(
  m: BodyMetrics,
  activity: ActivityLevel,
  goal: NutritionGoal,
  diet: DietPreference = "omnivore",
): DailyTargets {
  validateMetrics(m);
  const bmrValue = bmr(m);
  const tdeeValue = bmrValue * ACTIVITY_MULTIPLIER[activity];

  const effectiveGoal: NutritionGoal = m.ageYears < 18 && goal === "lose_weight" ? "maintain" : goal;

  let target: number;
  if (effectiveGoal === "lose_weight") target = tdeeValue - Math.min(tdeeValue * 0.15, 500);
  else if (effectiveGoal === "gain_muscle") target = tdeeValue + Math.min(tdeeValue * 0.10, 300);
  else target = tdeeValue;

  const floor = Math.max(bmrValue, calorieFloor(m.sex));
  let adjusted = effectiveGoal !== goal;
  if (target < floor) { target = floor; adjusted = true; }

  const proteinPerKg = effectiveGoal === "lose_weight" ? 1.8 : effectiveGoal === "gain_muscle" ? 2.0 : 1.6;
  const protein = Math.min(m.weightKg * Math.min(proteinPerKg, 2.2), (target * 0.35) / 4);
  const fatShare = diet === "low_carb" ? 0.35 : 0.30;
  const fat = Math.max((target * fatShare) / 9, m.weightKg * 0.6);
  const carbs = Math.max((target - protein * 4 - fat * 9) / 4, 0);

  // Math.round arrotonda .5 verso +∞ come `.rounded()` di Swift per valori positivi.
  return {
    bmr: Math.round(bmrValue),
    tdee: Math.round(tdeeValue),
    calorieTarget: Math.round(target),
    proteinG: Math.round(protein),
    carbsG: Math.round(carbs),
    fatG: Math.round(fat),
    isAdjustedForSafety: adjusted,
  };
}

export function isSafeManualTarget(kcal: number, m: BodyMetrics): boolean {
  return kcal >= calorieFloor(m.sex) && kcal <= 6000;
}

// ---------------------------------------------------------------------------
// Piano indicato da un professionista sanitario (stesse regole di ProfessionalPlan.swift).

export type HealthProfessional = "doctor" | "dietitian" | "nutritionist";

export interface ProfessionalPlan {
  professional: HealthProfessional;
  professionalName?: string | null;
  calorieTarget: number;
  proteinG?: number | null;
  carbsG?: number | null;
  fatG?: number | null;
  notes?: string | null;
  startDate: string; // ISO 8601
  reviewDate?: string | null;
  confirmedAt: string;
}

export type ProfessionalPlanIssue =
  | "caloriesOutOfRange"
  | "macroOutOfRange"
  | "macrosDoNotMatchCalories"
  | "notesTooLong"
  | "nameTooLong"
  | "reviewBeforeStart";

export const PROFESSIONAL_PLAN_LIMITS = {
  minKcal: 800,
  maxKcal: 6000,
  maxMacroG: 1000,
  notesMaxLength: 1000,
  nameMaxLength: 80,
  macroTolerance: 0.15,
} as const;

const chars = (s?: string | null) => (s ? [...s].length : 0);

export function validateProfessionalPlan(p: ProfessionalPlan): ProfessionalPlanIssue[] {
  const L = PROFESSIONAL_PLAN_LIMITS;
  const issues: ProfessionalPlanIssue[] = [];
  if (!Number.isInteger(p.calorieTarget) || p.calorieTarget < L.minKcal || p.calorieTarget > L.maxKcal) {
    issues.push("caloriesOutOfRange");
  }
  const macros = [p.proteinG, p.carbsG, p.fatG].filter((v): v is number => v != null);
  if (macros.some((v) => !Number.isInteger(v) || v < 0 || v > L.maxMacroG)) issues.push("macroOutOfRange");
  if (p.proteinG != null && p.carbsG != null && p.fatG != null && p.calorieTarget > 0) {
    const fromMacros = p.proteinG * 4 + p.carbsG * 4 + p.fatG * 9;
    if (Math.abs(fromMacros - p.calorieTarget) / p.calorieTarget > L.macroTolerance) {
      issues.push("macrosDoNotMatchCalories");
    }
  }
  if (chars(p.notes) > L.notesMaxLength) issues.push("notesTooLong");
  if (chars(p.professionalName) > L.nameMaxLength) issues.push("nameTooLong");
  if (p.reviewDate && Date.parse(p.reviewDate) < Date.parse(p.startDate)) issues.push("reviewBeforeStart");
  return issues;
}

/** Obiettivi effettivi: i macro non indicati seguono le proporzioni degli obiettivi calcolati. */
export function professionalPlanTargets(p: ProfessionalPlan, fallback: DailyTargets | null): DailyTargets {
  const kcal = p.calorieTarget;
  const baseKcal = Math.max(fallback?.calorieTarget ?? 0, 1);
  const proteinShare = fallback ? (fallback.proteinG * 4) / baseKcal : 0.25;
  const fatShare = fallback ? (fallback.fatG * 9) / baseKcal : 0.3;
  const proteinG = p.proteinG ?? Math.round((kcal * proteinShare) / 4);
  const fatG = p.fatG ?? Math.round((kcal * fatShare) / 9);
  const carbsG = p.carbsG ?? Math.max(Math.round((kcal - proteinG * 4 - fatG * 9) / 4), 0);
  return {
    bmr: fallback?.bmr ?? 0, tdee: fallback?.tdee ?? 0, calorieTarget: kcal,
    proteinG, carbsG, fatG, isAdjustedForSafety: false,
  };
}

// ---------------------------------------------------------------------------
// Descrizione testuale del pasto (stesse regole di FoodDescription in ProfessionalPlan.swift).

export const FOOD_DESCRIPTION_LIMITS = { minLength: 3, maxLength: 500 } as const;

export function sanitizeFoodDescription(text: unknown): string | null {
  if (typeof text !== "string") return null;
  const cleaned = text.replace(/[\p{Cc}\p{Cf}]/gu, " ").split(/\s+/u).filter(Boolean).join(" ");
  const n = [...cleaned].length;
  if (n < FOOD_DESCRIPTION_LIMITS.minLength || n > FOOD_DESCRIPTION_LIMITS.maxLength) return null;
  if (!/\p{L}/u.test(cleaned)) return null;
  return cleaned;
}
