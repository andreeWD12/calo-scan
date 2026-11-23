import { test } from "node:test";
import assert from "node:assert/strict";
import { aiEstimateFood, cleanProductName, isLatinName, fromOFF, fromUSDA, isBarcode, normalizeQuery, stableUUID } from "./foods.ts";

test("alimenti: USDA per 100 g", async () => {
  const f = await fromUSDA({
    fdcId: 171688, description: "Apples, raw, with skin", dataType: "SR Legacy",
    foodNutrients: [
      { nutrientId: 1008, unitName: "KCAL", value: 52 }, { nutrientId: 1003, unitName: "G", value: 0.26 },
      { nutrientId: 1005, unitName: "G", value: 13.81 }, { nutrientId: 1004, unitName: "G", value: 0.17 },
    ],
  }, "Mela");
  assert.ok(f);
  assert.equal(f.name, "Mela");
  assert.deepEqual(f.per100g, { kcal: 52, proteinG: 0.3, carbsG: 13.8, fatG: 0.2 });
  assert.equal(f.source, "usda");
  assert.equal(f.id, await stableUUID("usda:171688"));
  assert.match(f.id, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test("alimenti: USDA Foundation con energia di Atwater", async () => {
  const f = await fromUSDA({
    fdcId: 1, description: "Rice", dataType: "Foundation",
    foodNutrients: [{ nutrientId: 2047, unitName: "KCAL", value: 130 }, { nutrientId: 1003, value: 2.7 }, { nutrientId: 1004, value: 0.3 }, { nutrientId: 1005, value: 28 }],
  });
  assert.equal(f?.per100g.kcal, 130);
});

test("alimenti: valori mancanti o assurdi scartati", async () => {
  assert.equal(await fromUSDA({ fdcId: 2, description: "X", foodNutrients: [{ nutrientId: 1003, value: 5 }] }), null);
  assert.equal(await fromUSDA({ fdcId: 3, description: "X", foodNutrients: [
    { nutrientId: 1008, unitName: "KCAL", value: 2000 }, { nutrientId: 1003, value: 5 }, { nutrientId: 1004, value: 5 }] }), null);
});

test("alimenti: Open Food Facts", async () => {
  const f = await fromOFF({
    code: "8076809513753", product_name: "Spaghetti n.5", product_name_it: "Spaghetti n.5", brands: "Barilla, Barilla G. e R.",
    serving_quantity: "100",
    nutriments: { "energy-kcal_100g": 359, proteins_100g: 13, carbohydrates_100g: 71, fat_100g: 2 },
  });
  assert.equal(f?.brand, null);
  assert.equal(f?.name, "Spaghetti n.5");
  assert.equal(f?.source, "open_food_facts");
  assert.equal(f?.defaultServingG, 100);
  const kjOnly = await fromOFF({ code: "1", product_name: "Biscotti", nutriments: { energy_100g: 2000, proteins_100g: 7, carbohydrates_100g: 70, fat_100g: 18 } });
  assert.equal(kjOnly?.per100g.kcal, 478);
  assert.equal(await fromOFF({ code: "2", product_name: "Senza valori", nutriments: {} }), null);
});

test("alimenti: codici a barre e query", () => {
  assert.ok(isBarcode("8076809513753"));
  assert.ok(!isBarcode("80768"));
  assert.ok(!isBarcode("abc12345678"));
  assert.equal(normalizeQuery("  Pasta   AL Pomodoro "), "pasta al pomodoro");
  assert.equal(normalizeQuery("1"), null);
  assert.equal(normalizeQuery("123"), null);
});

test("alimenti: nomi senza marchi né insegne", () => {
  assert.equal(cleanProductName("Spaghetti n.5 Barilla", "Barilla"), "Spaghetti n.5");
  assert.equal(cleanProductName("Esselunga mozzarella", undefined), "Mozzarella");
  assert.equal(cleanProductName("Yogurt greco 0% - Coop", "Coop"), "Yogurt greco 0%");
  assert.equal(cleanProductName("Coppa di testa", undefined), "Coppa di testa");
  assert.equal(cleanProductName("Barilla", "Barilla"), "");
});

test("alimenti: stima AI solo se coerente", async () => {
  const pasta = await aiEstimateFood("Fusilli", { kcal: 158, proteinG: 5.8, carbsG: 30.9, fatG: 0.9 });
  assert.equal(pasta?.source, "ai_estimate");
  assert.equal(pasta?.per100g.kcal, 158);
  // Calorie incoerenti con le macro: ricalcolate (4·10 + 4·20 + 9·5 = 165).
  const fixed = await aiEstimateFood("Sugo", { kcal: 900, proteinG: 10, carbsG: 20, fatG: 5 });
  assert.equal(fixed?.per100g.kcal, 165);
  assert.equal(await aiEstimateFood("X", { kcal: NaN, proteinG: NaN, carbsG: 1, fatG: 1 }), null);
  assert.equal(await aiEstimateFood("X", { kcal: 100, proteinG: 80, carbsG: 80, fatG: 0 }), null);
});

test("alimenti: solo nomi in alfabeto latino", () => {
  assert.ok(isLatinName("Pâte à tartiner 100% cacao"));
  assert.ok(isLatinName("Fusilli n.34"));
  assert.ok(!isLatinName("פסטה פוזילי"));
  assert.ok(!isLatinName("Паста"));
});
