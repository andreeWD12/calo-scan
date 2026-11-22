// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/nutrition.test.ts
// (oppure `deno test`). Stessi casi di EnergyCalculatorTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bmr, isSafeManualTarget, professionalPlanTargets, sanitizeFoodDescription, targets, validateProfessionalPlan,
} from "./nutrition.ts";

test("BMR uomo", () => {
  assert.equal(bmr({ ageYears: 30, sex: "male", heightCm: 180, weightKg: 80 }), 1780);
});

test("BMR donna", () => {
  assert.equal(bmr({ ageYears: 30, sex: "female", heightCm: 165, weightKg: 60 }), 1320.25);
});

test("uomo moderatamente attivo, perdita peso", () => {
  const t = targets({ ageYears: 30, sex: "male", heightCm: 180, weightKg: 80 }, "moderately_active", "lose_weight");
  assert.deepEqual(t, {
    bmr: 1780, tdee: 2759, calorieTarget: 2345, proteinG: 144, carbsG: 266, fatG: 78,
    isAdjustedForSafety: false,
  });
});

test("soglia minima applicata", () => {
  const t = targets({ ageYears: 70, sex: "female", heightCm: 150, weightKg: 45 }, "sedentary", "lose_weight");
  assert.equal(t.calorieTarget, 1200);
  assert.equal(t.isAdjustedForSafety, true);
});

test("minorenne: nessun deficit", () => {
  const t = targets({ ageYears: 16, sex: "male", heightCm: 175, weightKg: 70 }, "moderately_active", "lose_weight");
  assert.equal(t.calorieTarget, t.tdee);
  assert.equal(t.isAdjustedForSafety, true);
});

test("dati non validi rifiutati", () => {
  assert.throws(() => targets({ ageYears: 30, sex: "male", heightCm: 20, weightKg: 80 }, "sedentary", "maintain"));
});

test("obiettivo manuale sotto soglia rifiutato", () => {
  const m = { ageYears: 30, sex: "female" as const, heightCm: 165, weightKg: 60 };
  assert.equal(isSafeManualTarget(1000, m), false);
  assert.equal(isSafeManualTarget(1800, m), true);
});

const plan = (over = {}) => ({
  professional: "doctor" as const, calorieTarget: 1600, startDate: "2026-11-01T00:00:00Z",
  confirmedAt: "2026-11-01T00:00:00Z", ...over,
});

test("piano del professionista valido", () => {
  assert.deepEqual(validateProfessionalPlan(plan()), []);
  assert.deepEqual(validateProfessionalPlan(plan({ calorieTarget: 1000 })), []);
});

test("piano: calorie fuori intervallo", () => {
  assert.deepEqual(validateProfessionalPlan(plan({ calorieTarget: 700 })), ["caloriesOutOfRange"]);
  assert.deepEqual(validateProfessionalPlan(plan({ calorieTarget: 6500 })), ["caloriesOutOfRange"]);
});

test("piano: macro incoerenti con le calorie", () => {
  assert.deepEqual(validateProfessionalPlan(plan({ proteinG: 100, carbsG: 180, fatG: 53 })), []);
  assert.deepEqual(validateProfessionalPlan(plan({ proteinG: 200, carbsG: 300, fatG: 100 })), ["macrosDoNotMatchCalories"]);
});

test("piano: data di controllo prima dell'inizio", () => {
  assert.deepEqual(validateProfessionalPlan(plan({ reviewDate: "2026-10-01T00:00:00Z" })), ["reviewBeforeStart"]);
});

test("piano: macro mancanti seguono le proporzioni calcolate", () => {
  const base = { bmr: 1400, tdee: 2000, calorieTarget: 2000, proteinG: 125, carbsG: 225, fatG: 67, isAdjustedForSafety: false };
  assert.deepEqual(professionalPlanTargets(plan(), base), {
    bmr: 1400, tdee: 2000, calorieTarget: 1600, proteinG: 100, carbsG: 179, fatG: 54, isAdjustedForSafety: false,
  });
  assert.deepEqual(professionalPlanTargets(plan({ proteinG: 90 }), null), {
    bmr: 0, tdee: 0, calorieTarget: 1600, proteinG: 90, carbsG: 191, fatG: 53, isAdjustedForSafety: false,
  });
});

test("descrizione del pasto ripulita e validata", () => {
  assert.equal(sanitizeFoodDescription("  pasta al pomodoro\n\t 80 g  "), "pasta al pomodoro 80 g");
  assert.equal(sanitizeFoodDescription("ok"), null);
  assert.equal(sanitizeFoodDescription("123 456"), null);
  assert.equal(sanitizeFoodDescription("a".repeat(501)), null);
  assert.equal(sanitizeFoodDescription(42), null);
});
