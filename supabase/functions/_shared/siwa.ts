/**
 * Revoca dell'accesso con Apple all'eliminazione dell'account (requisito App Store 5.1.1(v)):
 * il codice di autorizzazione appena ottenuto dall'app si scambia con un token e lo si revoca.
 * client_secret = JWT ES256 firmato con la chiave dei servizi Apple (con "Sign in with Apple" attivo).
 */
import { secret, signES256 } from "./applejwt.ts";
import { bundleId } from "./appstore.ts";

export function cleanAuthorizationCode(v: unknown): string | null {
  return typeof v === "string" && /^[A-Za-z0-9._-]{10,1000}$/.test(v) ? v : null;
}

/** Esito per il log: mai blocca l'eliminazione. */
export async function revokeAppleAccess(code: string): Promise<"revoked" | "not_configured" | "failed"> {
  const team = secret("APPLE_TEAM_ID"), keyId = secret("APPLE_SERVICES_KEY_ID"), pem = secret("APPLE_SERVICES_PRIVATE_KEY");
  if (!team || !keyId || !pem) return "not_configured";
  const now = Math.floor(Date.now() / 1000);
  const clientSecret = await signES256(keyId,
    { iss: team, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: bundleId() }, pem);
  const form = (o: Record<string, string>) => new URLSearchParams(o).toString();
  const headers = { "content-type": "application/x-www-form-urlencoded" };

  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST", headers, signal: AbortSignal.timeout(10_000),
    body: form({ client_id: bundleId(), client_secret: clientSecret, code, grant_type: "authorization_code" }),
  }).catch(() => null);
  if (!tokenRes?.ok) {
    console.warn("siwa: scambio del codice non riuscito", tokenRes?.status ?? "rete");
    return "failed";
  }
  const tokens = await tokenRes.json() as { refresh_token?: string; access_token?: string };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) return "failed";
  const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST", headers, signal: AbortSignal.timeout(10_000),
    body: form({
      client_id: bundleId(), client_secret: clientSecret, token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }),
  }).catch(() => null);
  if (!revokeRes?.ok) {
    console.warn("siwa: revoca non riuscita", revokeRes?.status ?? "rete");
    return "failed";
  }
  return "revoked";
}
