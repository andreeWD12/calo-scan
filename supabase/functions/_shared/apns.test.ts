import { test } from "node:test";
import assert from "node:assert/strict";
import { isDeadToken, payloadFor } from "./apns.ts";

test("apns: testo del premio senza dati personali e con la destinazione in app", () => {
  const p = payloadFor("referral_reward");
  assert.equal(p.route, "referral");
  assert.ok(p.aps.alert.title.length > 0 && p.aps.alert.body.length < 178);
  assert.doesNotMatch(JSON.stringify(p), /\d+\s?(kcal|kg)/);
});

test("apns: token da eliminare solo quando Apple lo dice", () => {
  assert.equal(isDeadToken(410, "Unregistered"), true);
  assert.equal(isDeadToken(400, "BadDeviceToken"), true);
  assert.equal(isDeadToken(400, "PayloadTooLarge"), false);
  assert.equal(isDeadToken(429, "TooManyRequests"), false);
  assert.equal(isDeadToken(500, undefined), false);
});
