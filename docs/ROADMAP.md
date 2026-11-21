# Roadmap

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | Architettura e struttura del progetto | ✅ completata |
| 2 | Design system e schermate principali | ⏳ prossima |
| 3 | Registrazione, login, onboarding | |
| 4 | Database (schema + RLS) e backend | |
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
