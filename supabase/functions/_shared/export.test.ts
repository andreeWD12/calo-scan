import { test } from "node:test";
import assert from "node:assert/strict";
import { buildExport, EXPORT_TABLES, exportFileName } from "./export.ts";

test("export: tutte le tabelle presenti, user_id tolto, descrizioni in italiano", () => {
  const out = buildExport({ id: "u1", email: "a@b.it", createdAt: "2026-01-01T00:00:00Z", providers: ["email"] },
    { meals: [{ id: "m1", user_id: "u1", type: "lunch" }] }, new Date("2026-11-25T10:00:00Z"));
  assert.equal(Object.keys(out.dati).length, EXPORT_TABLES.length);
  assert.deepEqual(out.dati.meals.righe, [{ id: "m1", type: "lunch" }]);
  assert.deepEqual(out.dati.weight_entries.righe, []);
  assert.equal(out.account.email, "a@b.it");
  assert.equal(out.esportatoIl, "2026-11-25T10:00:00.000Z");
});

test("export: nome del file con la data", () => {
  assert.equal(exportFileName(new Date("2026-11-25T10:00:00Z")), "CaloScan-dati-2026-11-25.json");
});
