/** JWT ES256 firmati con una chiave .p8 di Apple (App Store Server API, APNs, DeviceCheck). */

/** Legge un segreto togliendo spazi e virgolette finiti per sbaglio nel comando `supabase secrets set`. */
export function secret(name: string): string | undefined {
  return Deno.env.get(name)?.trim().replace(/^["']|["']$/g, "") || undefined;
}

export function pemToBytes(pem: string): Uint8Array<ArrayBuffer> {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJSON = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));

export async function signES256(keyId: string, payload: Record<string, unknown>, pem: string): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemToBytes(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const unsigned = `${b64urlJSON({ alg: "ES256", kid: keyId, typ: "JWT" })}.${b64urlJSON(payload)}`;
  // WebCrypto restituisce la firma già nel formato r||s richiesto da JWS.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  return `${unsigned}.${b64url(sig)}`;
}
