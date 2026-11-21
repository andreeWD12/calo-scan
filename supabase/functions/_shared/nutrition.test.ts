// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/nutrition.test.ts
// (oppure `deno test`). Stessi casi di EnergyCalculatorTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import { bmr, isSafeManualTarget, targets } from "./nutrition.ts";

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
