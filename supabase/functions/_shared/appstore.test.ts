// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/appstore.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { bestPlan, cleanTransactionId, decodeJWSPayload, grantsAccess, ownership, parseStatuses } from "./appstore.ts";

const b64url = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jws = (payload: unknown) => `${b64url({ alg: "ES256" })}.${b64url(payload)}.firma`;
const BUNDLE = "com.andrewnalini.caloscan.app";
const USER = "5d3c1f0a-1111-4222-8333-944455556666";

const tx = (over: Record<string, unknown> = {}) => jws({
  bundleId: BUNDLE, productId: "caloscan.pro.yearly", originalTransactionId: "2000000111", transactionId: "2000000222",
  expiresDate: Date.parse("2027-11-24T10:00:00Z"), appAccountToken: USER.toUpperCase(), environment: "Sandbox", ...over,
});
const statuses = (status: number, txInfo = tx(), autoRenew = 1) => ({
  environment: "Sandbox",
  data: [{ subscriptionGroupIdentifier: "1", lastTransactions: [{ status, signedTransactionInfo: txInfo, signedRenewalInfo: jws({ autoRenewStatus: autoRenew }) }] }],
});

test("appstore: decodifica del contenuto JWS", () => {
  assert.deepEqual(decodeJWSPayload(jws({ a: 1 })), { a: 1 });
  assert.equal(decodeJWSPayload("rotto"), null);
  assert.equal(decodeJWSPayload(42), null);
});

test("appstore: lettura degli stati", () => {
  const [s] = parseStatuses(statuses(1), BUNDLE);
  assert.equal(s.plan, "pro");
  assert.equal(s.status, 1);
  assert.equal(s.willRenew, true);
  assert.equal(s.appAccountToken, USER);
  assert.equal(s.expiresAt, "2027-11-24T10:00:00.000Z");
  assert.equal(s.environment, "Sandbox");
  assert.equal(s.offerCodeUsed, false);
  assert.equal(parseStatuses(statuses(1, tx({ offerType: 3, offerIdentifier: "ref30" })), BUNDLE)[0].offerCodeUsed, true);
});

test("appstore: scarta altre app, prodotti sconosciuti e segna i rimborsi", () => {
  assert.equal(parseStatuses(statuses(1, tx({ bundleId: "com.altra.app" })), BUNDLE).length, 0);
  assert.equal(parseStatuses(statuses(1, tx({ productId: "altro" })), BUNDLE).length, 0);
  assert.equal(parseStatuses(statuses(1, tx({ revocationDate: 1 })), BUNDLE)[0].status, 5);
  assert.equal(parseStatuses(statuses(1, tx({ productId: "caloscan.pro.monthly.pregnancy" })), BUNDLE)[0].plan, "pro");
  assert.equal(parseStatuses({}, BUNDLE).length, 0);
});

test("appstore: accesso solo se attivo o in tolleranza e non scaduto", () => {
  const now = new Date("2026-11-24T10:00:00Z");
  const future = "2026-12-24T10:00:00Z", past = "2026-10-24T10:00:00Z";
  assert.equal(grantsAccess({ status: 1, expiresAt: future }, now), true);
  assert.equal(grantsAccess({ status: 4, expiresAt: future }, now), true);
  assert.equal(grantsAccess({ status: 3, expiresAt: future }, now), false);
  assert.equal(grantsAccess({ status: 5, expiresAt: future }, now), false);
  assert.equal(grantsAccess({ status: 1, expiresAt: past }, now), false);
  assert.equal(bestPlan([{ plan: "plus", status: 1, expiresAt: future }, { plan: "pro", status: 2, expiresAt: past }], now), "plus");
  assert.equal(bestPlan([{ plan: "plus", status: 1, expiresAt: future }, { plan: "pro", status: 1, expiresAt: future }], now), "pro");
  assert.equal(bestPlan([], now), "free");
});

test("appstore: un abbonamento appartiene a un solo account", () => {
  const [s] = parseStatuses(statuses(1), BUNDLE);
  assert.equal(ownership(s, USER, null), "ok");
  assert.equal(ownership(s, "altro-utente", null), "other_account");
  const noToken = { ...s, appAccountToken: null };
  assert.equal(ownership(noToken, "altro-utente", null), "ok");
  assert.equal(ownership(noToken, "altro-utente", USER), "other_account");
});

test("appstore: ID transazione", () => {
  assert.equal(cleanTransactionId("2000000222"), "2000000222");
  assert.equal(cleanTransactionId(2000000222), "2000000222");
  assert.equal(cleanTransactionId("12; drop"), null);
  assert.equal(cleanTransactionId(""), null);
});
