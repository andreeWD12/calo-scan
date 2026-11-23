import { test } from "node:test";
import assert from "node:assert/strict";
import { checkScanQuota, decodeJPEG, MAX_ITEMS, safeTimeZone, sanitizeAIResult, startOfDay } from "./scan.ts";

test("scansioni: limiti per piano", () => {
  assert.deepEqual(checkScanQuota("free", 2, 2), { ok: true });
  assert.deepEqual(checkScanQuota("free", 3, 3), { ok: false, reason: "daily" });
  assert.deepEqual(checkScanQuota("plus", 19, 5), { ok: true });
  assert.deepEqual(checkScanQuota("plus", 20, 0), { ok: false, reason: "daily" });
  assert.deepEqual(checkScanQuota("pro", 500, 19), { ok: true });
  assert.deepEqual(checkScanQuota("pro", 500, 20), { ok: false, reason: "burst" });
});

test("scansioni: inizio del giorno nel fuso dell'utente", () => {
  const now = new Date("2026-11-23T23:30:00Z"); // 00:30 del 24 a Roma
  assert.equal(startOfDay(now, "Europe/Rome").toISOString(), "2026-11-23T23:00:00.000Z");
  assert.equal(startOfDay(now, "UTC").toISOString(), "2026-11-23T00:00:00.000Z");
  const summer = new Date("2026-07-01T10:15:00Z");
  assert.equal(startOfDay(summer, "Europe/Rome").toISOString(), "2026-06-30T22:00:00.000Z");
  assert.equal(safeTimeZone("Europe/Lisbon"), "Europe/Lisbon");
  assert.equal(safeTimeZone("Marte/Base"), "Europe/Rome");
  assert.equal(safeTimeZone(42), "Europe/Rome");
});

test("scansioni: solo JPEG", () => {
  const jpeg = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, 1, 2, 3));
  assert.ok(decodeJPEG(jpeg));
  assert.equal(decodeJPEG(btoa("GIF89a....")), null);
  assert.equal(decodeJPEG("%%%non-base64"), null);
  assert.equal(decodeJPEG(""), null);
});

test("scansioni: risposta del modello ripulita e limitata", () => {
  const r = sanitizeAIResult({
    items: [
      { name: "Pasta al pomodoro", searchQuery: "pasta cooked", grams: 182.4, confidence: 0.8, ingredients: ["pasta", "pomodoro"] },
      { name: "Olio", searchQuery: "olive oil", grams: 99999, confidence: 4, ingredients: [] },
      { name: "", searchQuery: "x", grams: 10, confidence: 0.5, ingredients: [] },
      { name: "Pane", grams: "tanto", confidence: 0.5 },
    ],
    questions: ["Q1", "Q2", "Q3", "Q4"],
    overallConfidence: 0.7,
  });
  assert.equal(r.items.length, 2);
  assert.deepEqual(r.items[0], { name: "Pasta al pomodoro", searchQuery: "pasta cooked", grams: 182, confidence: 0.8, ingredients: ["pasta", "pomodoro"] });
  assert.equal(r.items[1].grams, 3000);
  assert.equal(r.items[1].confidence, 1);
  assert.equal(r.questions.length, 3);
  assert.equal(sanitizeAIResult(null).items.length, 0);
  const many = sanitizeAIResult({ items: Array.from({ length: 40 }, (_, i) => ({ name: `a${i}`, searchQuery: "a", grams: 10, confidence: 1, ingredients: [] })) });
  assert.equal(many.items.length, MAX_ITEMS);
});
