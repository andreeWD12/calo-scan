# CaloScan — Architettura (Fase 1)

Documento di riferimento per tutte le fasi successive. Ogni scelta qui sotto è vincolante finché non viene aggiornata in questo file.

## 1. Visione d'insieme

```
┌──────────────────────── iPhone (iOS 17+) ────────────────────────┐
│ SwiftUI Views ──► ViewModels (@Observable, @MainActor)            │
│                      │                                            │
│                      ▼                                            │
│              Repository / Service protocols                       │
│      ┌───────────────┼──────────────────┬──────────────────┐      │
│  SupabaseAuth   SupabaseDB (RLS)   EdgeFunctionsClient   StoreKit 2│
│      │               │                  │                  │      │
└──────┼───────────────┼──────────────────┼──────────────────┼──────┘
       │ HTTPS/TLS     │ PostgREST        │ HTTPS + JWT      │ JWS signed tx
       ▼               ▼                  ▼                  ▼
┌──────────────────────────── Supabase ────────────────────────────┐
│ Auth (Apple, Google, email)   Postgres + RLS   Storage (privato)  │
│ Edge Functions (Deno/TS):                                         │
│   analyze-food   coach-chat   food-search   verify-purchase       │
│   app-store-notifications   export-data   delete-account          │
│   cleanup-images (cron)                                           │
└───────────┬──────────────────────┬───────────────────┬────────────┘
            ▼                      ▼                   ▼
     Modello AI multimodale   USDA FoodData Central   App Store Server API
     (chiave solo server)     + Open Food Facts       (verifica abbonamenti)
```

Principio guida: **il client è "non fidato"**. Tutto ciò che conta (quote di scansione, piano attivo, valori nutrizionali salvati, chiamate AI) viene deciso o verificato sul server.

## 2. Scelte tecnologiche

| Area | Scelta | Motivo |
|---|---|---|
| Linguaggio | Swift 6, strict concurrency | Sicurezza dei dati tra thread |
| UI | SwiftUI + Swift Charts | Nativo, dark mode, Dynamic Type, accessibilità |
| Pattern | MVVM con `@Observable` (Observation) | Meno boilerplate di `ObservableObject`, aggiornamenti granulari |
| iOS minimo | **iOS 17.0** | Necessario per Observation e API di Charts moderne; copre la quasi totalità degli iPhone attivi |
| Progetto | XcodeGen (`ios/project.yml`) | Il `.xcodeproj` si rigenera, niente conflitti di merge |
| Dipendenze | Swift Package Manager: `supabase-swift`, `GoogleSignIn-iOS` | Solo due dipendenze esterne |
| Logica di dominio | Pacchetto locale `CaloScanCore` (solo Foundation) | Testabile senza simulatore, riusabile |
| Backend | Supabase (Postgres 15, Auth, Storage, Edge Functions) | RLS nativa, auth Apple/Google pronta |
| AI | Provider multimodale chiamato **solo** dalle Edge Functions; provider e modello configurabili tramite variabili d'ambiente | Le chiavi non entrano mai nell'app |
| Valori nutrizionali | USDA FoodData Central (alimenti generici) + Open Food Facts (prodotti confezionati), cache in `food_items` | L'AI riconosce e stima i grammi, **non** inventa i valori nutrizionali |
| Abbonamenti | StoreKit 2 + App Store Server API + Server Notifications V2 | Stato dell'abbonamento autorevole sul server |

## 3. Struttura del repository

```
caloscan/
├── docs/                    Architettura, setup, roadmap
├── ios/
│   ├── project.yml          Definizione progetto XcodeGen
│   ├── Config/              xcconfig (Debug/Release, Secrets non versionato)
│   ├── Packages/CaloScanCore/   Modelli + calcoli nutrizionali + test
│   └── CaloScan/
│       ├── App/             Entry point, container dipendenze, routing radice
│       ├── Core/            Config, Networking, Security (Keychain), Logging, Services
│       ├── DesignSystem/    Token colori/tipografia, componenti riutilizzabili (Fase 2)
│       ├── Features/        Un modulo per area: View + ViewModel
│       │   ├── Auth/  Onboarding/  Home/  Diary/  Scanner/
│       │   ├── Progress/  Coach/  Profile/  Subscription/  Settings/
│       └── Resources/       Info.plist, Assets, PrivacyInfo, localizzazioni
└── supabase/
    ├── config.toml
    ├── migrations/          Schema SQL + RLS (Fase 4)
    └── functions/
        ├── _shared/         Codice condiviso (nutrizione, auth, entitlements)
        └── <funzione>/      Una cartella per Edge Function
```

## 4. Livelli dell'app iOS

1. **View** (SwiftUI): solo layout e binding. Nessuna chiamata di rete.
2. **ViewModel** (`@Observable @MainActor final class`): stato della schermata come enum `Loadable<T>` (`idle / loading / loaded / empty / failed`), azioni dell'utente, validazione input.
3. **Service / Repository** (protocolli in `Core/Services`): `AuthService`, `ProfileRepository`, `MealRepository`, `FoodSearchService`, `ScanService`, `CoachService`, `WeightRepository`, `SubscriptionService`, `NotificationService`. Le implementazioni concrete usano Supabase; nei test e nelle Preview si usano implementazioni in memoria.
4. **AppContainer**: crea le implementazioni una volta e le inietta tramite `Environment`. Nessun singleton globale nascosto.
5. **CaloScanCore**: tipi puri e calcoli (BMR, TDEE, obiettivi, macro, aggregazioni del diario). Nessuna dipendenza da UI o rete.

Navigazione: `TabView` con 5 sezioni (Home, Diario, Scanner, Progressi, Profilo). Lo Scanner è il tab centrale, reso con un pulsante circolare in evidenza che apre la fotocamera a schermo intero. Ogni tab ha il proprio `NavigationStack` con percorso tipizzato.

## 5. Flusso principale: scansione di un piatto

1. L'utente scatta la foto (AVFoundation). L'app ridimensiona a max 1280 px, JPEG ~0.7, **rimuove EXIF/GPS**.
2. Upload su Storage nel bucket privato `scans/{user_id}/{scan_id}.jpg` (policy RLS sul percorso).
3. L'app chiama `analyze-food` con `scan_id` e JWT dell'utente.
4. La funzione: verifica il JWT → controlla piano e quota in `subscription_usage` (transazione atomica) → genera URL firmato breve → chiama il modello multimodale con output JSON vincolato (nome, ingredienti, grammi stimati, metodo di cottura, confidenza, domande di chiarimento, es. "quanto olio?").
5. Per ogni alimento riconosciuto cerca la corrispondenza in `food_items` / USDA / Open Food Facts e calcola i nutrienti **dai valori per 100 g del database**. Se non trova corrispondenza affidabile, marca l'elemento come `needs_review`.
6. Salva il risultato in `food_scans` e lo restituisce. L'interfaccia mostra sempre i valori come **stime**, con la confidenza e le domande di chiarimento.
7. L'utente modifica/aggiunge/elimina/sostituisce alimenti e conferma → `meals` + `meal_items`. I totali giornalieri (`daily_nutrition`) si aggiornano con un trigger.
8. L'immagine viene cancellata automaticamente dopo il periodo di conservazione (default 30 giorni, configurabile; subito se l'utente lo sceglie).

### 5b. Descrizione a parole

Quando la foto non viene riconosciuta (o l'utente non vuole scattarla, o non ha dato il consenso all'analisi delle foto) può **descrivere il piatto**: "pasta al pomodoro, un piatto medio, con parmigiano".

- Punti di accesso: fotocamera ("Descrivi a parole"), schermata di errore dell'analisi, schermata del consenso foto ("Descrivi il piatto senza foto"), risultato della scansione ("Non è corretto? Descrivi il piatto").
- L'app ripulisce il testo con `FoodDescription.sanitize` (3–500 caratteri, niente caratteri di controllo); il server ripete la stessa regola con `sanitizeFoodDescription`.
- `analyze-food` accetta `{ description, scan_id? }`. Con `scan_id` (foto di un tentativo precedente) il modello riceve foto **e** testo; senza, solo il testo. Il resto del flusso è identico: output JSON vincolato, valori dai database, `needs_review` se manca la corrispondenza.
- Quota: conta come un'analisi AI. **Un'analisi che non riconosce alimenti non viene conteggiata**, così descrivere un piatto dopo una foto fallita non consuma due analisi.
- Il pasto salvato ha `source = 'description'`; il diario e i report distinguono foto, descrizione e inserimento manuale.

## 6. Calcoli nutrizionali

- **BMR**: Mifflin-St Jeor (1990). Uomo: 10·kg + 6,25·cm − 5·età + 5. Donna: stesso con −161. Se l'utente non indica il sesso biologico, si usa la media dei due valori e lo si spiega nell'interfaccia.
- **TDEE** = BMR × fattore attività (1,2 / 1,375 / 1,55 / 1,725 / 1,9).
- **Obiettivo**: perdita −15% del TDEE (max −500 kcal), aumento massa +10% (max +300 kcal), altrimenti mantenimento.
- **Limiti di sicurezza**: mai sotto il BMR né sotto 1.500 kcal (uomini) / 1.200 kcal (donne) / 1.350 (non specificato); minimo 18 anni per gli obiettivi di perdita peso; ritmo massimo di perdita indicato ~0,5–1% del peso a settimana.
- **Macro**: proteine 1,6 g/kg (aumento massa 1,8–2,0, perdita 1,8) limitate a 2,2 g/kg; grassi 25–30% delle kcal (minimo 0,6 g/kg); carboidrati = calorie rimanenti, con aggiustamento per preferenza low carb.
- Tutte le stime sono **modificabili** dall'utente; il server applica comunque gli stessi limiti minimi.
- **Piano del professionista**: se l'utente inserisce le calorie (ed eventualmente i macronutrienti e le indicazioni della dieta) ricevute da un medico, dietista o biologo nutrizionista, quei valori diventano l'obiettivo effettivo (`AppState.targets`). I macronutrienti non indicati mantengono le proporzioni degli obiettivi calcolati e i carboidrati coprono le kcal restanti (`ProfessionalPlan.dailyTargets` / `professionalPlanTargets`). Intervallo ammesso 800–6.000 kcal: sotto le soglie dell'app l'interfaccia mostra un avviso e chiede la conferma esplicita che il valore viene da un professionista. L'app non modifica né giudica il piano; il coach lo usa come riferimento e non propone obiettivi diversi. Promemoria locale il giorno dopo la data del controllo per aggiornarlo.
- **Pasti del piano**: il piano può contenere i pasti (colazione, pranzo, cena, spuntini) con alimenti e grammature, uguali ogni giorno oppure diversi per giorno della settimana (`PlannedDay.weekday`, 1 = domenica come `Calendar`). Ogni alimento può essere collegato al database (allora ha valori nutrizionali) o restare solo nome + grammi (promemoria, non conteggiato). In Home e Diario, se un pasto non è ancora registrato, compare "Dal tuo piano" con **Registra come da piano**: l'utente conferma o corregge i grammi e il pasto viene salvato con `source = 'plan'`. Validazione `isValidMealPlan` (TS) / `ProfessionalPlan.isValid(mealPlan:)` (Swift): massimo un giorno per weekday, un pasto per tipo, 30 alimenti per pasto, grammi 1–3000.
- **Sgarri**: ogni pasto (scansionato, descritto o inserito a mano) può essere segnato come sgarro (`meals.is_cheat_meal`), anche dopo, dal menu contestuale del diario. Conta nelle calorie del giorno come ogni altro pasto; `NutritionStats.cheatMeals` dà numero, calorie e quota sul totale, mostrati nel giorno, nella settimana e nel mese. Linguaggio neutro: nessun punteggio, colpa o "compensazione" suggerita (anche il coach segue questa regola).
- Lo stesso algoritmo esiste in Swift (`CaloScanCore`) e in TypeScript (`supabase/functions/_shared/nutrition.ts`), con gli stessi casi di test.

## 7. Database (dettagli in Fase 4)

Tabelle: `users` (vista su `auth.users` → tabella `public.users` 1:1), `user_profiles`, `user_goals`, `user_preferences`, `food_items`, `food_scans`, `meals`, `meal_items`, `daily_nutrition`, `weight_history`, `body_measurements`, `nutrition_reports`, `ai_conversations`, `ai_messages`, `subscriptions`, `subscription_usage`, `consents`, `professional_plans` (1:1 con l'utente: professionista, nome facoltativo, kcal, macro facoltativi, note, data di inizio e di controllo, `confirmed_at`, `meal_plan` JSONB; CHECK identici a `validateProfessionalPlan`). `meals` ha anche `is_cheat_meal boolean default false` e `source` in (`scan`, `description`, `manual`, `plan`).

Regole:
- RLS attiva su **ogni** tabella; policy `user_id = auth.uid()`.
- `food_items` pubblici in sola lettura; alimenti personalizzati visibili solo al proprietario.
- `subscriptions` e `subscription_usage` **non scrivibili** dal client: solo le Edge Functions con service role.
- Vincoli `CHECK` su grammi, kcal, peso, altezza; date validate.
- Cancellazione account → `ON DELETE CASCADE` da `auth.users` + pulizia Storage.

## 8. Abbonamenti

| Piano | Scansioni AI/giorno | Coach | Statistiche |
|---|---|---|---|
| Free | 3 | messaggi base limitati (5/giorno) | settimanali di base |
| Plus | 20 | consigli personalizzati (30 msg/giorno) | settimanali + mensili complete |
| Pro | 100 | coach avanzato, piani pasto, ricette, lista spesa (150 msg/giorno) | report mensili avanzati |

Limiti in tabella `plan_limits` (modificabili senza rilasciare l'app). Product ID: `caloscan.plus.monthly`, `caloscan.plus.yearly`, `caloscan.pro.monthly`, `caloscan.pro.yearly`; i prezzi si impostano in App Store Connect.

### Inviti all'upgrade

Schede compatte sopra la barra delle sezioni (`UpsellBanner`), mai a schermo intero e mai durante la fotocamera o un flusso in corso. Si chiudono con la X o da sole dopo 9 secondi. Compaiono 2,6 s dopo l'azione che le provoca, così non si sovrappongono al popup di conferma.

| Momento | Chi lo vede | Messaggio |
|---|---|---|
| Dopo aver salvato un pasto analizzato dall'AI, se resta 1 scansione o nessuna | Free → Plus, Plus → Pro | "Ti resta 1 scansione AI oggi · Con Plus hai 20 scansioni al giorno" |
| Dopo un messaggio al coach, se resta 1 messaggio o nessuno | Free → Plus, Plus → Pro | "Ultimo messaggio al coach per oggi · Con Plus hai 30 messaggi al giorno" |
| Dal 10° pasto salvato (utente costante) | Solo Free | "Stai registrando con costanza · Con Plus vedi le statistiche mensili" |

Regole (`UpsellPolicy`, testate in `UpsellPolicyTests`): mai per Pro; nessun invito nei primi 2 giorni dal primo avvio (tranne le scansioni in esaurimento, che è un'informazione utile); al massimo 1 al giorno e 2 a settimana; lo stesso invito al massimo una volta a settimana; dopo 3 chiusure con la X quel tipo di invito non compare più. Lo stato resta solo sul dispositivo (UserDefaults), senza tracciamento. Restano anche le schede fisse dove una funzione è riservata ai piani a pagamento (statistiche mensili, macronutrienti settimanali) e la schermata "Scansioni di oggi esaurite".

Flusso: StoreKit 2 acquista → l'app invia la transazione firmata (JWS) a `verify-purchase` → il server verifica la firma con l'App Store Server Library, salva in `subscriptions` con `appAccountToken = user_id` → le notifiche V2 di Apple (rinnovi, rimborsi, scadenze) aggiornano lo stato. Ogni funzione AI legge il piano **dal database**, mai dal client.

## 9. Sicurezza e privacy

- Nessuna chiave segreta nell'app: nel bundle c'è solo l'URL Supabase e la *anon key* pubblica (protetta da RLS).
- Token di sessione nel Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- Solo HTTPS (ATS attivo, nessuna eccezione).
- Immagini in bucket privato, URL firmati di breve durata, EXIF rimosso, cancellazione automatica.
- Dati sanitari: consenso esplicito registrato in `consents` (art. 9 GDPR), separato dall'accettazione dei termini.
- Esportazione dati (JSON) e cancellazione account dall'app (requisito Apple 5.1.1(v)).
- `PrivacyInfo.xcprivacy` con le API e i tipi di dati dichiarati.
- Avvertenze: il coach non diagnostica, non prescrive diete terapeutiche, rimanda a un professionista. Filtri lato server sulle risposte (niente obiettivi sotto i limiti di sicurezza, messaggio dedicato per segnali di disturbi alimentari).
- Rate limiting per utente sulle Edge Functions.

## 10. Notifiche

Notifiche **locali** per i promemoria (pasti, peso, riepilogo giornaliero): funzionano senza server e senza raccogliere token. Push remote (APNs) solo per il report settimanale e i suggerimenti, opzionali. Massimo 3 notifiche al giorno, orari scelti dall'utente, tutto disattivato di default tranne ciò che l'utente abilita nell'onboarding.

### Notifiche push (APNs)

- `AppDelegate` registra il dispositivo solo dopo che l'utente ha attivato una notifica (mai al primo avvio).
- Il token viene inviato a `PushTokenService` (tabella `push_tokens`, Fase 9); le notifiche remote partono da una Edge Function con chiave APNs `.p8`.
- Con l'app aperta le notifiche appaiono come banner; il tocco o un'azione rapida ("Scansiona il piatto", "Registra il peso") apre la schermata giusta tramite `DeepLinkRouter` (payload `{"route": "scanner"}` o URL `caloscan://scanner`).

## 11. Animazioni e feedback

- Molle di sistema (`.smooth`, `.snappy`, `.bouncy`) definite in `DS.Motion`; nessuna durata casuale sparsa nel codice.
- Entrate a cascata delle schede, profondità durante lo scroll (`scrollTransition`), anelli e barre che si riempiono, numeri che cambiano con `numericText`.
- Apertura dello scanner con zoom dal pulsante centrale (iOS 18, `navigationTransition(.zoom)`); su iOS 17 presentazione standard.
- Popup di conferma in stile iOS (`ToastCenter`) con feedback aptico e annuncio VoiceOver.
- Effetti SF Symbols (`symbolEffect`) su tab e azioni; feedback aptico su scatto, salvataggio ed errori.
- Con "Riduci movimento" attivo, spostamenti e scale diventano dissolvenze.

## 11b. Gestione errori e stati

- `APIError` tipizzato (`offline`, `unauthorized`, `quotaExceeded`, `server`, `decoding`, `aiUnavailable`) con messaggi localizzati.
- Ogni schermata gestisce: caricamento (skeleton), vuoto (con azione), errore (con "Riprova").
- Retry con backoff solo per errori transitori; mai per 4xx.

## 12. Modalità anteprima (solo Debug)

Le build Debug avviate con l'argomento `-PreviewMode` usano `PreviewStore` (servizi in memoria con dati d'esempio), utile per provare l'interfaccia nel simulatore e per i test. Con `-PreviewOnboarding` si parte dalla schermata di benvenuto. Il file è racchiuso in `#if DEBUG` e non esiste nelle build Release o App Store. Per attivarlo in Xcode: *Product → Scheme → Edit Scheme → Run → Arguments*.

## 13. Conformità

Requisiti GDPR, AI Act, MDR, consumatori, accessibilità e App Store, con lo stato di implementazione: `docs/COMPLIANCE.md`.

## 14. Limiti noti dell'ambiente di sviluppo

Questo progetto viene scritto in un ambiente Linux: non è possibile eseguire Xcode, il simulatore o compilare SwiftUI qui. La logica server (TypeScript) viene testata in questo ambiente; il codice Swift va compilato e verificato sul tuo Mac.
