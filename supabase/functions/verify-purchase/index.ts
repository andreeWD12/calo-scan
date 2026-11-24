/**
 * Verifica di un acquisto: { transactionIds: string[] } → { plan, expiresAt, willRenew }.
 * L'app invia solo gli ID delle transazioni StoreKit; lo stato vero si legge dall'App Store Server API.
 * Un abbonamento resta legato a un solo account CaloScan (appAccountToken = ID utente impostato dall'app).
 * Usata dopo un acquisto, al ripristino, dopo un codice offerta e per ogni aggiornamento di Transaction.updates.
 */
import { errorResponse } from "../_shared/errors.ts";
import { AppStoreUnavailableError, cleanTransactionId, fetchSubscriptions, ownership } from "../_shared/appstore.ts";
import { planInfo } from "../_shared/plan.ts";
import { linkedUser, saveSubscription } from "../_shared/subscriptions.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;
  const body = await readJSON(req, 4096) as { transactionIds?: unknown } | null;
  const ids = [...new Set((Array.isArray(body?.transactionIds) ? body.transactionIds : []).map(cleanTransactionId))]
    .filter((x): x is string => x !== null).slice(0, 10);
  if (ids.length === 0) return errorResponse("invalid_input");

  let otherAccount = false;
  try {
    for (const id of ids) {
      for (const s of await fetchSubscriptions(id)) {
        if (ownership(s, auth.userId, await linkedUser(admin, s.originalTransactionId)) !== "ok") {
          otherAccount = true;
          continue;
        }
        await saveSubscription(admin, s, auth.userId);
      }
    }
    const info = await planInfo(admin, auth.userId);
    if (otherAccount && info.plan === "free") {
      return errorResponse("invalid_input", { message: "Questo abbonamento è già collegato a un altro account CaloScan. Accedi con quell'account per usarlo." });
    }
    return json(info);
  } catch (e) {
    if (e instanceof AppStoreUnavailableError) {
      console.error("verify-purchase:", e.message);
      return errorResponse("internal", { message: "Non riusciamo a verificare l'acquisto con Apple in questo momento. Riprova tra poco: l'abbonamento non è perso." });
    }
    console.error("verify-purchase:", (e as Error).message);
    return errorResponse("internal");
  }
});
