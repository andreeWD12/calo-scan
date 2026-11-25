# Roadmap

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | Architettura e struttura del progetto | ✅ completata |
| 2 | Design system e schermate principali | ✅ completata |
| 3 | Registrazione, login, onboarding (collegamento a Supabase Auth) | ✅ completata |
| 4 | Database (schema + RLS) e backend | ✅ completata |
| 5 | AI Food Scanner e analisi nutrizionale | ✅ completata |
| 6 | Diario e statistiche | ✅ completata |
| 7 | AI Nutrition Coach | ✅ completata |
| 8 | Abbonamenti Free / Plus / Pro | ✅ completata |
| 9 | Notifiche, privacy, sicurezza | ✅ completata |
| 10 | Test, bug fixing, preparazione App Store | ⏳ prossima |

## Fase 1 – consegnato

- Architettura completa (`docs/ARCHITECTURE.md`).
- Progetto XcodeGen, configurazione xcconfig senza segreti, Info.plist, entitlements, manifest privacy.
- Pacchetto `CaloScanCore`: modelli di dominio e calcolo BMR/TDEE/obiettivi/macro con limiti di sicurezza, con test.
- Mirror TypeScript del calcolo per la validazione server, 7 test eseguiti e superati.
- Client Edge Functions con contratto d'errore condiviso app/server.
- Container dipendenze, protocolli dei servizi, stato `Loadable` per le schermate.

Nota: il codice Swift è stato scritto in un ambiente Linux senza Xcode e non è ancora stato compilato. Va verificato al primo `xcodegen generate` sul Mac.

## Fase 2 – consegnato

- Design system (`DesignSystem/`): palette light/dark con contrasti WCAG AA, tipografia Dynamic Type, spaziature, componenti (pulsanti, card, anelli, barre macro, stati di caricamento/vuoto/errore, campi, selezioni).
- Navigazione a 5 sezioni con Scanner centrale a schermo intero.
- Tutte le 25 schermate (vedi `ios/CaloScan/Features/README.md`), ognuna con ViewModel e stati di caricamento, vuoto ed errore.
- Fotocamera reale (AVFoundation), scelta dalla libreria, ridimensionamento e rimozione dei metadati EXIF/GPS.
- Promemoria locali reali (UserNotifications), tema chiaro/scuro/automatico.
- Requisiti UE e App Store nell'interfaccia: vedi `docs/COMPLIANCE.md`.
- Modalità anteprima solo Debug (`-PreviewMode`, `-PreviewOnboarding`) per provare l'app nel simulatore prima che il backend sia collegato.

## Fase 9 – consegnato

- **Esportazione dei dati** (art. 15 e 20 GDPR): funzione `export-data`, un JSON leggibile con tutte le tabelle dell'utente e una descrizione per sezione (`_shared/export.ts`, con test). Gratis per tutti.
- **Eliminazione dell'account**: con "Accedi con Apple" l'app chiede una conferma ad Apple e il server revoca l'accesso dell'app all'Apple ID (`_shared/siwa.ts`), come richiesto da App Store 5.1.1(v). Tutti i dati spariscono a cascata (verificato dai test del database).
- **Notifiche push**: token APNs salvato con `register_push_token` (un token per un solo account, al massimo 10 dispositivi), coda `push_outbox`, funzione `push-dispatch` pianificata con pg_cron. Testi fissi senza dati sanitari. Prima notifica: "il tuo premio è pronto".
- **Invita un amico** collegato: funzione `referral` (codice personale, inserimento entro 14 giorni, 10 tentativi al giorno), invito valido al primo pasto dell'amico con un trigger del database, premio unico con un codice offerta Apple dal lotto `offer_code_pool`, DeviceCheck contro gli account multipli sullo stesso iPhone, riscatto riconosciuto dalle transazioni con codice offerta.
- **Sicurezza**: test automatici del database in CI (`supabase/tests`): RLS attivo ovunque, nessun permesso per gli utenti non autenticati, tabelle del server non scrivibili dall'app, isolamento tra utenti, regole degli inviti, cancellazione a cascata. Il controllo ha trovato e chiuso permessi di scrittura superflui su 6 tabelle.
- **Pagine web**: informativa privacy (`privacy/`) e termini di servizio (`terms/`), accanto all'assistenza.

## Fase 8 – consegnato

- Migrazione `20261128000001_fase8_abbonamenti.sql`: tabella `subscriptions` (un abbonamento Apple per riga, legato a un solo account), RLS in sola lettura, permessi espliciti.
- Funzione `verify-purchase`: l'app invia solo gli ID delle transazioni; il server rilegge lo stato dall'**App Store Server API** con la chiave In-App Purchase e decide il piano. Un abbonamento con `appAccountToken` di un altro account viene rifiutato.
- Funzione `app-store-notifications` (Server Notifications V2): rinnovi, scadenze, rimborsi e problemi di addebito aggiornano il piano anche ad app chiusa. Il contenuto della notifica serve solo a sapere quale abbonamento rileggere da Apple.
- `get-entitlements` legge il piano dagli abbonamenti (attivo o in periodo di tolleranza), con scadenza e rinnovo automatico.
- App: `StoreKitPurchaseService` (StoreKit 2) con prezzi e offerte reali, acquisto con `appAccountToken`, ripristino, codici offerta, ascolto di `Transaction.updates` e sincronizzazione all'accesso. Logica in `_shared/appstore.ts` con test.

## Fase 7 – consegnato

- Migrazione `20261127000001_fase7_coach.sql`: `coach_messages` (conversazione, l'utente la legge e la cancella) e `ai_events` (solo conteggio degli utilizzi, senza testo), RLS e permessi espliciti.
- Funzione `coach-chat`: risposte dell'AI con profilo, obiettivi effettivi (piano del professionista › gravidanza › calcolati), pasti di oggi e media della settimana. Chat solo Plus (30 messaggi al giorno) e Pro (150); Free riceve `plan_required`. Filtri di sicurezza in `_shared/coach.ts` con test.
- Stesse funzione: proposte di stile alimentare (Pro, 5 al giorno, solo stili ammessi da `allowedStyles`) e lista della spesa AI (Plus e Pro, 5 al giorno, senza allergeni e, in gravidanza, senza alimenti a rischio).
- Consigli del giorno gratuiti per tutti, calcolati sul telefono con regole fisse (`DailyTips`, con test): calorie rimaste, proteine, costanza, media della settimana. In Home e nel Coach.
- Traguardi: feste con coriandoli (obiettivo del giorno, giorni di fila, peso obiettivo) e pop-up di incoraggiamento e sulle abitudini (`Milestones`, `CelebrationCenter`).
- App: chat collegata, scheda con lucchetto per Free, "Cancella conversazione", messaggi rimasti da `get-entitlements`.

## Fase 6 – consegnato

- Migrazione `20261126000001_fase6_misure.sql`: tabella `body_measurements` (vita, fianchi, petto, braccio, coscia; almeno una misura, valori plausibili, massimo 1000 rilevazioni), RLS sul proprietario, permessi espliciti.
- Progressi: misure salvate sul server, variazione di ogni misura dalla prima rilevazione, storico con eliminazione. Il peso resta visibile anche se le misure non si caricano. Misure e storico completo del peso sono Plus.
- Diario e Home: tocca un alimento registrato per cambiare grammi o alimento; dal menu si può togliere un singolo alimento o registrare di nuovo il pasto adesso.
- CI: anche i test della logica condivisa (`swift test` su CaloScanCore).

## Fase 5 – consegnato

- `analyze-food`: l'AI (Claude, modello in `AI_MODEL`) riconosce solo alimenti e grammi; calorie e macro arrivano da USDA FoodData Central. Risposta con schema JSON fisso e ripulita lato server (`sanitizeAIResult`).
- `food-search`: USDA (ricerca tradotta in inglese, nomi tradotti in italiano) + Open Food Facts (prodotti italiani e codici a barre), cache di 30 giorni in `food_search_cache`.
- `get-entitlements`: piano e scansioni di oggi. Scanner AI solo nei piani a pagamento: Plus 4 al giorno, Pro 15; Free usa ricerca, codice a barre e inserimento manuale. Contano solo le analisi riuscite (`scan_events`).
- Foto: mai salvate sui server. La miniatura del pasto resta solo sul telefono (`MealPhotoStore`), esclusa dal backup e cancellata con il pasto o all'uscita.
- Consensi controllati dal server: dati sanitari sempre, analisi foto solo quando si invia una foto.
- Nuova grafica: sfondi sfumati, ombre morbide, un colore per pasto, anelli più grandi per calorie e macro, serie di giorni registrati, haptics.
- Test: 54 test TypeScript, controllo tipi Deno e prova dal vivo di USDA e Open Food Facts in CI.

Funzioni Plus e Pro segnate da una filigrana con lucchetto (vedi ARCHITECTURE §8). Fino alla Fase 8 tutti gli utenti hanno il piano Free; per provare lo scanner, gli account in `TESTER_USER_IDS` hanno Pro.

## Fase 4 – consegnato

- Migrazione `20261124000001_fase4_diario_spesa.sql`:
  - `meals`: pasti con gli alimenti e i loro valori per 100 g (il diario non cambia se cambia il database alimenti); vincolo `meal_items_valid` con gli stessi limiti dell'app (1–3000 g, valori plausibili, max 50 alimenti).
  - `shopping_items`: lista della spesa, massimo 200 prodotti per utente (trigger).
  - RLS sul proprietario, cancellazione a cascata, permessi espliciti.
- Funzione `save-professional-plan`: salva o elimina il piano del medico o dietista dopo averlo rivalidato (`_shared/professionalPlan.ts`, test inclusi).
- App: `SupabaseMealRepository` (Home, Diario, statistiche), `SupabaseShoppingListService`, salvataggio del piano del professionista.
- Barra di navigazione: linea di separazione dietro il pulsante Scanner, icone più grandi.
- Permessi espliciti per `authenticated` e `service_role` anche sulle tabelle della Fase 3 (migrazioni `…0002`, `…0003`).

Dalla Fase 9 tutti i servizi dell'app sono collegati al server.

## Fase 3 – consegnato

- Accesso con Apple, Google ed email/password su Supabase Auth (`SupabaseAuthService`); sessione nel Keychain, rinnovo automatico.
- Link delle email (`caloscan://auth-callback`): conferma registrazione e recupero password con schermata "Nuova password".
- Dopo l'accesso: se il profilo non esiste parte l'onboarding, altrimenti la Home (con cache locale solo dell'ID per l'uso offline).
- Migrazione `20261123000001_fase3_profili_consensi.sql`: `profiles`, `professional_plans`, `consents` + storico `consent_events`, `weight_entries`, tutte con RLS e cancellazione a cascata.
- Funzione `save-profile`: rivalida profilo e obiettivi sul server (`_shared/profile.ts`, test inclusi: età minima 16 anni, intervalli, obiettivo calorico sicuro).
- Funzione `delete-account`: cancella account e dati.
- Bundle ID `com.andrewnalini.caloscan.app`.

Ancora `NotConnectedService` dopo la Fase 3: pasti, ricerca, scanner, coach, misure corporee, abbonamenti, push, lista della spesa, inviti, export dati, salvataggio del piano del professionista.

I servizi di produzione restano `NotConnectedService` (errore esplicito, nessun dato finto) finché ogni fase non collega il proprio backend.
