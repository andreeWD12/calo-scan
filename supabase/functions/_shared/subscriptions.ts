/** Salvataggio degli abbonamenti letti da Apple, condiviso da verify-purchase e app-store-notifications. */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import type { SubscriptionRecord } from "./appstore.ts";

export async function saveSubscription(admin: SupabaseClient, s: SubscriptionRecord, userId: string): Promise<void> {
  const { error } = await admin.from("subscriptions").upsert({
    original_transaction_id: s.originalTransactionId,
    user_id: userId,
    product_id: s.productId,
    plan: s.plan,
    status: s.status,
    expires_at: s.expiresAt,
    will_renew: s.willRenew,
    environment: ["Production", "Sandbox", "Xcode", "LocalTesting"].includes(s.environment) ? s.environment : "Production",
    updated_at: new Date().toISOString(),
  }, { onConflict: "original_transaction_id" });
  if (error) throw new Error(`subscriptions: ${error.code}`);
  if (s.offerCodeUsed) {
    // Il premio degli inviti è un codice offerta: se l'utente ne aveva uno, ora risulta riscattato.
    await admin.from("referral_rewards").update({ redeemed_at: new Date().toISOString() })
      .eq("referrer_id", userId).is("redeemed_at", null);
  }
}

export async function linkedUser(admin: SupabaseClient, originalTransactionId: string): Promise<string | null> {
  const { data, error } = await admin.from("subscriptions").select("user_id")
    .eq("original_transaction_id", originalTransactionId).maybeSingle();
  if (error) throw new Error(`subscriptions: ${error.code}`);
  return (data?.user_id as string | undefined) ?? null;
}
