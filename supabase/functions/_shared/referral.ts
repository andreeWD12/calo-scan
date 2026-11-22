// Regole del programma "Invita un amico". Pure funzioni, usate dalla Edge Function `referral`
// e dal job che assegna i premi. La normalizzazione è identica a `ReferralCode` in Swift.
//
// Premio: UN solo sconto sul primo mese per chi invita (non accumulabile), consegnato come
// codice offerta Apple monouso preso da un lotto importato da App Store Connect. L'app non
// sblocca mai nulla da sola (linea guida App Store 3.1.1).

export const REFERRAL = {
  alphabet: "ABCDEFGHJKMNPQRSTUVWXYZ23456789",
  length: 8,
  /** Giorni dalla creazione dell'account entro cui l'amico può inserire un codice. */
  applyWindowDays: 14,
  /** Giorni di validità del codice offerta assegnato. */
  rewardValidityDays: 60,
  /** Massimo di inviti conteggiati per utente (limite anti-abuso; il premio resta uno solo). */
  maxCountedInvites: 50,
} as const;

export function normalizeReferralCode(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const cleaned = input.toUpperCase().replace(/[\s-]/g, "");
  if (cleaned.length !== REFERRAL.length) return null;
  return [...cleaned].every((c) => REFERRAL.alphabet.includes(c)) ? cleaned : null;
}

/** Codice casuale con un generatore crittografico; l'unicità la garantisce il vincolo UNIQUE del DB. */
export function generateReferralCode(random: (n: number) => Uint8Array = (n) => crypto.getRandomValues(new Uint8Array(n))): string {
  const a = REFERRAL.alphabet;
  const max = Math.floor(256 / a.length) * a.length; // rifiuta i byte che introdurrebbero bias
  let out = "";
  while (out.length < REFERRAL.length) {
    for (const b of random(16)) {
      if (b < max && out.length < REFERRAL.length) out += a[b % a.length];
    }
  }
  return out;
}

export type ApplyReferralResult = "applied" | "invalid_code" | "own_code" | "already_referred" | "too_late";

export interface ApplyInput {
  rawCode: unknown;
  /** Proprietario del codice, se esiste. */
  codeOwnerId: string | null;
  userId: string;
  userCreatedAt: string; // ISO
  now: string; // ISO
  alreadyReferred: boolean;
}

export function evaluateApply(i: ApplyInput): ApplyReferralResult {
  if (!normalizeReferralCode(i.rawCode) || !i.codeOwnerId) return "invalid_code";
  if (i.codeOwnerId === i.userId) return "own_code";
  if (i.alreadyReferred) return "already_referred";
  const ageDays = (Date.parse(i.now) - Date.parse(i.userCreatedAt)) / 86_400_000;
  if (!(ageDays >= 0) || ageDays > REFERRAL.applyWindowDays) return "too_late";
  return "applied";
}

export interface QualifyInput {
  onboardingCompleted: boolean;
  mealsLogged: number;
  /** DeviceCheck: il dispositivo dell'amico ha già prodotto un invito valido. */
  deviceAlreadyUsed: boolean;
}

/** Un invito conta solo quando l'amico usa davvero l'app, non al solo download. */
export function isQualified(q: QualifyInput): boolean {
  return q.onboardingCompleted && q.mealsLogged >= 1 && !q.deviceAlreadyUsed;
}

export type RewardDecision = "grant" | "already_rewarded" | "not_eligible" | "no_qualified_invites";

export interface RewardInput {
  qualifiedInvites: number;
  /** Il referrer ha già ricevuto un codice (anche scaduto o riscattato): non accumulabile. */
  hasReward: boolean;
  /** Il referrer è o è stato abbonato: lo sconto è sul primo mese. */
  everSubscribed: boolean;
}

export function decideReward(r: RewardInput): RewardDecision {
  if (r.hasReward) return "already_rewarded";
  if (r.everSubscribed) return "not_eligible";
  if (r.qualifiedInvites < 1) return "no_qualified_invites";
  return "grant";
}
