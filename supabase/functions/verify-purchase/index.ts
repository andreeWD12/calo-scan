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

  let otherAccount = false, found = 0;
  try {
    for (const id of ids) {
      const subs = await fetchSubscriptions(id);
      found += subs.length;
      for (const s of subs) {
        if (ownership(s, auth.userId, await linkedUser(admin, s.originalTransactionId)) !== "ok") {
          otherAccount = true;
          continue;
        }
        await saveSubscription(admin, s, auth.userId);
      }
    }
    const info = await planInfo(admin, auth.userId);
    console.log(`verify-purchase: ${ids.length} transazioni, ${found} abbonamenti trovati da Apple, piano ${info.plan}`);
    if (found === 0 && info.plan === "free") {
      // Apple non conosce la transazione: acquisto fatto con lo schema "StoreKit locale" di Xcode, bundle ID diverso
      // o prodotto non mappato in PRODUCTS. Meglio un messaggio chiaro che un acquisto "riuscito" che non sblocca nulla.
      return errorResponse("invalid_input", { message: "Apple non ha trovato questo acquisto. Se stai provando da Xcode, usa lo schema \"CaloScan\" (non \"StoreKit locale\") e un account Sandbox." });
    }
    if (otherAccount && info.plan === "free") {
      return errorResponse("invalid_input", { message: "Questo abbonamento è già collegato a un altro account CaloScan. Accedi con quell'account per usarlo." });
    }
    return json(info);
  } catch (e) {
    if (e instanceof AppStoreUnavailableError) {
      console.error("verify-purchase:", e.message);
      return errorResponse("internal", { message: `Non riusciamo a verificare l'acquisto con Apple in questo momento. Riprova tra poco: l'abbonamento non è perso. (${e.message})` });
    }
    console.error("verify-purchase:", (e as Error).message);
    return errorResponse("internal");
  }
});
