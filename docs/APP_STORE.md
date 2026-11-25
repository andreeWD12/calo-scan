# Pubblicazione su App Store

Tutto quello che serve in App Store Connect, pronto da copiare. I passaggi in ordine sono in `docs/SETUP.md` (Fase 10).
Limiti di lunghezza di Apple indicati tra parentesi; i testi qui sotto li rispettano.

## 1. Informazioni dell'app

| Campo | Valore |
|---|---|
| Nome (30) | `CaloScan` · se Apple dice che è già usato: `CaloScan: calorie con AI` |
| Sottotitolo (30) | `Calorie e macro da una foto` |
| Lingua principale | Italiano |
| Bundle ID | `com.andrewnalini.caloscan.app` |
| SKU | `caloscan-ios` (solo per te, non si vede) |
| Categoria principale | Salute e fitness |
| Categoria secondaria | Cibo e bevande |
| Prezzo | Gratis (con acquisti in-app) |
| Disponibilità | Italia (l'app è solo in italiano). Si possono aggiungere altri paesi dopo |
| URL privacy | `https://andreewd12.github.io/calo-scan/privacy/` |
| URL assistenza | `https://andreewd12.github.io/calo-scan/support/` |
| URL marketing | (vuoto) |
| Copyright | `2026 Andrew Nalini` |

### Testo promozionale (170, si può cambiare senza nuova revisione)

```
Fotografa il piatto e scopri calorie e macro in pochi secondi. Diario, progressi e un coach AI che conosce i tuoi obiettivi.
```

### Parole chiave (100, separate da virgola, senza spazi)

```
calorie,contacalorie,dieta,macro,proteine,nutrizione,peso,diario alimentare,dimagrire,scanner cibo
```

### Descrizione (4000)

```
CaloScan ti aiuta a sapere cosa mangi, senza fatica.

FOTOGRAFA IL PIATTO
Scatta una foto o descrivi il pasto a parole: l'intelligenza artificiale riconosce gli alimenti e stima le quantità, poi calorie e macronutrienti arrivano dai database USDA FoodData Central e Open Food Facts. Puoi sempre correggere grammi e alimenti prima di salvare.

CERCA, SCANSIONA, REGISTRA
Cerca tra migliaia di alimenti e prodotti italiani, leggi il codice a barre delle confezioni o inserisci un alimento a mano. Gratis per tutti.

OBIETTIVI SU MISURA
Calcoliamo il tuo fabbisogno con la formula di Mifflin-St Jeor e il tuo livello di attività, con limiti di sicurezza: mai sotto il metabolismo basale, niente deficit per i minorenni. Se segui un piano del medico o del dietista, puoi inserirlo e diventa il tuo obiettivo.

DIARIO E PROGRESSI
Giorno, settimana e mese a colpo d'occhio: calorie, proteine, carboidrati e grassi, andamento del peso, misure corporee e i giorni di fila in cui hai registrato i pasti.

COACH AI
Chiedi come organizzare una cena fuori o cosa mangiare a colazione: il coach risponde tenendo conto dei tuoi obiettivi e di quello che hai già mangiato oggi.

ANCHE IN GRAVIDANZA
Una modalità dedicata con i valori di riferimento EFSA per trimestre, gli alimenti da evitare secondo il Ministero della Salute e mai un deficit calorico.

PIANI
• Free: diario, ricerca, codice a barre, inserimento manuale, peso, lista della spesa e consigli del giorno.
• Plus: scanner AI (4 analisi al giorno), coach AI (30 messaggi al giorno), statistiche avanzate, misure corporee, piano del professionista, lista della spesa con suggerimenti AI.
• Pro: tutto Plus con 15 analisi e 150 messaggi al giorno, stili alimentari con il coach e dieta completa in gravidanza.

Abbonamenti mensili o annuali con rinnovo automatico, disdicibili in qualsiasi momento dalle impostazioni dell'Apple ID almeno 24 ore prima del rinnovo.

LA TUA PRIVACY
Le foto non vengono mai salvate sui nostri server. I dati sono in Europa, non li vendiamo e non usiamo pubblicità. Puoi esportarli o cancellare l'account dall'app quando vuoi.

CaloScan è un'app di benessere e non è un dispositivo medico: le stime possono contenere errori e non sostituiscono il parere del medico o del dietista.

Termini di servizio: https://andreewd12.github.io/calo-scan/terms/
Privacy: https://andreewd12.github.io/calo-scan/privacy/
```

### Novità di questa versione (solo dalla 1.0.1 in poi)

```
Correzioni e miglioramenti.
```

## 2. Screenshot

Servono quelli per iPhone 6,9" (1320 × 2868). Apple li riduce da sola per gli altri iPhone.
La build automatica li crea a ogni aggiornamento della PR: GitHub › **Actions** › l'ultima esecuzione "Build iOS" ›
in fondo alla pagina **Artifacts** › `app-store-screenshots` (file zip). Sono 5: Home, scansione, Diario, Progressi, Coach.
Trascinali in ordine in App Store Connect › la versione 1.0 › *iPhone 6,9"*.

Sono schermate reali dell'app con dati d'esempio (piano Pro), come chiede la linea guida 2.3.3.

## 3. Abbonamenti (nomi e descrizioni per App Store Connect)

Gruppo: **CaloScan Premium** (nome mostrato: `CaloScan Premium`).

| Product ID | Nome visualizzato (35) | Descrizione (55) |
|---|---|---|
| `caloscan.plus.monthly` | CaloScan Plus mensile | Scanner AI, coach AI e statistiche avanzate |
| `caloscan.plus.yearly` | CaloScan Plus annuale | Scanner AI, coach AI e statistiche avanzate |
| `caloscan.pro.monthly` | CaloScan Pro mensile | Più analisi AI, stili alimentari e gravidanza |
| `caloscan.pro.yearly` | CaloScan Pro annuale | Più analisi AI, stili alimentari e gravidanza |
| `caloscan.pro.monthly.pregnancy` | CaloScan Pro gravidanza | CaloScan Pro con sconto per i primi 3 mesi |

Per ognuno: *Review Information* › uno screenshot del paywall (va bene lo screenshot preso con lo schema "CaloScan StoreKit locale")
e la nota `Si acquista da Profilo › Abbonamento oppure toccando una funzione con il lucchetto.`

**Importante**: alla prima pubblicazione gli abbonamenti si inviano **insieme alla versione dell'app**. Nella pagina della versione 1.0,
sezione *In-App Purchases and Subscriptions*, premi **+** e seleziona tutti e 5. Se lo dimentichi Apple li rifiuta come "non inviati".

## 4. Classificazione per età

App Store Connect › *App Information* › *Age Rating* › *Edit*. Risposte:

| Domanda | Risposta |
|---|---|
| Violenza, contenuti sessuali, linguaggio volgare, horror, droghe, alcol e tabacco, gioco d'azzardo, armi | Nessuno |
| Informazioni mediche o terapeutiche | Rare/lievi (informazioni generali di benessere, nessuna diagnosi) |
| Temi di salute e benessere | Sì |
| Contenuti generati dagli utenti / comunicazione tra utenti | No (gli utenti non si vedono tra loro) |
| Chatbot o contenuti generati dall'AI (se la domanda c'è) | Sì: coach AI con filtri di sicurezza |
| Accesso web senza restrizioni | No |
| Pubblicità | No |
| Controlli parentali / verifica dell'età | Nessuno (l'età si chiede nell'onboarding, minimo 16 anni) |

Se il risultato è più basso di **16+**, imposta l'età minima a **16+** con l'opzione per scegliere una classificazione più alta:
l'app chiede almeno 16 anni per il consenso ai dati sanitari (GDPR art. 8).

## 5. App Privacy (etichetta "privacy nutrition")

App Store Connect › *App Privacy* › *Get Started*. **Raccogli dati?** Sì. Per **ogni** tipo qui sotto:
*Collegato all'identità* = **Sì**, *Usato per il tracciamento* = **No**, *Scopo* = solo **Funzionalità dell'app**.
È lo stesso elenco del file `ios/CaloScan/Resources/PrivacyInfo.xcprivacy`: se uno cambia, cambia anche l'altro.

| Categoria Apple | Tipo | Cosa è in CaloScan |
|---|---|---|
| Informazioni di contatto | Nome | Nome visualizzato |
| Informazioni di contatto | Indirizzo email | Account |
| Salute e fitness | Salute | Pasti, peso, misure, piano del professionista, allergie |
| Salute e fitness | Fitness | Livello di attività |
| Informazioni sensibili | Informazioni sensibili | Gravidanza (Apple la classifica così) |
| Contenuti utente | Foto o video | Foto dei piatti inviate all'analisi AI (mai salvate) |
| Contenuti utente | Altri contenuti dell'utente | Messaggi al coach, descrizioni dei piatti |
| Identificatori | ID utente | ID dell'account |
| Acquisti | Cronologia acquisti | Abbonamenti |
| Utilizzo | Interazione con il prodotto | Conteggio di scansioni e messaggi per i limiti del piano |

Non raccolti: posizione, contatti, cronologia di navigazione, dati di diagnostica, identificatori del dispositivo, dati finanziari.

## 6. Altre domande di App Store Connect

| Domanda | Risposta |
|---|---|
| Crittografia (export compliance) | Già risposto nel file Info.plist (`ITSAppUsesNonExemptEncryption = NO`): solo HTTPS standard |
| Diritti sui contenuti: l'app usa contenuti di terzi? | Sì, e hai i diritti: USDA FoodData Central (dominio pubblico) e Open Food Facts (licenza ODbL, citata in app) |
| Pubblicità / IDFA | No |
| Accesso con terze parti | Google e Apple (Accedi con Apple presente, linea guida 4.8) |
| **Stato di trader (Digital Services Act UE)** | *Business* › *Compliance* (o al primo invio): vendi abbonamenti, quindi sei **trader**. Apple mostrerà nell'UE indirizzo, telefono ed email che inserisci. Serve per distribuire in Italia |

## 7. Informazioni per la revisione (App Review)

*Sign-in required*: **Sì**. Crea un account apposta (vedi SETUP passo 27) e scrivi qui email e password.

Note (copia e incolla, sostituendo l'email):

```
CaloScan is a nutrition and calorie tracking app (wellness, not a medical device). The UI is in Italian.

DEMO ACCOUNT
Email: <EMAIL DELL'ACCOUNT DI REVISIONE>  Password: see the Sign-In fields.
On the welcome screen tap "Hai già un account? Accedi" and sign in with email and password. The profile is already set up, so the app opens on the Home screen.
The account is on the Free plan, so you can test the subscription purchase with your sandbox Apple ID.

WHERE TO FIND THINGS
- AI photo scanner (Plus/Pro): central camera button in the tab bar. "Descrivi a parole" lets you describe a meal in text instead of taking a photo.
- Free features: food search, barcode, manual entry (magnifying glass in the scanner), Diary, Progress.
- AI coach (Plus/Pro): sparkles icon at the top of Home.
- Subscriptions: Profilo > Abbonamento, or tap any feature with a lock. Restore purchases and "Riscatta un codice" are on the paywall.
- Account deletion (5.1.1(v)): Profilo > Privacy e account > Elimina account e dati. Data export is on the same screen.
- Health sources and method (1.4.1): Profilo > Impostazioni > Fonti scientifiche e metodo.
- The AI coach is also reachable from Profilo > AI Nutrition Coach.

AI AND SAFETY
Photos are sent to our AI provider only to recognise foods and estimate portions; they are never stored on our servers. Nutrition values come from USDA FoodData Central and Open Food Facts. All AI output is labelled as an estimate and can be edited. Calorie targets never go below BMR or 1,200/1,500 kcal, there is no deficit for minors, and the coach answers questions about eating disorders or self-harm with fixed messages pointing to Italian helplines instead of AI-generated content.

SUBSCRIPTIONS
Auto-renewable subscriptions in one group: Plus and Pro, monthly and yearly, plus a Pro monthly variant with a 3-month introductory offer that is shown only to users who said they are pregnant. Purchases are verified server-side with the App Store Server API.

Minimum age for an account is 16 (GDPR consent for health data).
```

Recapito: nome, cognome, telefono, email (non vengono mostrati agli utenti).

## 8. Prima di premere "Invia per la revisione"

- [ ] TestFlight: provata la build sul tuo iPhone con la lista del § 9
- [ ] Indirizzo del titolare inserito in `privacy/index.html` e `terms/index.html` e pagine online
- [ ] `TESTER_USER_IDS` rimosso da Supabase
- [ ] Supabase **Pro** attivo
- [ ] I 5 abbonamenti "Ready to Submit" e aggiunti alla versione 1.0
- [ ] Paid Applications Agreement attivo, dati fiscali e bancari, stato di trader
- [ ] Account di revisione creato, onboarding completato, email e password in App Review Information
- [ ] Screenshot caricati, descrizione, parole chiave, URL privacy e assistenza
- [ ] App Privacy compilata come nel § 5, classificazione per età 16+

## 9. Prova finale su TestFlight (lista per te)

Fai le prove con la build scaricata da TestFlight, non da Xcode: è identica a quella che riceveranno gli utenti.
In TestFlight gli acquisti sono gratuiti (sandbox) e un mese dura pochi minuti.

1. Registrazione con email: arriva la mail di conferma, il link riapre l'app.
2. Accedi con Apple e con Google, esci, rientra.
3. Onboarding completo fino alla Home; obiettivo calorico visibile.
4. Free: cerca "mela", leggi un codice a barre di una confezione, aggiungi un alimento a mano. Lo scanner AI mostra il lucchetto.
5. Compra **Plus mensile** dal paywall: il piano cambia subito, Profilo › Abbonamento mostra la scadenza.
6. Scanner: foto di un piatto vero → risultato → correggi i grammi → salva. Poi "Descrivi a parole".
7. Coach: fai una domanda; prova anche "Cancella conversazione".
8. Diario: cambia giorno, modifica un alimento, togli un alimento. Progressi: aggiungi un peso.
9. Passa a **Pro** (dal paywall): eventuali stili alimentari e gravidanza si sbloccano.
10. Impostazioni: attiva un promemoria (arriva la richiesta di permesso), apri "Fonti scientifiche e metodo", "Assistenza" › Scrivici.
11. Privacy e account: Esporta i miei dati (si apre il foglio di condivisione con il file).
12. Invita un amico: il codice si copia e si condivide.
13. Riavvia l'iPhone senza internet: l'app si apre e dice chiaramente che manca la connessione.
14. Testo grande (Impostazioni iOS › Schermo › Dimensioni testo al massimo) e modalità scura: niente testo tagliato nelle schermate principali.
15. **Per ultimo**, con un account di prova: Elimina account e dati. L'app torna alla schermata iniziale e l'account non esiste più.

Se qualcosa non va, scrivi in questo progetto cosa hai fatto e cosa hai visto (uno screenshot aiuta).
