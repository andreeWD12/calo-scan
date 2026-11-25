/**
 * App Store Server Notifications V2 (rinnovi, scadenze, rimborsi, cambi di piano).
 * Endpoint pubblico chiamato da Apple: il contenuto della notifica NON viene creduto. Serve solo a sapere quale
 * transazione riguarda; lo stato si rilegge dall'App Store Server API e si aggiorna l'abbonamento già collegato.
 * Risponde sempre 200 quando la notifica è stata gestita, così Apple non la ripete.
 */
import { AppStoreUnavailableError, cleanTransactionId, decodeJWSPayload, fetchSubscriptions } from "../_shared/appstore.ts";
import { linkedUser, saveSubscription } from "../_shared/subscriptions.ts";
import { adminClient, readJSON } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  const body = await readJSON(req, 65_536) as { signedPayload?: unknown } | null;
  const payload = decodeJWSPayload(body?.signedPayload);
  if (!payload) return new Response(null, { status: 400 });
  if (payload.notificationType === "TEST") return new Response(null, { status: 200 });

  const data = (payload.data ?? {}) as { signedTransactionInfo?: unknown };
  const tx = decodeJWSPayload(data.signedTransactionInfo);
  const transactionId = cleanTransactionId(tx?.transactionId) ?? cleanTransactionId(tx?.originalTransactionId);
  if (!transactionId) return new Response(null, { status: 200 }); // non riguarda un abbonamento

  const admin = adminClient();
  try {
    for (const s of await fetchSubscriptions(transactionId)) {
      // Si aggiornano solo abbonamenti già collegati a un account (il collegamento lo fa verify-purchase).
      const userId = await linkedUser(admin, s.originalTransactionId);
      if (userId) await saveSubscription(admin, s, userId);
    }
    return new Response(null, { status: 200 });
  } catch (e) {
    // 500: Apple riproverà più tardi.
    console.error("app-store-notifications:", e instanceof AppStoreUnavailableError ? e.message : (e as Error).message);
    return new Response(null, { status: 500 });
  }
});
