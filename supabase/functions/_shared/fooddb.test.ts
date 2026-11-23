import { test } from "node:test";
import assert from "node:assert/strict";
import { matchQueries } from "./fooddb.ts";

test("abbinamento: dal termine preciso a quello generico", () => {
  assert.deepEqual(matchQueries("fusilli pasta cooked"), ["fusilli pasta cooked", "pasta cooked"]);
  assert.deepEqual(matchQueries("pasta cooked"), ["pasta cooked"]);
  assert.deepEqual(matchQueries("olive oil"), ["olive oil"]);
});
