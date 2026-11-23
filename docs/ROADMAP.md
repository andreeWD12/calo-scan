# Roadmap

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | Architettura e struttura del progetto | ✅ completata |
| 2 | Design system e schermate principali | ✅ completata |
| 3 | Registrazione, login, onboarding (collegamento a Supabase Auth) | ✅ completata |
| 4 | Database (schema + RLS) e backend | ✅ completata |
| 5 | AI Food Scanner e analisi nutrizionale | ✅ completata |
| 6 | Diario e statistiche | ⏳ prossima |
| 7 | AI Nutrition Coach | |
| 8 | Abbonamenti Free / Plus / Pro | |
| 9 | Notifiche, privacy, sicurezza | |
| 10 | Test, bug fixing, preparazione App Store | |

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

Ancora `NotConnectedService` dopo la Fase 5: misure corporee (Fase 6), coach e suggerimenti AI della spesa (Fase 7), abbonamenti e inviti (Fase 8), push ed export dati (Fase 9).

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
