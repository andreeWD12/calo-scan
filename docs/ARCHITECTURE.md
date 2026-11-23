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

In Home, in alto a destra: corona (piani Plus/Pro; per gli utenti Pro, gestione dell'abbonamento) e ✦ (coach). Alla fine dell'onboarding, dopo la scelta del piano, `AppGuideView` spiega in 7 pagine tutte le funzioni e i pulsanti (Home, Scanner, Diario, Progressi, Coach, Profilo, piani); si può saltare ed è riapribile da Profilo → Guida all'app.

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
- **Pasti del piano**: il piano può contenere i pasti (colazione, pranzo, cena, spuntini) con alimenti e grammature, uguali ogni giorno oppure diversi per giorno della settimana (`PlannedDay.weekday`, 1 = domenica come `Calendar`). Ogni alimento può essere collegato al database (allora ha valori nutrizionali) o restare solo nome + grammi (promemoria, non conteggiato). In Home e Diario, se un pasto non è ancora registrato, compare "Dal tuo piano" con **Registra come da piano**: l'utente conferma o corregge i grammi e il pasto viene salvato con `source = 'plan'`. Il piano si ripete da solo, senza ricompilarlo: i pasti sono legati al giorno della settimana, non a una data. **Rotazione**: se il piano alterna settimane diverse (es. settimana 1 e 2), `rotation_weeks` (1–4) indica dopo quante settimane ricomincia e `PlannedDay.week` a quale settimana appartiene ogni giorno; la settimana in corso si calcola dalle settimane trascorse (da lunedì) rispetto a `rotation_anchor` (una data della settimana 1; null = data di inizio), con `rotationWeek` (TS) / `ProfessionalPlan.rotationWeek` (Swift), stessi test. L'utente può riallineare la rotazione ("Questa settimana è la settimana N"). Validazione `isValidMealPlan` (TS) / `ProfessionalPlan.isValid(mealPlan:rotationWeeks:)` (Swift): massimo un giorno per settimana e weekday, settimane 1…`rotation_weeks`, un pasto per tipo, 30 alimenti per pasto, grammi 1–3000.
- **Sgarri**: ogni pasto (scansionato, descritto o inserito a mano) può essere segnato come sgarro (`meals.is_cheat_meal`), anche dopo, dal menu contestuale del diario. Conta nelle calorie del giorno come ogni altro pasto; `NutritionStats.cheatMeals` dà numero, calorie e quota sul totale, mostrati nel giorno, nella settimana e nel mese. Linguaggio neutro: nessun punteggio, colpa o "compensazione" suggerita (anche il coach segue questa regola).
- Lo stesso algoritmo esiste in Swift (`CaloScanCore`) e in TypeScript (`supabase/functions/_shared/nutrition.ts`), con gli stessi casi di test.

## 7. Database (dettagli in Fase 4)

Tabelle: `users` (vista su `auth.users` → tabella `public.users` 1:1), `user_profiles`, `user_goals`, `user_preferences`, `food_items`, `food_scans`, `meals`, `meal_items`, `daily_nutrition`, `weight_history`, `body_measurements`, `nutrition_reports`, `ai_conversations`, `ai_messages`, `subscriptions`, `subscription_usage`, `consents`, `professional_plans` (1:1 con l'utente: professionista, nome facoltativo, kcal, macro facoltativi, note, data di inizio e di controllo, `confirmed_at`, `meal_plan` JSONB, `rotation_weeks smallint default 1`, `rotation_anchor date`; CHECK identici a `validateProfessionalPlan`). `meals` ha anche `is_cheat_meal boolean default false` e `source` in (`scan`, `description`, `manual`, `plan`).

Regole:
- RLS attiva su **ogni** tabella; policy `user_id = auth.uid()`.
- `food_items` pubblici in sola lettura; alimenti personalizzati visibili solo al proprietario.
- `subscriptions` e `subscription_usage` **non scrivibili** dal client: solo le Edge Functions con service role.
- Vincoli `CHECK` su grammi, kcal, peso, altezza; date validate.
- Cancellazione account → `ON DELETE CASCADE` da `auth.users` + pulizia Storage.

## 8. Abbonamenti

| Piano | Scansioni AI/giorno | Coach | Statistiche |
|---|---|---|---|
| Free | 0 (ricerca, codice a barre e inserimento manuale gratuiti) | messaggi base limitati (5/giorno) | settimanali di base |
| Plus | 4 (una per pasto) | consigli personalizzati (30 msg/giorno) | settimanali + mensili complete |
| Pro | 15 | coach avanzato, piani pasto, ricette, lista spesa (150 msg/giorno) | report mensili avanzati |

Limiti in `SCAN_LIMITS` (`supabase/functions/_shared/scan.ts`), applicati da `analyze-food` e mostrati da `get-entitlements`: si cambiano con un nuovo deploy delle funzioni, senza rilasciare l'app. Lo scanner AI è riservato ai piani a pagamento per contenere i costi del fornitore AI (decisione del 23/11/2026). Le analisi fallite non contano. Costi AI: monitorare il costo medio per utente sul cruscotto del fornitore. Product ID: `caloscan.plus.monthly`, `caloscan.plus.yearly`, `caloscan.pro.monthly`, `caloscan.pro.yearly`, più `caloscan.pro.monthly.pregnancy` (Pro, solo per l'offerta gravidanza); i prezzi si impostano in App Store Connect.

### Lista della spesa

Da Home (icona carrello in alto a sinistra) e da Profilo. Prodotti raggruppati per reparto (`ShoppingCategory.guess` sceglie il reparto dal nome; l'utente lo cambia con la pressione prolungata), spunta con un tocco, eliminazione, rimozione dei prodotti presi, condivisione come testo.

| Funzione | Piano |
|---|---|
| Inserimento manuale, spunta, condivisione | Tutti (Free compreso) |
| Prodotti dai pasti del piano del professionista per 7 giorni, grammature sommate (`ShoppingListBuilder`, nessuna AI) | Tutti |
| Suggerimenti AI (`shopping-suggest`): obiettivi, piano, preferenze e pasti recenti; l'utente sceglie cosa aggiungere | Plus: 2 liste a settimana · Pro: fino a 5 al giorno (in `plan_limits`) |

Allergeni: il prompt li esclude e il server applica comunque `filterSuggestions` (`_shared/shopping.ts`, con test) prima di rispondere. Tabella `shopping_items` (id, user_id, name, quantity, category, is_checked, source `manual`/`plan`/`ai`, added_at) con RLS sul proprietario, massimo 200 prodotti.

Allergeni nell'onboarding: i 14 del Reg. UE 1169/2011 più intolleranza al lattosio e voce libera; modificabili dal Profilo.

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

## Codici offerta

I codici si creano in **App Store Connect** (Abbonamenti › Codici offerta): codici singoli o personalizzati (es. `CALOSCAN30`), con mesi gratuiti o prezzo scontato, anche solo per nuovi clienti. L'app non ha un sistema di codici proprio (linea guida 3.1.1): il pulsante "Riscatta un codice" (paywall e Profilo › Abbonamento) apre il foglio di Apple (`offerCodeRedemption`, iOS 17.2+; `AppStore.presentOfferCodeRedeemSheet` su 17.0–17.1). La transazione risultante passa dalla stessa verifica server degli acquisti (`verify-purchase`, App Store Server Notifications con `offerType` / `offerIdentifier`). I codici si possono riscattare anche dal link `https://apps.apple.com/redeem?ctx=offercodes&id=<APP_ID>&code=<CODICE>`.

## Inviti ("Invita un amico")

**Premio**: chi invita riceve **uno sconto sul primo mese** di Plus o Pro: **30%**, **uno solo e non accumulabile**, anche se invita più amici. Lo sconto non viene applicato dall'app: è un **codice offerta Apple monouso** (linea guida 3.1.1).

**Configurazione in App Store Connect** (una volta, e ricaricando il lotto quando serve):
1. Abbonamenti › Plus mensile (e Pro mensile) › Codici offerta › nuovo codice: idoneità "Nuovi clienti", tipo "pay as you go" (prezzo scontato per il primo periodo), 1 mese al **30% di sconto** (prezzo del primo mese = 70% del prezzo mensile, per ogni paese).
2. Genera **codici monouso** (rispettando i limiti trimestrali e le scadenze indicati da App Store Connect) e scarica il CSV.
3. Importa il CSV nella tabella `offer_code_pool` (solo service_role). Da lì il server assegna i codici da solo: nessuna azione manuale per ogni invito.
4. Il server avvisa (email all'amministratore) quando restano meno di 100 codici liberi o quando il lotto sta per scadere: si genera un nuovo lotto e si ripete il passo 3.

**Regole** (`supabase/functions/_shared/referral.ts`, testate):
- Ogni utente ha un codice personale di 8 caratteri (`generateReferralCode`, alfabeto senza 0/O/1/I/L, CSPRNG); l'app lo mostra come `ABCD-2345`.
- L'amico lo inserisce nell'onboarding (passo "Come ti chiami?", facoltativo) o da Profilo › Invita un amico, **entro 14 giorni** dall'iscrizione e **una sola volta**; non vale il proprio codice (`evaluateApply`).
- L'invito diventa **valido** quando l'amico completa l'onboarding e registra almeno un pasto (`isQualified`), non al semplice download. Contro gli account multipli sullo stesso iPhone si usa **DeviceCheck** (2 bit per dispositivo, nessun identificatore salvato).
- Al primo invito valido il server assegna al referrer un codice del lotto (`decideReward`): niente se ha già avuto un premio (non accumulabile) o se è già stato abbonato (lo sconto è sul primo mese). Il codice vale 60 giorni; l'utente lo riscatta con il link Apple precompilato (`https://apps.apple.com/redeem?ctx=offercodes&id=APP_STORE_ID&code=…`) o con il foglio "Riscatta un codice".
- Notifica push al referrer quando il premio è pronto (Fase 9).

**Tabelle** (RLS: ogni utente legge solo le proprie righe; scrittura solo dalla Edge Function `referral`):
- `referral_codes` (user_id PK → users ON DELETE CASCADE, code UNIQUE).
- `referrals` (referred_id PK → users ON DELETE CASCADE, referrer_id → users ON DELETE SET NULL, created_at, qualified_at). Un amico ha al massimo un referrer.
- `referral_rewards` (referrer_id PK → users ON DELETE CASCADE ⇒ **un premio per utente per sempre**, offer_code, assigned_at, expires_at, redeemed_at da App Store Server Notifications `offerIdentifier`).
- `offer_code_pool` (code PK, offer_id, expires_at, assigned_to NULL) — solo service_role.

**Edge Function `referral`**: `GET` stato (`ReferralStatus`), `POST {code}` → `ReferralApplyResult`. La qualificazione la valuta un trigger su `meals` (primo pasto) + flag onboarding. Rate limit: 10 tentativi di inserimento codice al giorno per utente.

**Privacy**: l'app non legge la rubrica; la condivisione è il foglio di sistema. Il referrer vede solo i conteggi (amici iscritti, inviti validi), mai nomi o email degli amici.

## Stile alimentare scelto con il coach (solo Pro)

Da Coach o da Profilo › Stile alimentare l'utente sceglie, con l'aiuto del coach AI, uno stile da un **catalogo chiuso** (`EatingStyle`, Swift / `EATING_STYLES`, TS): equilibrata, mediterranea, ricca di proteine, pochi carboidrati (moderata), vegetariana, vegana, digiuno intermittente 12:12, 14:10, 16:8. Esclusi per scelta: digiuni oltre 16 ore, 5:2, digiuni di giorni interi, chetogenica, diete a bassissimo contenuto calorico. Gli obiettivi calorici restano quelli calcolati (con le soglie minime) o del professionista: lo stile cambia *come* si distribuiscono i pasti, non abbassa le calorie.

**Flusso**: 4 domande di sicurezza obbligatorie (gravidanza/allattamento, farmaci per il diabete, disturbi alimentari, altre condizioni seguite dal medico) → abitudini (pasti al giorno, quando si ha fame, allenamento, nota) → Edge Function `coach-eating-style` → fino a 3 proposte con motivazione e primi passi → scelta → per i digiuni, orario della finestra e promemoria facoltativi (spenti di default, locali).

**Sicurezza** (`EatingStyleSafety` / `styleBlocks`, stessi test):
- Digiuni: esclusi sotto i 18 anni e con BMI < 18,5.
- Stili restrittivi (digiuni e pochi carboidrati): esclusi con una qualsiasi risposta "Sì" alle domande di sicurezza.
- Con un piano del professionista nessuno stile è selezionabile: vale il piano.
- Il server calcola gli stili ammessi e passa al modello **solo quelli**; l'output è filtrato da `sanitizeProposals` (solo stili ammessi, max 3, niente doppioni, testo ripulito, claim sulla salute vietati sostituiti con la descrizione neutra del catalogo — Reg. UE 1924/2006).
- L'app ricontrolla le regole prima di salvare. Le risposte di sicurezza **non vengono salvate**: servono solo per la richiesta.

**Dati**: `user_profiles.eating_style jsonb` (`EatingStyleChoice`: stile, finestra, data, promemoria). In Home, per i digiuni, il riquadro "Finestra alimentare aperta / Pausa dal cibo" con l'orario del prossimo cambio, senza conti alla rovescia o toni di sfida. Solo Pro (`AppState.hasEatingStyles`; il server rifiuta le richieste dagli altri piani): fino a 10 richieste di proposte al giorno (`plan_limits`).

## Modalità gravidanza (tutele per tutti, dieta completa con Pro)

| Funzione | Piano |
|---|---|
| Mai deficit calorico (almeno mantenimento), niente digiuni né stili restrittivi, elenco degli alimenti da evitare in Profilo › Gravidanza | Tutti (Free compreso): sono tutele di sicurezza e non si vendono |
| Dieta per settimana (energia e proteine EFSA, consigli della fase, prossimo cambio), avvisi automatici su ricerca, scansioni e lista della spesa | Solo Pro (`AppState.hasPregnancyPlan`) |
| Esclusione degli alimenti *da evitare* dai suggerimenti AI (lista della spesa Plus) | Sempre, è una tutela |

**Datazione**: si chiede *a che settimana sei* (1–41, predefinito) oppure la data presunta del parto; si salva sempre la data (`PregnancyInfo.dueDate(week:days:)` / `dueDateFromWeek`, 280 giorni = 40 settimane), così la settimana avanza da sola ogni 7 giorni. Date valide: da 14 giorni fa (oltre il termine) a 294 giorni da oggi.

**Piano della settimana** (`PregnancyNutrition.weekPlan` / `pregnancyWeekPlan`, stessi test): dalla settimana derivano trimestre, energia e proteine in più, la settimana del prossimo cambio (14 e 28) e la fase dei consigli (1–13 nausea e acido folico dal medico; 14–27 ferro e calcio; 28–36 pasti piccoli e pesce a basso mercurio; 37+ nessuna dieta, idratazione e fibre). I valori di energia e proteine restano quelli ufficiali EFSA per trimestre: non inventiamo valori intermedi settimana per settimana.

Attivabile da onboarding ("Sono in gravidanza", per sesso femminile o non indicato) e da Profilo › Gravidanza. Dati: `user_profiles.pregnancy jsonb` (`PregnancyInfo`: data presunta del parto, immunità alla toxoplasmosi facoltativa) — dato sanitario art. 9 GDPR, con il consenso già raccolto.

- **Obiettivi** (`PregnancyNutrition` / `pregnancyTargets`, stessi test): mai in deficit. Mantenimento (Mifflin-St Jeor, obiettivo "mantieni") + energia EFSA 2013 per trimestre (+70 / +260 / +500 kcal) + proteine EFSA 2012 (+1 / +9 / +28 g); grassi 30%, carboidrati il resto. Il trimestre si aggiorna da solo dalla data presunta del parto. Il piano del professionista, se presente, ha la priorità. Con Free: `max(obiettivo calcolato, mantenimento)`; l'onboarding salva il mantenimento e il trimestre si aggiunge in `AppState.targets` solo con Pro. La modalità resta attiva fino a 2 settimane dopo la data presunta, poi l'app chiede di aggiornarla.
- **Alimenti** (`PregnancyFoodSafety.check` / `checkPregnancyFood`, stessi test con casi di falsi allarmi): regole per parole chiave con eccezioni ("cotto", "analcolica", "pastorizzato", "al forno"…). *Da evitare*: alcol, carne cruda, salumi crudi (da limitare se immune alla toxoplasmosi, per la listeria), pesce crudo e affumicato a freddo, uova crude, latte crudo e formaggi molli/erborinati non cotti, fegato e paté, pesci predatori grandi, germogli crudi, energy drink. *Con moderazione*: caffeina (≤ 200 mg/giorno, EFSA 2015), tonno, liquirizia.
- **Dove compare**: avviso accanto al nome in ricerca alimenti, risultati della scansione (nome + ingredienti, con spiegazione) e lista della spesa. I suggerimenti AI (lista della spesa, coach) escludono gli alimenti *da evitare* sul server (`filterForPregnancy`) e il prompt del coach riceve settimana e trimestre.
- **Stili alimentari**: in gravidanza niente digiuni né stili restrittivi; attivando la modalità, uno stile restrittivo già scelto viene rimosso.
- **Offerta gravidanza** (−30% per 3 mesi): se nell'onboarding è attivo "Sono in gravidanza", la scelta del piano mostra in cima una card Pro dedicata (anche da Profilo › Gravidanza › "Scopri l'offerta"). Prodotto `caloscan.pro.monthly.pregnancy` nello **stesso gruppo** di abbonamenti, stesso prezzo di Pro mensile, con **offerta introduttiva** Apple *Pay as you go*, 3 periodi da 1 mese al 70% del prezzo (es. 6,99 € invece di 9,99 €). StoreKit: `PlanOffer.audience = .pregnancy`, `introPrice` e `introMonths` da `product.subscription.introductoryOffer`, `isEligibleForIntro` da `Product.SubscriptionInfo.isEligibleForIntroOffer(for: groupID)`. Apple concede **una sola offerta introduttiva per gruppo** e Apple ID: chi ha già usato i 7 giorni gratis dell'annuale (o l'offerta stessa) non vede la card e resta il paywall normale. Il server tratta il prodotto come Pro (mappa `product_id → plan` delle funzioni di verifica e delle notifiche). Nessun dato di gravidanza va ad Apple: il prodotto è scelto in app. La card dice prezzo scontato, durata, prezzo successivo e rinnovo automatico; "Continua con il piano Free" resta sempre visibile.
- **Limiti dichiarati**: il riconoscimento per nome non è completo ("controlla l'etichetta"); integratori (es. acido folico), aumento di peso e dubbi clinici restano a ginecologo, ostetrica o medico. Fonti linkate in app (Ministero della Salute).

