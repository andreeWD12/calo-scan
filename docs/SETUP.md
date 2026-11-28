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
    Per vedere il paywall con i prezzi prima che App Store Connect renda disponibili i prodotti (es. per lo screenshot di revisione),
    scegli in Xcode lo schema **CaloScan StoreKit locale**: usa i prodotti finti di `ios/StoreKit/CaloScan.storekit`. Con questo schema
    gli acquisti non passano dal server, quindi il piano non cambia: per le prove vere torna allo schema **CaloScan**.
15. Prima della pubblicazione togli `TESTER_USER_IDS` (`supabase secrets unset TESTER_USER_IDS`): da qui in poi il piano arriva solo dagli abbonamenti.

## Fase 9 – Notifiche, privacy, inviti

16. Codice e database, dalla cartella `~/calo-scan`:
    ```
    git fetch && git checkout fase-9-privacy && git pull
    supabase db push --remote
    supabase functions deploy export-data referral push-dispatch delete-account verify-purchase app-store-notifications get-entitlements
    cd ios && xcodegen generate
    ```
17. **Una chiave per i servizi Apple** (notifiche, DeviceCheck, revoca di "Accedi con Apple"): developer.apple.com › *Certificates, IDs & Profiles* ›
    **Keys** › **+**. Nome "CaloScan servizi", spunta **Apple Push Notifications service (APNs)**, **DeviceCheck** e **Sign in with Apple**
    (per quest'ultimo *Configure* › App ID principale `com.andrewnalini.caloscan.app`). *Continue* › *Register* › **Download** del `.p8`
    (si scarica una volta sola) e annota il **Key ID**. Il **Team ID** è in alto a destra nella pagina (10 caratteri).
    ```
    supabase secrets set APPLE_TEAM_ID="XXXXXXXXXX" APPLE_SERVICES_KEY_ID="YYYYYYYYYY"
    supabase secrets set APPLE_SERVICES_PRIVATE_KEY="$(tr -d '\n' < ~/Downloads/AuthKey_YYYYYYYYYY.p8)"
    ```
    È una chiave diversa da quella In-App Purchase della Fase 8: servono entrambe.
18. **Invio pianificato delle notifiche** (ogni 10 minuti). Crea un segreto casuale e salvalo su Supabase:
    ```
    openssl rand -hex 32
    supabase secrets set PUSH_CRON_SECRET="il-valore-appena-generato"
    ```
    Dashboard Supabase › **Database › Extensions**: attiva `pg_cron` e `pg_net`. Poi **SQL Editor** › New query, sostituisci il segreto e premi *Run*:
    ```sql
    select vault.create_secret('il-valore-appena-generato', 'push_cron_secret');
    select cron.schedule('push-dispatch', '*/10 * * * *', $$
      select net.http_post(
        url := 'https://bvfwujdugqzlwikuycmi.supabase.co/functions/v1/push-dispatch',
        headers := jsonb_build_object('x-cron-secret',
          (select decrypted_secret from vault.decrypted_secrets where name = 'push_cron_secret')),
        body := '{}'::jsonb);
    $$);
    ```
    Verifica: Edge Functions › `push-dispatch` › Logs mostra ogni 10 minuti "0 inviate, 0 da riprovare".
19. **Premi degli inviti** (codici offerta Apple) – **da fare dopo la prima approvazione**: Apple genera codici monouso solo quando
    l'abbonamento è approvato. Fino ad allora gli inviti funzionano lo stesso: chi ha un invito valido vede "lo stiamo preparando"
    e riceve codice e notifica appena importi il lotto.
    1. App Store Connect › la tua app › **Abbonamenti** › Plus mensile (`caloscan.plus.monthly`) › **Codici offerta** › *Crea codice offerta*:
       nome di riferimento `ref30`; idoneità **Nuovi clienti** (chi non è mai stato abbonato); tipo **Pagamento a consumo**
       (*Pay as you go*), durata **1 mese**; prezzo: per l'Italia **2,99 €** (su 4,99 € è il 40%: i prezzi Apple finiscono in ,99 e il 30% esatto,
       3,49 €, non esiste). Lascia che App Store Connect calcoli gli altri paesi. Conferma.
    2. Nello stesso codice offerta › *Codici monouso* › *Genera*: quantità **500**, scadenza **la più lontana proposta**. Dopo qualche minuto
       compare *Scarica*: salva il file (es. in `~/Downloads`). Annota la scadenza.
    3. Dal Terminale, in `~/calo-scan` (dopo `git pull`):
       ```
       scripts/import-offer-codes.sh ~/Downloads/<file scaricato> <scadenza AAAA-MM-GG>
       ```
       Controlla che il numero di codici trovati sia 500. Lo script crea `<file>-import.sql`: aprilo, copia tutto in
       Supabase › **SQL Editor** e premi *Run*. Il risultato `premi_assegnati_ora` indica quanti premi in attesa sono partiti subito.
       Il file dei codici e quello .sql restano sul tuo Mac: non metterli nel repository (sono codici che valgono soldi).
    4. Etichetta mostrata in app e App Store ID (App Store Connect › *Informazioni app* › Apple ID):
       ```
       supabase secrets set REFERRAL_DISCOUNT_LABEL="40%" APP_STORE_ID=1234567890
       ```
       Se scegli un altro prezzo, l'etichetta è lo sconto arrotondato (es. 3,99 € su 4,99 € = `"20%"`).
    5. Prova: con un account che ha un invito valido apri Profilo › Invita un amico: compare il codice con *Riscatta*.
    Codici liberi rimasti: `select count(*) from public.offer_code_pool where assigned_to is null and expires_at > now() + interval '7 days';`
    Controllalo una volta al mese e, sotto 100 o un mese prima della scadenza, genera un nuovo lotto e ripeti i passi 2–3.
20. **Pagine web** (GitHub Pages, gratis perché il repository è pubblico): GitHub › Settings › Pages › *Deploy from a branch*, branch `main`,
    cartella `/ (root)`. Dopo il merge rispondono:
    `https://andreewd12.github.io/calo-scan/privacy/`, `.../terms/` e `.../support/`. Prima completa **l'indirizzo** del titolare
    (evidenziato in giallo in `privacy/index.html` e `terms/index.html`). Consigliato un controllo legale: l'app tratta dati sulla salute (art. 9 GDPR).
    Gli stessi URL vanno in `ios/Config/Secrets.xcconfig` (`PRIVACY_POLICY_URL`, `TERMS_URL`, `SUPPORT_URL`) e in App Store Connect.
21. **Prova**: Profilo › Privacy e account › *Esporta i miei dati* (file JSON da condividere); Profilo › Invita un amico (codice personale);
    con un secondo account inserisci il codice e registra un pasto: dopo al massimo 10 minuti il primo account riceve la notifica del premio.

## Fase 10 – Pubblicazione

Testi, risposte e liste di controllo pronti da copiare sono in **`docs/APP_STORE.md`**. Qui l'ordine dei passaggi.

22. **Codice aggiornato**, dalla cartella `~/calo-scan` (dopo il merge della PR della Fase 10):
    ```
    git checkout main && git pull
    cd ios && xcodegen generate && cd ..
    ```
    Versione e numero di build sono in `ios/Config/Version.xcconfig` (1.0.0, build 1).
23. **Server pronto per il lancio**:
    ```
    supabase db push --remote
    supabase functions deploy
    supabase secrets unset TESTER_USER_IDS
    ```
    (`functions deploy` senza nomi pubblica tutte le funzioni.) Poi passa a **Supabase Pro** (circa 25 $/mese,
    Dashboard › Organization › Billing): i progetti gratuiti si sospendono dopo una settimana senza attività e hanno backup limitati.
    In Authentication › URL Configuration controlla che `caloscan://auth-callback` sia tra i Redirect URLs.
24. **Indirizzo del titolare** nelle pagine legali (evidenziato in giallo in `privacy/index.html` e `terms/index.html`), commit e push su `main`.
    Le pagine devono essere online prima dell'invio: Apple le apre durante la revisione.
25. **Stato di trader UE**: App Store Connect › *Business* › la tua organizzazione › *Compliance* › Digital Services Act ›
    "Sono un trader" e inserisci indirizzo, telefono ed email (Apple li mostra agli utenti UE). Senza, l'app non esce in Italia.
26. **Carica la build** da Xcode sul Mac:
    1. In alto scegli lo schema **CaloScan** e come dispositivo **Any iOS Device (arm64)**.
    2. Menu **Product › Archive** (qualche minuto). Si apre l'Organizer.
    3. **Distribute App › App Store Connect › Distribute**. Lascia le opzioni predefinite (firma automatica).
    4. Dopo 10–30 minuti la build compare in App Store Connect › **TestFlight** (arriva anche un'email). Alla domanda
       sulla crittografia non devi rispondere: è già nel progetto.
    Per ogni nuovo caricamento aumenta `CURRENT_PROJECT_VERSION` in `ios/Config/Version.xcconfig` (2, 3, …) e rifai `xcodegen generate`,
    altrimenti Apple rifiuta la build con "bundle version already used".
27. **TestFlight**: TestFlight › *Internal Testing* › **+** › aggiungi te stesso. Installa l'app **TestFlight** sull'iPhone, apri CaloScan da lì
    e segui la lista di prova in `docs/APP_STORE.md` § 9. Le notifiche push di TestFlight usano i server di produzione di Apple:
    è normale, è già gestito.
    Sempre da TestFlight crea l'**account di revisione**: registrati con un'email nuova che controlli tu (es. un alias iCloud),
    conferma la mail, completa l'onboarding e registra due o tre pasti. Lascialo sul piano Free.
28. **Scheda dell'app** in App Store Connect › la tua app › versione **1.0**: testi, parole chiave, URL, screenshot (scaricali da GitHub ›
    Actions › ultima esecuzione "Build iOS" › Artifacts › `app-store-screenshots`), *App Privacy*, classificazione per età,
    *App Review Information* con l'account di revisione e le note. Tutto in `docs/APP_STORE.md` §§ 1–7.
    In *Build* scegli la build caricata.
29. **Abbonamenti nella prima versione**: nella pagina della versione 1.0, sezione *In-App Purchases and Subscriptions*, premi **+**
    e seleziona tutti e 5 gli abbonamenti. Devono essere "Ready to Submit" (nome, descrizione, prezzo e screenshot di revisione).
30. **Invia**: *Add for Review* › *Submit to App Review*. La revisione richiede di solito 1–3 giorni. Se Apple chiede chiarimenti o rifiuta,
    copia il messaggio di Apple in questo progetto: lo sistemiamo insieme. Puoi scegliere "Rilascia manualmente" per decidere tu il giorno.
31. **Dopo l'approvazione**: crea i codici offerta `ref30` degli inviti (passo 19) e imposta `APP_STORE_ID`
    (App Store Connect › *Informazioni app* › Apple ID) sia in `ios/Config/Secrets.xcconfig` sia con
    `supabase secrets set APP_STORE_ID=...`. L'`APP_STORE_ID` nell'app vale dalla versione successiva.

Tutti i segreti server sono elencati in `supabase/.env.example`.
