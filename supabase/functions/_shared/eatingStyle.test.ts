// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/eatingStyle.test.ts
// Stessi casi di EatingStyleTests.swift, più il filtro dell'output del modello.
import { test } from "node:test";
import assert from "node:assert/strict";
import { allowedStyles, EATING_STYLES, isEatingAt, NEUTRAL_REASON, sanitizeProposals, styleBlocks } from "./eatingStyle.ts";

const none = { pregnantOrBreastfeeding: false, diabetesMedication: false, eatingDisorderHistory: false, medicalSupervision: false };

test("stili: adulto senza rischi vede tutto il catalogo", () => {
  assert.deepEqual(allowedStyles(30, 23, none, false), [...EATING_STYLES]);
});

test("stili: digiuno escluso sotto i 18 anni e con BMI basso", () => {
  assert.deepEqual(styleBlocks("fasting_16_8", 17, 22, none, false), ["under_age"]);
  assert.deepEqual(styleBlocks("fasting_12_12", 25, 18.2, none, false), ["low_bmi"]);
  assert.deepEqual(styleBlocks("mediterranean", 16, 17, none, false), []);
});

test("stili: le risposte di sicurezza escludono solo gli stili restrittivi", () => {
  assert.deepEqual(allowedStyles(30, 22, { ...none, eatingDisorderHistory: true }, false),
    ["balanced", "mediterranean", "high_protein", "vegetarian", "vegan"]);
  assert.deepEqual(styleBlocks("moderate_low_carb", 30, 22, { ...none, pregnantOrBreastfeeding: true, diabetesMedication: true }, false),
    ["pregnancy", "diabetes_medication"]);
});

test("stili: il piano del professionista ha la priorità", () => {
  assert.deepEqual(allowedStyles(30, 22, none, true), []);
});

test("finestra alimentare", () => {
  assert.equal(isEatingAt(11 * 60 + 59, 720, 8), false);
  assert.equal(isEatingAt(12 * 60, 720, 8), true);
  assert.equal(isEatingAt(19 * 60 + 59, 720, 8), true);
  assert.equal(isEatingAt(20 * 60, 720, 8), false);
  assert.equal(isEatingAt(23 * 60 + 30, 1200, 10), true);
  assert.equal(isEatingAt(5 * 60 + 59, 1200, 10), true);
  assert.equal(isEatingAt(6 * 60, 1200, 10), false);
});

test("proposte del coach filtrate", () => {
  const allowed = allowedStyles(30, 22, { ...none, eatingDisorderHistory: true }, false);
  const out = sanitizeProposals([
    { style: "fasting_16_8", reason: "Ideale per te" },              // non ammesso
    { style: "keto", reason: "x" },                                  // fuori catalogo
    { style: "mediterranean", reason: "Brucia grassi e previene le malattie", firstSteps: ["Più legumi", "Detox serale"] },
    { style: "mediterranean", reason: "doppione" },
    { style: "high_protein", reason: "  Ti alleni 3 volte\na settimana  ", firstSteps: ["a", "b", "c", "d"] },
    { style: "balanced", reason: 42 },
    { style: "vegan", reason: "quarta proposta" },
  ], allowed);
  assert.deepEqual(out.map((p) => p.style), ["mediterranean", "high_protein", "balanced"]);
  assert.equal(out[0].reason, NEUTRAL_REASON.mediterranean);
  assert.deepEqual(out[0].firstSteps, ["Più legumi"]);
  assert.equal(out[1].reason, "Ti alleni 3 volte a settimana");
  assert.equal(out[1].firstSteps.length, 3);
  assert.equal(out[2].reason, NEUTRAL_REASON.balanced);
  assert.deepEqual(sanitizeProposals("nope", allowed), []);
});
