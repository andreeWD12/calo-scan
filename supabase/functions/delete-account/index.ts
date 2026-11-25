/**
 * Cancella definitivamente l'account e tutti i dati (art. 17 GDPR, App Store 5.1.1(v)).
 * Tutte le tabelle hanno ON DELETE CASCADE su auth.users (verificato da supabase/tests/security_test.sql).
 * Le foto dei pasti non sono mai salvate sul server: l'app le cancella dal telefono all'uscita.
 * Con Sign in with Apple: { appleAuthorizationCode } per revocare l'accesso dell'app all'Apple ID.
 * L'abbonamento Apple va disdetto dall'utente in App Store (l'app lo spiega prima di eliminare).
 */
import { errorResponse } from "../_shared/errors.ts";
import { cleanAuthorizationCode, revokeAppleAccess } from "../_shared/siwa.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;
  const body = await readJSON(req, 4096) as { appleAuthorizationCode?: unknown } | null;

  const code = cleanAuthorizationCode(body?.appleAuthorizationCode);
  if (code) {
    // Prima di cancellare: se la revoca non riesce, l'eliminazione procede comunque (diritto alla cancellazione).
    console.log("delete-account: revoca Sign in with Apple:", await revokeAppleAccess(code));
  }

  const { error } = await admin.auth.admin.deleteUser(auth.userId);
  if (error) {
    console.error("delete-account: cancellazione non riuscita");
    return errorResponse("internal");
  }
  // Nessun dato personale nei log: solo l'esito.
  console.log("delete-account: account cancellato");
  return json({ deleted: true });
});
