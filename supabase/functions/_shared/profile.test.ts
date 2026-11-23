import { test } from "node:test";
import assert from "node:assert/strict";
import { ageOn, pickTargets, validateProfilePayload } from "./profile.ts";

const today = "2026-11-23";
const profile = {
  displayName: "Giulia", birthDate: "1994-05-10T00:00:00Z", sex: "female", heightCm: 165, weightKg: 60,
  targetWeightKg: 57, activity: "lightly_active", goal: "lose_weight", diet: "mediterranean",
  allergens: ["gluten", "tree_nuts"], dietaryNotes: null,
};
const targets = { bmr: 1320, tdee: 1815, calorieTarget: 1543, proteinG: 108, carbsG: 170, fatG: 51, isAdjustedForSafety: false };

test("profilo: età compiuta", () => {
  assert.equal(ageOn("2010-11-23T00:00:00Z", today), 16);
  assert.equal(ageOn("2010-11-24T00:00:00Z", today), 15);
  assert.equal(ageOn("non-una-data", today), null);
});

test("profilo: valido", () => {
  assert.deepEqual(validateProfilePayload(profile, targets, today), []);
});

test("profilo: età minima 16 anni", () => {
  assert.deepEqual(validateProfilePayload({ ...profile, birthDate: "2011-01-01T00:00:00Z" }, targets, today), ["under_minimum_age"]);
  // Compie 16 anni oggi: data salvata come mezzanotte italiana (23:00 UTC del giorno prima).
  assert.deepEqual(validateProfilePayload({ ...profile, birthDate: "2010-11-22T23:00:00Z" }, targets, today), []);
  assert.deepEqual(validateProfilePayload({ ...profile, birthDate: "2010-11-25T10:00:00Z" }, targets, today), ["under_minimum_age"]);
  assert.deepEqual(validateProfilePayload({ ...profile, birthDate: "ieri" }, targets, today), ["invalid_birth_date"]);
});

test("profilo: obiettivo calorico sotto la soglia minima o oltre 6000 kcal", () => {
  assert.deepEqual(validateProfilePayload(profile, { ...targets, calorieTarget: 1100 }, today), ["unsafe_calorie_target"]);
  assert.deepEqual(validateProfilePayload(profile, { ...targets, calorieTarget: 6500 }, today), ["unsafe_calorie_target"]);
  assert.deepEqual(validateProfilePayload({ ...profile, sex: "male" }, { ...targets, calorieTarget: 1400 }, today), ["unsafe_calorie_target"]);
});

test("profilo: valori non validi", () => {
  assert.deepEqual(validateProfilePayload({ ...profile, heightCm: 90 }, targets, today), ["invalid_metrics"]);
  assert.deepEqual(validateProfilePayload({ ...profile, diet: "keto" }, targets, today), ["invalid_enum"]);
  assert.deepEqual(validateProfilePayload({ ...profile, allergens: ["gluten", "x"] }, targets, today), ["invalid_enum"]);
  assert.deepEqual(validateProfilePayload({ ...profile, displayName: " " }, targets, today), ["invalid_name"]);
  assert.deepEqual(validateProfilePayload({ ...profile, dietaryNotes: "a".repeat(501) }, targets, today), ["note_too_long"]);
  assert.deepEqual(validateProfilePayload(profile, { ...targets, proteinG: 10.5 }, today), ["invalid_targets"]);
  assert.deepEqual(validateProfilePayload(null, targets, today), ["invalid_metrics"]);
});

test("profilo: solo i campi attesi degli obiettivi", () => {
  assert.deepEqual(pickTargets({ ...targets, extra: 1 } as typeof targets), targets);
});
