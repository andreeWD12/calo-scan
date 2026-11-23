/**
 * Cancella definitivamente l'account e tutti i dati (art. 17 GDPR, App Store 5.1.1(v)).
 * Tutte le tabelle hanno ON DELETE CASCADE su auth.users; dalla Fase 5 qui si cancellano anche
 * le foto dei pasti nello storage. L'abbonamento Apple va disdetto dall'utente in App Store.
 */
import { errorResponse } from "../_shared/errors.ts";
import { adminClient, json, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;

  const { error } = await admin.auth.admin.deleteUser(auth.userId);
  if (error) {
    console.error("delete-account: cancellazione non riuscita");
    return errorResponse("internal");
  }
  // Nessun dato personale nei log: solo l'esito.
  console.log("delete-account: account cancellato");
  return json({ deleted: true });
});
