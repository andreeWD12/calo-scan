import { test } from "node:test";
import assert from "node:assert/strict";
import { testerPlan } from "./plan.ts";

test("piano: account di prova da TESTER_USER_IDS", () => {
  const id = "5D3C1F0A-1111-4222-8333-944455556666";
  assert.equal(testerPlan(id, undefined), null);
  assert.equal(testerPlan(id, ""), null);
  assert.equal(testerPlan(id, `abc, ${id.toLowerCase()} `), "pro");
  assert.equal(testerPlan("altro", id), null);
});
