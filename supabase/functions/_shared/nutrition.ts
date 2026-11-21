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
