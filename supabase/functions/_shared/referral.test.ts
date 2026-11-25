// Esecuzione: node --experimental-strip-types --test supabase/functions/_shared/referral.test.ts
// Normalizzazione: stessi casi di ReferralTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import { decideReward, evaluateApply, generateReferralCode, isQualified, normalizeReferralCode, REFERRAL } from "./referral.ts";

test("codice invito: normalizzazione", () => {
  assert.equal(normalizeReferralCode(" abcd-2345 "), "ABCD2345");
  assert.equal(normalizeReferralCode("ABCD 2345"), "ABCD2345");
  assert.equal(normalizeReferralCode("ABCD-0345"), null);
  assert.equal(normalizeReferralCode("ABCD-I345"), null);
  assert.equal(normalizeReferralCode("ABC2345"), null);
  assert.equal(normalizeReferralCode(""), null);
  assert.equal(normalizeReferralCode(42), null);
});

test("codice invito: generazione nell'alfabeto", () => {
  for (let i = 0; i < 200; i++) {
    const c = generateReferralCode();
    assert.equal(normalizeReferralCode(c), c);
  }
  // byte oltre la soglia scartati: 255 non è mai usato
  let calls = 0;
  const code = generateReferralCode(() => (calls++ === 0 ? new Uint8Array(16).fill(255) : new Uint8Array(16).fill(0)));
  assert.equal(code, "AAAAAAAA");
});

test("codice invito: inserimento dell'amico", () => {
  const base = {
    rawCode: "ABCD-2345", codeOwnerId: "A", userId: "B",
    userCreatedAt: "2026-11-20T10:00:00Z", now: "2026-11-22T10:00:00Z", alreadyReferred: false,
  };
  assert.equal(evaluateApply(base), "applied");
  assert.equal(evaluateApply({ ...base, rawCode: "nope" }), "invalid_code");
  assert.equal(evaluateApply({ ...base, codeOwnerId: null }), "invalid_code");
  assert.equal(evaluateApply({ ...base, codeOwnerId: "B" }), "own_code");
  assert.equal(evaluateApply({ ...base, alreadyReferred: true }), "already_referred");
  assert.equal(evaluateApply({ ...base, userCreatedAt: "2026-11-01T10:00:00Z" }), "too_late");
  assert.equal(REFERRAL.applyWindowDays, 14);
});

test("invito valido solo se l'amico usa l'app", () => {
  assert.equal(isQualified({ onboardingCompleted: true, mealsLogged: 1, deviceAlreadyUsed: false }), true);
  assert.equal(isQualified({ onboardingCompleted: true, mealsLogged: 0, deviceAlreadyUsed: false }), false);
  assert.equal(isQualified({ onboardingCompleted: false, mealsLogged: 3, deviceAlreadyUsed: false }), false);
  assert.equal(isQualified({ onboardingCompleted: true, mealsLogged: 3, deviceAlreadyUsed: true }), false);
});

test("premio: uno solo, non accumulabile, solo sul primo mese", () => {
  assert.equal(decideReward({ qualifiedInvites: 1, hasReward: false, everSubscribed: false }), "grant");
  assert.equal(decideReward({ qualifiedInvites: 5, hasReward: true, everSubscribed: false }), "already_rewarded");
  assert.equal(decideReward({ qualifiedInvites: 1, hasReward: false, everSubscribed: true }), "not_eligible");
  assert.equal(decideReward({ qualifiedInvites: 0, hasReward: false, everSubscribed: false }), "no_qualified_invites");
});
