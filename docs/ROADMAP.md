# Roadmap

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | Architettura e struttura del progetto | ✅ completata |
| 2 | Design system e schermate principali | ✅ completata |
| 3 | Registrazione, login, onboarding (collegamento a Supabase Auth) | ✅ completata |
| 4 | Database (schema + RLS) e backend | ⏳ prossima |
| 5 | AI Food Scanner e analisi nutrizionale | |
| 6 | Diario e statistiche | |
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
