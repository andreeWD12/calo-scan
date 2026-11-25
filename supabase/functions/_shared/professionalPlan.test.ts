import { test } from "node:test";
import assert from "node:assert/strict";
import { validateProfessionalPlanPayload } from "./professionalPlan.ts";

const plan = {
  professional: "dietitian", professionalName: "Dott.ssa Rossi", calorieTarget: 1800,
  proteinG: 110, carbsG: 200, fatG: 62, notes: null,
  startDate: "2026-11-23T00:00:00Z", reviewDate: "2027-01-23T00:00:00Z", confirmedAt: "2026-11-23T10:00:00Z",
  mealPlan: [{ week: 1, weekday: null, meals: [{ type: "breakfast", foods: [{ id: "a", name: "Yogurt greco", grams: 170 }] }] }],
  rotationWeeks: 1, rotationAnchor: null,
};

test("piano: valido", () => {
  assert.deepEqual(validateProfessionalPlanPayload(plan), []);
});

test("piano: forma non valida", () => {
  assert.deepEqual(validateProfessionalPlanPayload(null), ["invalid_shape"]);
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, professional: "coach" }), ["invalid_shape"]);
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, startDate: "ieri" }), ["invalid_shape"]);
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, mealPlan: [{ weekday: 1, meals: "no" }] }), ["invalid_shape"]);
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, proteinG: 10.5 }), ["invalid_shape"]);
});

test("piano: regole dell'app", () => {
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, calorieTarget: 600, proteinG: null, carbsG: null, fatG: null }),
    ["caloriesOutOfRange"]);
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, proteinG: 300 }), ["macrosDoNotMatchCalories"]);
  assert.deepEqual(validateProfessionalPlanPayload({ ...plan, reviewDate: "2026-01-01T00:00:00Z" }), ["reviewBeforeStart"]);
  const tooHeavy = { ...plan, mealPlan: [{ week: 1, weekday: null, meals: [{ type: "lunch", foods: [{ id: "b", name: "Pasta", grams: 5000 }] }] }] };
  assert.deepEqual(validateProfessionalPlanPayload(tooHeavy), ["mealPlanInvalid"]);
});
