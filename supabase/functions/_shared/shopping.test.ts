// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/shopping.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { containsAllergen, filterSuggestions } from "./shopping.ts";

test("allergeni riconosciuti nel nome", () => {
  assert.equal(containsAllergen("Pasta integrale", ["gluten"]), true);
  assert.equal(containsAllergen("Mandorle tostate", ["tree_nuts"]), true);
  assert.equal(containsAllergen("Zucchine", ["gluten", "milk"]), false);
});

test("latte senza lattosio ammesso per intolleranza, non per allergia", () => {
  assert.equal(containsAllergen("Latte senza lattosio", ["lactose"]), false);
  assert.equal(containsAllergen("Latte senza lattosio", ["milk"]), true);
});

test("filtro dei suggerimenti", () => {
  const out = filterSuggestions(
    [{ name: "Salmone" }, { name: "Lenticchie" }, { name: "" }, { name: "Yogurt greco" }],
    ["fish"],
  );
  assert.deepEqual(out.map((s) => s.name), ["Lenticchie", "Yogurt greco"]);
});
