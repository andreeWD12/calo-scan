/**
 * DeviceCheck: 2 bit per iPhone conservati da Apple, per non contare due volte lo stesso dispositivo negli inviti
 * (account multipli). Nessun identificatore del dispositivo viene salvato da CaloScan.
 * bit0 = questo iPhone ha già usato il codice di un amico.
 * Se la chiave non è impostata o Apple non risponde, l'invito non viene bloccato (si registra solo nel log).
 */
import { secret, signES256 } from "./applejwt.ts";

const HOSTS = { production: "https://api.devicecheck.apple.com", sandbox: "https://api.development.devicecheck.apple.com" };

async function token(): Promise<string | null> {
  const team = secret("APPLE_TEAM_ID"), keyId = secret("APPLE_SERVICES_KEY_ID"), pem = secret("APPLE_SERVICES_PRIVATE_KEY");
  if (!team || !keyId || !pem) return null;
  const now = Math.floor(Date.now() / 1000);
  return await signES256(keyId, { iss: team, iat: now }, pem);
}

export function cleanDeviceToken(v: unknown): string | null {
  return typeof v === "string" && /^[A-Za-z0-9+/=]{20,8000}$/.test(v) ? v : null;
}

async function call(environment: keyof typeof HOSTS, path: string, body: Record<string, unknown>): Promise<Response | null> {
  const jwt = await token();
  if (!jwt) {
    console.warn("devicecheck: chiave non impostata, controllo saltato");
    return null;
  }
  return await fetch(`${HOSTS[environment]}/v1/${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
    body: JSON.stringify({ ...body, transaction_id: crypto.randomUUID(), timestamp: Date.now() }),
    signal: AbortSignal.timeout(8000),
  }).catch(() => null);
}

/** true se questo iPhone ha già usato un codice invito; null se non si può sapere. */
export async function deviceAlreadyUsed(deviceToken: string, environment: keyof typeof HOSTS): Promise<boolean | null> {
  const res = await call(environment, "query_two_bits", { device_token: deviceToken });
  if (!res || !res.ok) {
    if (res) console.warn("devicecheck: risposta", res.status);
    return null;
  }
  const text = await res.text();
  // Apple risponde con un testo (non JSON) se per il dispositivo non è mai stato salvato nulla.
  try { return (JSON.parse(text) as { bit0?: boolean }).bit0 === true; } catch { return false; }
}

export async function markDeviceUsed(deviceToken: string, environment: keyof typeof HOSTS): Promise<void> {
  const res = await call(environment, "update_two_bits", { device_token: deviceToken, bit0: true, bit1: false });
  if (res && !res.ok) console.warn("devicecheck: aggiornamento non riuscito", res.status);
}
