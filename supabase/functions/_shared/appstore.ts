/**
 * Abbonamenti App Store. Lo stato di un abbonamento si legge SEMPRE dall'App Store Server API
 * (connessione TLS con Apple, autenticata con la chiave In-App Purchase): non ci si fida mai di quanto
 * dichiara l'app né del contenuto delle notifiche, che servono solo a sapere QUALE abbonamento riguardare.
 *
 * Logica pura (prodotti, lettura delle risposte) testata in appstore.test.ts; le chiamate di rete sono in fondo.
 */
import type { Plan } from "./scan.ts";

export const PRODUCTS: Record<string, Plan> = {
  "caloscan.plus.monthly": "plus",
  "caloscan.plus.yearly": "plus",
  "caloscan.pro.monthly": "pro",
  "caloscan.pro.yearly": "pro",
  "caloscan.pro.monthly.pregnancy": "pro",
};

/** Stati dell'App Store Server API: 1 attivo, 2 scaduto, 3 tentativi di addebito, 4 periodo di tolleranza, 5 revocato. */
export type AppleStatus = 1 | 2 | 3 | 4 | 5;

export interface SubscriptionRecord {
  originalTransactionId: string;
  productId: string;
  plan: Plan;
  status: AppleStatus;
  expiresAt: string | null;   // ISO
  willRenew: boolean;
  appAccountToken: string | null;
  environment: string;
}

/** Contenuto (non verificato) di un JWS: si usa solo su dati appena ricevuti da Apple via TLS. */
export function decodeJWSPayload(jws: unknown): Record<string, unknown> | null {
  if (typeof jws !== "string") return null;
  const part = jws.split(".")[1];
  if (!part) return null;
  try {
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "=");
    const json = new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
    const obj = JSON.parse(json);
    return typeof obj === "object" && obj !== null ? obj as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

/**
 * Risposta di "Get All Subscription Statuses" → abbonamenti di CaloScan, uno per originalTransactionId.
 * Scarta prodotti sconosciuti e transazioni di altre app (bundleId diverso).
 */
export function parseStatuses(body: unknown, bundleId: string): SubscriptionRecord[] {
  const b = (body ?? {}) as { data?: unknown; environment?: unknown };
  const out: SubscriptionRecord[] = [];
  for (const group of Array.isArray(b.data) ? b.data : []) {
    for (const last of Array.isArray((group as { lastTransactions?: unknown }).lastTransactions)
      ? (group as { lastTransactions: unknown[] }).lastTransactions : []) {
      const l = last as { status?: unknown; signedTransactionInfo?: unknown; signedRenewalInfo?: unknown };
      const tx = decodeJWSPayload(l.signedTransactionInfo);
      if (!tx || tx.bundleId !== bundleId) continue;
      const productId = String(tx.productId ?? "");
      const plan = PRODUCTS[productId];
      if (!plan) continue;
      const renewal = decodeJWSPayload(l.signedRenewalInfo);
      const status = [1, 2, 3, 4, 5].includes(l.status as number) ? l.status as AppleStatus : 2;
      out.push({
        originalTransactionId: String(tx.originalTransactionId ?? ""),
        productId,
        plan,
        status: tx.revocationDate ? 5 : status,
        expiresAt: typeof tx.expiresDate === "number" ? new Date(tx.expiresDate).toISOString() : null,
        willRenew: renewal?.autoRenewStatus === 1,
        appAccountToken: typeof tx.appAccountToken === "string" ? tx.appAccountToken.toLowerCase() : null,
        environment: String(tx.environment ?? b.environment ?? "Production"),
      });
    }
  }
  return out.filter((s) => s.originalTransactionId);
}

/** Abbonamento che dà accesso: attivo o in tolleranza e non scaduto. Il blocco degli addebiti (3) non dà accesso. */
export function grantsAccess(s: { status: number; expiresAt: string | null }, now = new Date()): boolean {
  if (s.status !== 1 && s.status !== 4) return false;
  return s.expiresAt === null || Date.parse(s.expiresAt) > now.getTime() - 60_000;
}

/** Piano più alto tra gli abbonamenti che danno accesso. */
export function bestPlan(subs: { plan: Plan; status: number; expiresAt: string | null }[], now = new Date()): Plan {
  const active = subs.filter((s) => grantsAccess(s, now));
  if (active.some((s) => s.plan === "pro")) return "pro";
  if (active.some((s) => s.plan === "plus")) return "plus";
  return "free";
}

export type OwnershipDecision = "ok" | "other_account";

/**
 * Un abbonamento appartiene a un solo account CaloScan. L'app imposta `appAccountToken` = ID utente a ogni acquisto;
 * se manca (es. codice offerta riscattato fuori dall'app) vale il primo account che lo collega.
 */
export function ownership(s: SubscriptionRecord, userId: string, linkedUserId: string | null): OwnershipDecision {
  if (s.appAccountToken && s.appAccountToken !== userId.toLowerCase()) return "other_account";
  if (linkedUserId && linkedUserId !== userId) return "other_account";
  return "ok";
}

/** ID transazione inviato dall'app: solo cifre, come quelli di StoreKit. */
export function cleanTransactionId(v: unknown): string | null {
  const s = typeof v === "number" ? String(v) : typeof v === "string" ? v.trim() : "";
  return /^\d{1,30}$/.test(s) ? s : null;
}

// ---------------------------------------------------------------------------
// Rete (App Store Server API)

export class AppStoreUnavailableError extends Error {}

function pemToBytes(pem: string): Uint8Array<ArrayBuffer> {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJSON = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));

/** JWT ES256 per l'App Store Server API (valido 20 minuti). */
async function apiToken(): Promise<string> {
  const env = (k: string) => Deno.env.get(k)?.trim().replace(/^["']|["']$/g, "") || undefined;
  const issuer = env("APPLE_ISSUER_ID"), keyId = env("APPLE_KEY_ID"), pem = env("APPLE_PRIVATE_KEY");
  if (!issuer || !keyId || !pem) throw new AppStoreUnavailableError("chiave App Store Server API non impostata");
  const key = await crypto.subtle.importKey("pkcs8", pemToBytes(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64urlJSON({ alg: "ES256", kid: keyId, typ: "JWT" })}.${b64urlJSON({
    iss: issuer, iat: now, exp: now + 1200, aud: "appstoreconnect-v1", bid: bundleId(),
  })}`;
  // WebCrypto restituisce la firma già nel formato r||s richiesto da JWS.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  return `${unsigned}.${b64url(sig)}`;
}

export function bundleId(): string {
  return Deno.env.get("APPLE_BUNDLE_ID")?.trim().replace(/^["']|["']$/g, "") || "com.andrewnalini.caloscan.app";
}

const HOSTS = ["https://api.storekit.itunes.apple.com", "https://api.storekit-sandbox.itunes.apple.com"];

/** Stato degli abbonamenti a cui appartiene `transactionId` (produzione, poi sandbox per TestFlight e Xcode). */
export async function fetchSubscriptions(transactionId: string): Promise<SubscriptionRecord[]> {
  const token = await apiToken();
  for (const host of HOSTS) {
    const res = await fetch(`${host}/inApps/v1/subscriptions/${transactionId}`, {
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(10_000),
    }).catch(() => null);
    if (!res) throw new AppStoreUnavailableError("App Store non raggiungibile");
    if (res.status === 404) continue; // transazione dell'altro ambiente
    // Finché l'app non è pubblicata, la produzione può rispondere 401 anche con una chiave valida: si prova la sandbox.
    if (res.status === 401 && host !== HOSTS[HOSTS.length - 1]) {
      console.warn("appstore: 401 dalla produzione, provo la sandbox");
      continue;
    }
    if (!res.ok) {
      console.error("appstore: risposta", res.status, host.includes("sandbox") ? "(sandbox)" : "(produzione)");
      throw new AppStoreUnavailableError(`App Store ${res.status}`);
    }
    return parseStatuses(await res.json(), bundleId());
  }
  return [];
}
