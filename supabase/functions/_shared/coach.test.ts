// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/coach.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  activePregnancy, coachSystemPrompt, contextBlock, effectiveTargets, localDate, safetyTopic, sanitizeCoachReply,
  sanitizeShopping, sanitizeUserText, summarizeMeals, toTurns, type CoachContext,
} from "./coach.ts";
import { COACH_LIMITS } from "./scan.ts";

const stored = { bmr: 1400, tdee: 2000, calorieTarget: 1700, proteinG: 110, carbsG: 190, fatG: 55, isAdjustedForSafety: false };
const profile = { displayName: "Andrea", birthDate: "1995-05-10T00:00:00Z", sex: "female" as const, heightCm: 165, weightKg: 60,
  activity: "lightly_active" as const, goal: "lose_weight", diet: "omnivore" as const, allergens: ["milk"] };

test("coach: chat solo per Plus e Pro", () => {
  assert.deepEqual(COACH_LIMITS, { free: 0, plus: 30, pro: 150 });
});

test("coach: testo dell'utente ripulito e limitato", () => {
  assert.equal(sanitizeUserText("  ciao\u0000 coach  "), "ciao coach");
  assert.equal(sanitizeUserText("   "), null);
  assert.equal(sanitizeUserText("a".repeat(1001)), null);
  assert.equal(sanitizeUserText(42), null);
});

test("coach: richieste a rischio non vanno al modello", () => {
  assert.equal(safetyTopic("a volte penso al suicidio"), "crisis");
  assert.equal(safetyTopic("mi faccio vomitare dopo cena"), "eating_disorder");
  assert.equal(safetyTopic("voglio stare a 600 kcal al giorno"), "extreme_restriction");
  assert.equal(safetyTopic("posso fare un digiuno di 5 giorni?"), "eating_disorder");
  assert.equal(safetyTopic("cosa mangio stasera con 600 kcal rimaste?"), null);
  assert.equal(safetyTopic("Quante calorie mi rimangono oggi?"), null);
});

test("coach: totali del giorno dai pasti", () => {
  const s = summarizeMeals([
    { type: "lunch", items: [{ grams: 80, food: { name: "Fusilli", per100g: { kcal: 350, proteinG: 12, carbsG: 72, fatG: 1.5 } } }] },
    { type: "lunch", items: [{ grams: 10, food: { name: "Olio d'oliva", per100g: { kcal: 884, proteinG: 0, carbsG: 0, fatG: 100 } } }] },
    { type: "dinner", items: "rotto" },
  ]);
  assert.equal(s.kcal, 368);
  assert.equal(s.fatG, 11);
  assert.deepEqual(s.foods.lunch, ["Fusilli 80 g", "Olio d'oliva 10 g"]);
});

test("coach: obiettivi effettivi", () => {
  assert.equal(effectiveTargets(profile, stored, null, "plus", "2026-11-24"), stored);
  const pp = { calorieTarget: 1900, proteinG: 120, carbsG: null, fatG: null } as never;
  assert.equal(effectiveTargets(profile, stored, pp, "plus", "2026-11-24")?.calorieTarget, 1900);
  const pregnant = { ...profile, pregnancy: { dueDate: "2027-04-01T00:00:00Z" } };
  assert.ok(activePregnancy(pregnant, "2026-11-24"));
  const plus = effectiveTargets(pregnant, stored, null, "plus", "2026-11-24")!;
  const pro = effectiveTargets(pregnant, stored, null, "pro", "2026-11-24")!;
  assert.ok(plus.calorieTarget > stored.calorieTarget, "in gravidanza mai in deficit");
  assert.ok(pro.calorieTarget > plus.calorieTarget, "Pro aggiunge il fabbisogno del trimestre");
  assert.equal(activePregnancy({ ...profile, pregnancy: { dueDate: "2020-01-01" } }, "2026-11-24"), null);
});

const ctx: CoachContext = {
  profile, targets: stored, today: summarizeMeals([]), weekAverageKcal: 1650, loggedDaysLastWeek: 5,
  hasProfessionalPlan: false, pregnancy: null, localTime: "19:30",
};

test("coach: contesto con allergeni, soglia e dati tra tag", () => {
  const block = contextBlock(ctx);
  assert.match(block, /^<dati_utente>/);
  assert.match(block, /da escludere sempre\): milk/);
  assert.match(block, /Nessun pasto registrato oggi/);
  assert.match(coachSystemPrompt(ctx), /meno di 1200 kcal/);
  assert.match(coachSystemPrompt({ ...ctx, hasProfessionalPlan: true }), /non modificarlo/);
});

test("coach: turni alternati che iniziano dall'utente", () => {
  const t = toTurns([{ role: "assistant", text: "x" }, { role: "user", text: "a" }, { role: "user", text: "b" }, { role: "assistant", text: "c" }], "d");
  assert.deepEqual(t.map((x) => x.role), ["user", "assistant", "user"]);
  assert.equal(t[0].text, "a\n\nb");
});

test("coach: risposta ripulita e limitata", () => {
  assert.match(sanitizeCoachReply(""), /Non sono riuscito/);
  assert.ok([...sanitizeCoachReply("parola ".repeat(600))].length <= 2501);
});

test("coach: lista della spesa ripulita", () => {
  const list = sanitizeShopping({ items: [{ name: "Lenticchie", quantity: "500 g", category: "pantry", reason: "Proteine" },
    { name: "", category: "x" }, { name: "Mele", category: "boh" }] });
  assert.equal(list.length, 2);
  assert.equal(list[1].category, "other");
});

test("coach: data locale", () => {
  assert.equal(localDate(new Date("2026-11-24T23:30:00Z"), "Europe/Rome"), "2026-11-25");
});
