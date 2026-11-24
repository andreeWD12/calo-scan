# Cosa devi configurare

Elenco completo dei servizi esterni. Ogni fase indica quando serve ciascuna voce: non è necessario fare tutto subito.

## Subito (per compilare l'app)

1. **Mac con Xcode 16 o successivo** e `brew install xcodegen`.
2. **Progetto Supabase** su supabase.com (piano Free va bene per lo sviluppo; regione UE consigliata per il GDPR, es. Frankfurt).
   - Da *Project Settings → API* copia **Project URL** e **anon public key** in `ios/Config/Secrets.xcconfig`.
   - La `service_role` key **non** va mai nell'app.

## Fase 3 – Autenticazione

3. **Apple Developer Program** (99 $/anno), necessario anche per Sign in with Apple e TestFlight.
   - Crea l'App ID `com.andrewnalini.caloscan.app` con la capability *Sign in with Apple* e *Push Notifications*.
   - Crea un *Services ID* e una chiave *Sign in with Apple* → inseriscili in Supabase → Authentication → Providers → Apple.
4. **Google Cloud Console**: crea un client OAuth **iOS** (per l'app) e uno **Web** (per Supabase).
   - Client iOS → `GOOGLE_IOS_CLIENT_ID` e `GOOGLE_REVERSED_CLIENT_ID` in `Secrets.xcconfig`.
   - Client Web → Supabase → Providers → Google.
5. In Supabase → Authentication → URL Configuration: **Site URL** = `caloscan://auth-callback` e, in **Redirect URLs**, aggiungi
   `caloscan://auth-callback` (conferma email e recupero password riaprono l'app da questo link).
6. Supabase → Authentication → Sign In / Providers: **Email** attivo con *Confirm email* acceso; **Apple** e **Google** quando
   hai i dati dei punti 3 e 4 (per Google spunta *Skip nonce checks*, richiesto dall'SDK iOS).
7. Configura un SMTP personalizzato (es. Resend, Postmark) per le email di conferma: quello predefinito di Supabase ha limiti
   molto bassi (poche email all'ora) e va bene solo per le prove.
8. **Database e funzioni** (dal Mac, nella cartella `calo-scan`):
   ```
   brew install supabase/tap/supabase
   supabase login
   supabase link --project-ref <ref del progetto>
   supabase db push --remote                          # crea tabelle, regole RLS e permessi (supabase/migrations)
   supabase functions deploy save-profile delete-account save-professional-plan
   ```
   Ogni migrazione concede esplicitamente i permessi (`grant`) sulle proprie tabelle: in questo progetto
   le nuove tabelle non li ricevono in automatico, e senza di essi l'app riceve "permission denied".
   `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` sono già disponibili alle funzioni: non vanno impostati.

## Fase 5 – AI

8. **Chiave Anthropic** (console.anthropic.com → API Keys) e **chiave USDA FoodData Central**
   (gratuita su fdc.nal.usda.gov/api-key-signup). Solo come segreti del server, mai nell'app:
   ```
   supabase secrets set ANTHROPIC_API_KEY=... USDA_FDC_API_KEY=...
   supabase db push --remote
   supabase functions deploy food-search analyze-food get-entitlements
   ```
   Facoltativi: `AI_MODEL` (predefinito `claude-opus-5-5`; un modello più economico abbassa i costi
   ma può riconoscere peggio i piatti) e `AI_EFFORT` (`low`, `medium` predefinito, `high`).
   Open Food Facts non richiede chiave.
   Lo scanner AI è solo per Plus e Pro. Per provarlo prima degli abbonamenti (Fase 8) dai il piano Pro
   al tuo account: copia il tuo User UID da Supabase → Authentication → Users e poi
   `supabase secrets set TESTER_USER_IDS=<il tuo UID>` (più account separati da virgola).

## Fase 7 – Coach

9. Nessuna nuova chiave (usa `ANTHROPIC_API_KEY`):
   ```
   supabase db push --remote
   supabase functions deploy coach-chat get-entitlements
   ```
   La chat è solo per Plus e Pro: per provarla prima della Fase 8 usa `TESTER_USER_IDS` come per lo scanner.

## Fase 8 – Abbonamenti

10. **App Store Connect** › la tua app › *Monetization* › *Subscriptions*: crea un *Subscription Group* "CaloScan Premium" con i 4 prodotti
    `caloscan.plus.monthly`, `caloscan.plus.yearly`, `caloscan.pro.monthly`, `caloscan.pro.yearly` e imposta i prezzi
    (proposta: Plus 4,99 € / 39,99 €, Pro 9,99 € / 79,99 €). Livelli del gruppo: Pro annuale e Pro mensile in alto, poi Plus.
    Facoltativo: sugli annuali un'*Introductory Offer* "Free trial" di 1 settimana.
    **Offerta gravidanza**: nello stesso gruppo crea anche `caloscan.pro.monthly.pregnancy` (nome "CaloScan Pro – Gravidanza",
    durata 1 mese, **stesso prezzo** di `caloscan.pro.monthly`, stesso livello di servizio). Nella sua pagina → *Subscription Prices* →
    *Introductory Offers* → **Pay as you go**, durata **3 mesi**, prezzo pari al 70% del normale (es. 6,99 € se Pro costa 9,99 €),
    in tutti i paesi in vendita. Se cambi il prezzo di Pro mensile, aggiorna anche questo prodotto e la sua offerta.
    Per ogni prodotto servono nome, descrizione e uno screenshot del paywall (per la revisione).
11. *Business* › firma il **Paid Applications Agreement** e inserisci dati fiscali e bancari (senza, gli acquisti non funzionano).
12. *Users and Access* › *Integrations* › **In-App Purchase** › genera una chiave. Scarica il file `.p8` (si scarica una volta sola) e annota
    *Key ID* e *Issuer ID*. Poi, dalla cartella del progetto:
    ```
    supabase secrets set APPLE_ISSUER_ID=... APPLE_KEY_ID=... APPLE_BUNDLE_ID=com.andrewnalini.caloscan.app
    supabase secrets set APPLE_PRIVATE_KEY="$(cat ~/Downloads/SubscriptionKey_XXXX.p8)"
    supabase db push --remote
    supabase functions deploy verify-purchase app-store-notifications get-entitlements
    ```
    La chiave resta solo nei segreti di Supabase: non metterla nel repository né nell'app.
13. *App Information* › **App Store Server Notifications** › V2, sia *Production* sia *Sandbox*:
    `https://bvfwujdugqzlwikuycmi.supabase.co/functions/v1/app-store-notifications`. Il pulsante "Send test notification" deve dare esito positivo.
14. **Prova con un account Sandbox** (*Users and Access* › *Sandbox*): sull'iPhone, Impostazioni › App Store › Account sandbox. Avvia l'app da Xcode,
    compra un piano dal paywall: il piano cambia subito e "Gestisci abbonamento" mostra scadenza e rinnovo. In Sandbox un mese dura 5 minuti.
    `ios/StoreKit/CaloScan.storekit` serve solo a vedere i prezzi del paywall senza App Store Connect (Xcode › Scheme › Run › Options ›
    StoreKit Configuration): con questo file gli acquisti non passano dal server, quindi il piano non cambia.
15. Prima della pubblicazione togli `TESTER_USER_IDS` (`supabase secrets unset TESTER_USER_IDS`): da qui in poi il piano arriva solo dagli abbonamenti.

## Fase 9–10 – Privacy e pubblicazione

16. Pagine pubbliche per **Informativa privacy** e **Termini di servizio** (URL richiesti da App Store Connect).
    Consigliato un controllo legale: l'app tratta dati relativi alla salute (art. 9 GDPR).
    **Pagina di assistenza** (GitHub Pages, gratis perché il repository è pubblico): GitHub › Settings › Pages ›
    *Deploy from a branch*, branch `main`, cartella `/ (root)`. La pagina è `support/index.html` e risponde su
    `https://andreewd12.github.io/calo-scan/support/` (la radice del sito mostra il README). Si aggiorna da sola a ogni modifica su `main`.
    Con un dominio tuo: Settings › Pages › *Custom domain*, poi aggiorna `SUPPORT_URL`. Privacy e termini andranno in `privacy/` e `terms/`.
    In `Secrets.xcconfig` imposta anche `SUPPORT_URL` (pagina di assistenza, richiesta da App Store Connect come *Support URL*,
    con un modo per contattarti) e `SUPPORT_EMAIL` (usata da Impostazioni › Assistenza › "Scrivici"; è visibile agli utenti).
17. Chiave APNs (.p8) per le notifiche push remote: Apple Developer → Keys → nuova chiave con *Apple Push Notifications service*. Serve anche la capability *Push Notifications* sull'App ID (già dichiarata in `project.yml`). I promemoria locali funzionano senza.
18. Icona dell'app 1024×1024, screenshot, descrizione e compilazione delle *App Privacy* in App Store Connect.

Tutti i segreti server sono elencati in `supabase/.env.example`.
