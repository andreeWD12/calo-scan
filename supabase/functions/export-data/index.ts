/**
 * Esportazione dei dati (art. 15 e 20 GDPR): tutte le righe dell'utente in un unico JSON leggibile.
 * Risponde { fileName, content } con il JSON già formattato: l'app lo salva in un file e lo condivide.
 * Gratis per tutti i piani. Limite: 10 esportazioni al giorno (protezione dal carico, non un limite del diritto).
 */
import { errorResponse } from "../_shared/errors.ts";
import { buildExport, EXPORT_TABLES, exportFileName } from "../_shared/export.ts";
import { adminClient, json, requireUser } from "../_shared/supabase.ts";

const recent = new Map<string, number[]>();

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;

  const now = Date.now();
  const times = (recent.get(auth.userId) ?? []).filter((t) => now - t < 86_400_000);
  if (times.length >= 10) {
    return errorResponse("invalid_input", { message: "Hai già esportato i dati più volte oggi. Riprova domani." });
  }
  recent.set(auth.userId, [...times, now]);

  try {
    const { data: userData, error: userError } = await admin.auth.admin.getUserById(auth.userId);
    if (userError || !userData.user) return errorResponse("unauthorized");
    const u = userData.user;
    const data: Record<string, unknown[]> = {};
    for (const { table, order } of EXPORT_TABLES) {
      const keyColumn = table === "referral_rewards" ? "referrer_id" : table === "referrals" ? "referred_id" : "user_id";
      let q = admin.from(table).select("*").eq(keyColumn, auth.userId);
      if (order) q = q.order(order, { ascending: true });
      const { data: rows, error } = await q.limit(50_000);
      if (error) throw new Error(`${table}: ${error.code ?? error.message}`);
      data[table] = rows ?? [];
    }
    const providers = (u.identities ?? []).map((i) => i.provider);
    const out = buildExport({ id: u.id, email: u.email ?? null, createdAt: u.created_at ?? null, providers }, data);
    console.log("export-data: esportazione completata");
    return json({ fileName: exportFileName(), content: JSON.stringify(out, null, 2) });
  } catch (e) {
    console.error("export-data:", (e as Error).message);
    return errorResponse("internal");
  }
});
