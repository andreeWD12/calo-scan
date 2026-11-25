/**
 * Notifiche push con APNs (HTTP/2, autenticazione a token con la chiave .p8 dei servizi Apple: APNs + DeviceCheck).
 * Testi fissi decisi dal server per tipo di notifica: mai dati sanitari, numeri del diario o nomi di altri utenti
 * (la notifica può comparire sulla schermata bloccata). Logica pura testata in apns.test.ts.
 */
import { secret, signES256 } from "./applejwt.ts";

export type PushKind = "referral_reward";

export interface PushPayload {
  aps: { alert: { title: string; body: string }; sound: "default"; "thread-id": string };
  route: string;
}

export function payloadFor(kind: PushKind): PushPayload {
  switch (kind) {
    case "referral_reward":
      return {
        aps: {
          alert: {
            title: "Il tuo premio è pronto",
            body: "Un amico che hai invitato ha iniziato a usare CaloScan. Apri l'app per vedere il tuo sconto.",
          },
          sound: "default",
          "thread-id": "referral",
        },
        route: "referral",
      };
  }
}

/** Token da eliminare: APNs dice che non è (più) valido. 410 = app disinstallata o notifiche revocate. */
export function isDeadToken(status: number, reason: string | undefined): boolean {
  return status === 410 || (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"));
}

export const MAX_ATTEMPTS = 5;

// ---------------------------------------------------------------------------
// Rete

export class PushUnavailableError extends Error {}

let cached: { token: string; at: number } | null = null;

/** Apple chiede di rinnovare il token tra 20 e 60 minuti: lo si riusa per 40. */
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 2400) return cached.token;
  const team = secret("APPLE_TEAM_ID"), keyId = secret("APPLE_SERVICES_KEY_ID"), pem = secret("APPLE_SERVICES_PRIVATE_KEY");
  if (!team || !keyId || !pem) throw new PushUnavailableError("chiave APNs (APPLE_SERVICES_KEY_ID) non impostata");
  cached = { token: await signES256(keyId, { iss: team, iat: now }, pem), at: now };
  return cached.token;
}

export interface SendResult { status: number; reason?: string }

export async function sendPush(deviceToken: string, environment: "sandbox" | "production", payload: PushPayload,
  topic: string): Promise<SendResult> {
  const host = environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  const res = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10_000),
  }).catch(() => null);
  if (!res) return { status: 0, reason: "network" };
  if (res.ok) return { status: res.status };
  const body = await res.json().catch(() => ({})) as { reason?: string };
  return { status: res.status, reason: body.reason };
}
