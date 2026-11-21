# CaloScan

App iOS di monitoraggio nutrizionale con scansione AI dei piatti, diario, coach AI e abbonamenti.

- **Architettura:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Cosa configurare:** [docs/SETUP.md](docs/SETUP.md)
- **Avanzamento per fasi:** [docs/ROADMAP.md](docs/ROADMAP.md)

## Struttura

```
ios/        App SwiftUI (MVVM) + pacchetto CaloScanCore (logica di dominio)
supabase/   Database, RLS, Edge Functions (AI, ricerca alimenti, abbonamenti)
docs/       Documentazione
```

## Avvio rapido (Mac)

```bash
brew install xcodegen supabase/tap/supabase
cp ios/Config/Secrets.example.xcconfig ios/Config/Secrets.xcconfig   # compila i valori
cd ios && xcodegen generate && open CaloScan.xcodeproj
```

Test della logica di dominio:

```bash
cd ios/Packages/CaloScanCore && swift test                                        # Swift
node --experimental-strip-types --test supabase/functions/_shared/*.test.ts       # server
```
