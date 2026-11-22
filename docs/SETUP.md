# Cosa devi configurare

Elenco completo dei servizi esterni. Ogni fase indica quando serve ciascuna voce: non è necessario fare tutto subito.

## Subito (per compilare l'app)

1. **Mac con Xcode 16 o successivo** e `brew install xcodegen`.
2. **Progetto Supabase** su supabase.com (piano Free va bene per lo sviluppo; regione UE consigliata per il GDPR, es. Frankfurt).
   - Da *Project Settings → API* copia **Project URL** e **anon public key** in `ios/Config/Secrets.xcconfig`.
   - La `service_role` key **non** va mai nell'app.

## Fase 3 – Autenticazione

3. **Apple Developer Program** (99 $/anno), necessario anche per Sign in with Apple e TestFlight.
   - Crea l'App ID `com.caloscan.app` (o il tuo bundle ID) con la capability *Sign in with Apple* e *Push Notifications*.
   - Crea un *Services ID* e una chiave *Sign in with Apple* → inseriscili in Supabase → Authentication → Providers → Apple.
4. **Google Cloud Console**: crea un client OAuth **iOS** (per l'app) e uno **Web** (per Supabase).
   - Client iOS → `GOOGLE_IOS_CLIENT_ID` e `GOOGLE_REVERSED_CLIENT_ID` in `Secrets.xcconfig`.
   - Client Web → Supabase → Providers → Google.
5. In Supabase → Authentication → URL Configuration aggiungi `caloscan://auth-callback` (recupero password e conferma email).
6. Configura un SMTP personalizzato (es. Resend, Postmark) per le email di conferma: quello predefinito di Supabase ha limiti molto bassi.

## Fase 4–5 – Backend e AI

7. `supabase login && supabase link --project-ref <ref>` per applicare migrazioni e pubblicare le funzioni.
8. **Chiave del provider AI multimodale** (es. Anthropic) → `supabase secrets set AI_API_KEY=...`. Mai nell'app.
9. **USDA FoodData Central API key** (gratuita su fdc.nal.usda.gov/api-key-signup) → `USDA_FDC_API_KEY`.
   Open Food Facts non richiede chiave.

## Fase 8 – Abbonamenti

10. **App Store Connect**: crea l'app, poi un *Subscription Group* "CaloScan Premium" con i 4 prodotti
    `caloscan.plus.monthly`, `caloscan.plus.yearly`, `caloscan.pro.monthly`, `caloscan.pro.yearly` e imposta i prezzi.
    **Offerta gravidanza**: nello stesso gruppo crea anche `caloscan.plus.monthly.pregnancy` (nome "CaloScan Plus – Gravidanza",
    durata 1 mese, **stesso prezzo** di `caloscan.plus.monthly`, stesso livello di servizio). Nella sua pagina → *Subscription Prices* →
    *Introductory Offers* → **Pay as you go**, durata **3 mesi**, prezzo pari al 70% del normale (es. 3,49 € se Plus costa 4,99 €),
    in tutti i paesi in vendita. Se cambi il prezzo di Plus mensile, aggiorna anche questo prodotto e la sua offerta.
11. Firma il *Paid Applications Agreement* e inserisci dati fiscali e bancari (senza, gli acquisti non funzionano).
12. Crea una chiave **App Store Connect API (In-App Purchase)** → `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`.
13. Imposta l'URL delle **App Store Server Notifications V2** sulla funzione `app-store-notifications`.

## Fase 9–10 – Privacy e pubblicazione

14. Pagine pubbliche per **Informativa privacy** e **Termini di servizio** (URL richiesti da App Store Connect).
    Consigliato un controllo legale: l'app tratta dati relativi alla salute (art. 9 GDPR).
15. Chiave APNs (.p8) per le notifiche push remote: Apple Developer → Keys → nuova chiave con *Apple Push Notifications service*. Serve anche la capability *Push Notifications* sull'App ID (già dichiarata in `project.yml`). I promemoria locali funzionano senza.
16. Icona dell'app 1024×1024, screenshot, descrizione e compilazione delle *App Privacy* in App Store Connect.

Tutti i segreti server sono elencati in `supabase/.env.example`.
