import { test } from "node:test";
import assert from "node:assert/strict";
import { hasItalianName, matchQueries } from "./fooddb.ts";

test("abbinamento: dal termine preciso a quello generico", () => {
  assert.deepEqual(matchQueries("fusilli pasta cooked"), ["fusilli pasta cooked", "pasta cooked"]);
  assert.deepEqual(matchQueries("pasta cooked"), ["pasta cooked"]);
  assert.deepEqual(matchQueries("olive oil"), ["olive oil"]);
});

test("Open Food Facts: solo prodotti con il nome in italiano", () => {
  assert.ok(hasItalianName({ product_name_it: "Fusilli" }));
  assert.ok(hasItalianName({ product_name: "Fusilli", lang: "it" }));
  assert.ok(!hasItalianName({ product_name: "Fusilli", lang: "fr" }));
  assert.ok(!hasItalianName({ product_name: "פוזילי", lang: "he", product_name_it: " " }));
});
