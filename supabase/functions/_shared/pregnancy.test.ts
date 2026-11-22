// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/pregnancy.test.ts
// Stessi casi di PregnancyTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import { checkPregnancyFood, filterForPregnancy, isValidDueDate, pregnancyTargets, pregnancyWeek, trimester } from "./pregnancy.ts";

test("gravidanza: alimenti da evitare", () => {
  const avoid: [string, string][] = [
    ["Prosciutto crudo di Parma", "toxoplasmosis"], ["Vino rosso", "alcohol"], ["Gin tonic", "alcohol"],
    ["Sushi misto", "listeria"], ["Salmone affumicato", "listeria"], ["Tiramisù", "salmonella"],
    ["Gorgonzola", "listeria"], ["Pesce spada alla griglia", "mercury"], ["Paté di fegato", "vitamin_a"],
    ["Pancetta cruda", "toxoplasmosis"],
  ];
  for (const [name, risk] of avoid) assert.deepEqual(checkPregnancyFood(name), { level: "avoid", risk }, name);
});

test("gravidanza: alimenti da limitare", () => {
  assert.deepEqual(checkPregnancyFood("Tonno in scatola"), { level: "limit", risk: "mercury" });
  assert.deepEqual(checkPregnancyFood("Caffè espresso"), { level: "limit", risk: "caffeine" });
  assert.deepEqual(checkPregnancyFood("Coca Cola"), { level: "limit", risk: "caffeine" });
});

test("gravidanza: nessun falso allarme sui casi comuni", () => {
  for (const n of ["Prosciutto cotto", "Birra analcolica", "Salmone al forno", "Mozzarella", "Uova strapazzate",
    "Pizza ai 4 formaggi con gorgonzola al forno", "Caffè decaffeinato", "Salame cotto", "Mele", "Pane di frumento",
    "Cioccolato fondente", "Lievito di birra", "Salame di cioccolato", "Spaghetti alla carbonara con guanciale",
    "Coppa di gelato"]) {
    assert.equal(checkPregnancyFood(n), null, n);
  }
});

test("gravidanza: immunità alla toxoplasmosi", () => {
  assert.deepEqual(checkPregnancyFood("Bresaola", true), { level: "limit", risk: "listeria" });
  assert.deepEqual(checkPregnancyFood("Bresaola", null), { level: "avoid", risk: "toxoplasmosis" });
  assert.deepEqual(checkPregnancyFood("Carne cruda", true), { level: "avoid", risk: "toxoplasmosis" });
  const items = [{ name: "Sushi" }, { name: "Tonno" }, { name: "Mele" }];
  assert.deepEqual(filterForPregnancy(items, null).map((i) => i.name), ["Tonno", "Mele"]);
});

test("gravidanza: settimane e trimestri", () => {
  assert.equal(pregnancyWeek("2027-05-01", "2026-11-22"), 17);
  assert.equal(pregnancyWeek("2026-11-22", "2026-11-22"), 40);
  assert.equal(pregnancyWeek("2027-08-29", "2026-11-22"), 1);
  assert.equal(pregnancyWeek("2027-02-14", "2026-11-22"), 28);
  assert.deepEqual([13, 14, 27, 28].map(trimester), [1, 2, 2, 3]);
  assert.equal(isValidDueDate("2027-05-01", "2026-11-22"), true);
  assert.equal(isValidDueDate("2026-11-21", "2026-11-22"), false);
  assert.equal(isValidDueDate("2027-09-20", "2026-11-22"), false);
});

test("gravidanza: obiettivi mai in deficit, EFSA per trimestre", () => {
  const m = { ageYears: 30, sex: "female" as const, heightCm: 165, weightKg: 60 };
  assert.deepEqual(pregnancyTargets(m, "lightly_active", "omnivore", 1),
    { bmr: 1320, tdee: 1815, calorieTarget: 1885, proteinG: 97, carbsG: 233, fatG: 63, isAdjustedForSafety: false });
  assert.deepEqual(pregnancyTargets(m, "lightly_active", "omnivore", 2),
    { bmr: 1320, tdee: 1815, calorieTarget: 2075, proteinG: 105, carbsG: 258, fatG: 69, isAdjustedForSafety: false });
  assert.deepEqual(pregnancyTargets(m, "lightly_active", "omnivore", 3),
    { bmr: 1320, tdee: 1815, calorieTarget: 2315, proteinG: 124, carbsG: 281, fatG: 77, isAdjustedForSafety: false });
});
