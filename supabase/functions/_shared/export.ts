/**
 * Esportazione dei dati personali (art. 15 e 20 GDPR): tutte le righe dell'utente in un JSON leggibile.
 * Logica pura (elenco delle tabelle, struttura del file) testata in export.test.ts.
 */

/** Tabelle con dati dell'utente (colonna `user_id`), con una descrizione in italiano per chi apre il file. */
export const EXPORT_TABLES: { table: string; title: string; order?: string }[] = [
  { table: "profiles", title: "Profilo, obiettivi e preferenze" },
  { table: "consents", title: "Consensi attuali" },
  { table: "consent_events", title: "Storico dei consensi", order: "at" },
  { table: "meals", title: "Diario dei pasti", order: "logged_at" },
  { table: "weight_entries", title: "Pesate", order: "date" },
  { table: "body_measurements", title: "Misure corporee", order: "date" },
  { table: "professional_plans", title: "Piano del medico o dietista" },
  { table: "shopping_items", title: "Lista della spesa", order: "added_at" },
  { table: "coach_messages", title: "Conversazione con il coach AI", order: "created_at" },
  { table: "scan_events", title: "Scansioni AI (solo data e esito, nessuna foto)", order: "created_at" },
  { table: "ai_events", title: "Altri utilizzi dell'AI (solo conteggio)", order: "created_at" },
  { table: "subscriptions", title: "Abbonamenti App Store" },
  { table: "push_tokens", title: "Dispositivi registrati per le notifiche" },
  { table: "referral_codes", title: "Il tuo codice invito" },
  { table: "referrals", title: "Invito usato all'iscrizione", order: "created_at" },
  { table: "referral_rewards", title: "Premio per gli inviti" },
];

/** Colonne interne che non dicono nulla all'utente (il token push è un dato tecnico ma resta: è suo). */
const HIDDEN = new Set(["user_id"]);

export interface ExportAccount { id: string; email: string | null; createdAt: string | null; providers: string[] }

export function buildExport(account: ExportAccount, data: Record<string, unknown[]>, now = new Date()) {
  const sections: Record<string, { descrizione: string; righe: unknown[] }> = {};
  for (const { table, title } of EXPORT_TABLES) {
    const rows = (data[table] ?? []).map((r) =>
      typeof r === "object" && r !== null
        ? Object.fromEntries(Object.entries(r as Record<string, unknown>).filter(([k]) => !HIDDEN.has(k)))
        : r
    );
    sections[table] = { descrizione: title, righe: rows };
  }
  return {
    app: "CaloScan",
    esportatoIl: now.toISOString(),
    nota: "Tutti i dati personali che CaloScan conserva sul server per il tuo account. Le foto dei pasti non vengono " +
      "conservate sul server: restano solo sul tuo iPhone. Formato JSON, leggibile da qualsiasi editor di testo.",
    account: { id: account.id, email: account.email, creatoIl: account.createdAt, accesso: account.providers },
    dati: sections,
  };
}

export function exportFileName(now = new Date()): string {
  return `CaloScan-dati-${now.toISOString().slice(0, 10)}.json`;
}
