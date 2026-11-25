/**
 * Client Supabase lato server. SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sono forniti
 * automaticamente alle Edge Functions: la chiave service_role non lascia mai il server.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { errorResponse } from "./errors.ts";

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Utente autenticato dal JWT della richiesta, oppure la risposta 401 da restituire. */
export async function requireUser(req: Request, admin: SupabaseClient): Promise<{ userId: string } | Response> {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return errorResponse("unauthorized");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return errorResponse("unauthorized");
  return { userId: data.user.id };
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** Legge il corpo JSON con un limite di dimensione, per non accettare payload enormi. */
export async function readJSON(req: Request, maxBytes = 32_768): Promise<unknown | null> {
  const text = await req.text();
  if (text.length > maxBytes) return null;
  try { return JSON.parse(text); } catch { return null; }
}
