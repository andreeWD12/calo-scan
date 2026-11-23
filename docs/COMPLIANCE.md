# Conformità: normative UE e App Store

Questo documento elenca i requisiti legali e di piattaforma che CaloScan deve rispettare e dove sono implementati.
Va aggiornato a ogni fase. **Non è una consulenza legale**: prima della pubblicazione fai verificare informativa,
termini e valutazione d'impatto da un professionista (DPO o avvocato privacy).

Legenda stato: ✅ implementato · 🟡 parziale (completato nella fase indicata) · ⏳ da fare

## 1. GDPR (Regolamento UE 2016/679)

| Requisito | Dove | Stato |
|---|---|---|
| Base giuridica per dati sanitari: consenso esplicito (art. 9(2)(a)) | Onboarding → passo "I tuoi dati": casella separata, non preselezionata, obbligatoria | ✅ UI · ✅ registrazione in `consents` con storico `consent_events` |
| Consenso libero, specifico, separato dai termini (art. 7) | Registrazione: termini e privacy in casella separata; analisi AI foto facoltativa con alternativa manuale | ✅ |
| Revoca del consenso facile quanto la concessione (art. 7(3)) | Profilo → Privacy e account | ✅ UI · 🟡 backend (Fase 4/9) |
| Informativa (art. 13) | Link in Welcome, Registrazione, Onboarding, Paywall, Impostazioni | ✅ link · ⏳ testo dell'informativa (a cura tua) |
| Età minima per il consenso digitale (art. 8) | 16 anni, la soglia più alta nell'UE (`AgePolicy.minimumAccountAge`) | ✅ |
| Piano del medico/dietista e descrizioni dei pasti: dati sanitari | Coperti dal consenso art. 9 dell'onboarding; inclusi in esportazione e cancellazione; nome del professionista facoltativo; nessun documento o ricetta caricato | ✅ UI · ✅ tabella `professional_plans`, scritta solo da `save-professional-plan` dopo la rivalidazione |
| Lista della spesa AI | Richiesta facoltativa dell'utente e dati necessari inviati solo dal server; allergeni esclusi due volte (prompt + filtro `filterSuggestions`); avviso di controllare le etichette | ✅ UI · 🟡 `shopping-suggest` (Fase 7) |
| Descrizione testuale inviata al fornitore AI | Informativa nel foglio "Descrivi il piatto"; nessun addestramento; disponibile anche senza consenso alle foto, perché non invia immagini | ✅ UI · ✅ `analyze-food` controlla il consenso sanitario; il testo non viene salvato |
| Minimizzazione (art. 5(1)(c)) | Sesso biologico facoltativo; foto ridimensionate e senza EXIF/GPS; nessun SDK di tracciamento | ✅ |
| Limitazione della conservazione (art. 5(1)(e)) | Foto mai salvate sui server: inviate al fornitore AI solo per l'analisi; miniatura solo sul telefono, esclusa dal backup, cancellata con il pasto e all'uscita | ✅ |
| Diritto di accesso e portabilità (art. 15, 20) | Privacy e account → Esporta i miei dati (JSON) | ✅ UI · 🟡 `export-data` (Fase 9) |
| Diritto alla cancellazione (art. 17) | Privacy e account → Elimina account e dati | ✅ UI · 🟡 `delete-account` (Fase 9) |
| Sicurezza del trattamento (art. 32) | HTTPS/ATS, token nel Keychain, RLS su ogni tabella, permessi minimi per ruolo, vincoli di validità nel database, chiavi solo lato server | ✅ database · ✅ nessun archivio di foto |
| Valutazione d'impatto DPIA (art. 35) | Obbligatoria: trattamento su larga scala di dati sanitari | ⏳ a cura tua, prima del lancio |
| Trasferimenti extra UE (capo V) | Supabase in regione UE; fornitore AI e USDA con clausole contrattuali standard / DPF | ⏳ verificare i DPA dei fornitori |
| Registro dei trattamenti (art. 30) e nomina responsabili (art. 28) | DPA con Supabase, fornitore AI, provider email | ⏳ a cura tua |

## 2. Regolamento UE sull'intelligenza artificiale (AI Act, 2024/1689)

| Requisito | Dove | Stato |
|---|---|---|
| Trasparenza: l'utente sa che interagisce con un'AI (art. 50) | Banner fisso nel Coach; etichette "coach AI" e "stima" su risultati e consigli | ✅ |
| Contenuti generati da AI riconoscibili | Risultati di scansione marcati come stime con grado di affidabilità | ✅ |
| Fonti dei valori nutrizionali | USDA FoodData Central (pubblico dominio) e Open Food Facts (ODbL), indicati sotto i risultati di ricerca | ✅ |
| Classificazione del rischio | Uso wellness/informativo, nessuna diagnosi → non ad alto rischio. Da mantenere evitando funzioni mediche | ✅ by design |

## 3. Dispositivi medici (MDR 2017/745)

CaloScan è un'app di benessere: non diagnostica, non tratta e non monitora patologie. Per restare fuori dall'ambito MDR:
- avvertenza "non è un dispositivo medico" in onboarding, profilo e coach ✅
- nessun obiettivo terapeutico generato dall'app; le "esigenze alimentari" sono note libere, non piani clinici ✅
- piano indicato da un professionista: l'app **registra e mostra** i valori inseriti dall'utente (funzione di archivio e visualizzazione, esclusa dall'MDR secondo le linee guida MDCG 2019-11); non li calcola, non li corregge, non dà indicazioni cliniche. Conferma esplicita che i valori vengono da un professionista e avviso sotto le soglie dell'app ✅
- pasti e grammature del piano: copiati dall'utente, mai generati o adattati dall'app; la registrazione "come da piano" salva le quantità realmente mangiate ✅
- sgarri: etichetta facoltativa scelta dall'utente, linguaggio neutro e nessun invito a compensare (prevenzione dei disturbi alimentari, coerente con le avvertenze del coach) ✅
- il coach rifiuta diagnosi e diete terapeutiche (prompt e filtri lato server, Fase 7) 🟡
- soglie di sicurezza: mai sotto 1.200/1.500 kcal né sotto il BMR, nessun deficit per i minori, peso obiettivo non sotto BMI 18,5 ✅

## 4. Consumatori e accessibilità

| Requisito | Dove | Stato |
|---|---|---|
| Pratiche commerciali (dir. 2005/29/CE) e dark pattern (DSA art. 25) negli inviti all'upgrade | Inviti legati a un limite reale o a un momento d'uso, nessuna urgenza finta o conto alla rovescia, chiusura sempre visibile, l'app resta usabile, massimo 2 a settimana, stop dopo 3 chiusure; nessun profilo inviato al server | ✅ |
| Direttiva 2011/83/UE e Omnibus: prezzi chiari, rinnovo, recesso | Paywall: prezzo localizzato da StoreKit, periodo, rinnovo automatico, come disdire; il recesso è gestito da Apple | ✅ |
| European Accessibility Act (dal 28/06/2025) | Dynamic Type, etichette VoiceOver, contrasti WCAG AA, target ≥ 44 pt, dark mode, animazioni che rispettano "Riduci movimento", popup annunciati da VoiceOver | ✅ base · ⏳ audit completo (Fase 10) |
| Lingua | Interfaccia in italiano; localizzazioni aggiuntive in `Localizable.xcstrings` | 🟡 Fase 10 |

## 5. App Store Review Guidelines

| Linea guida | Dove | Stato |
|---|---|---|
| 1.4.1 Salute: dati e stime con avvertenze, nessuna affermazione medica | Avvertenze in onboarding, scanner, coach | ✅ |
| 2.1 Completezza: niente funzioni finte | Nessun pulsante decorativo; i servizi non ancora collegati mostrano un errore esplicito | ✅ |
| 3.1.1 Acquisti in-app per contenuti digitali | Solo StoreKit 2, nessun link a pagamenti esterni | 🟡 Fase 8 |
| 3.1.1 Codici promozionali | Nessun codice gestito dall'app: solo codici offerta di Apple creati in App Store Connect, riscattati con il foglio di sistema ("Riscatta un codice" in paywall e Abbonamento) | 🟡 Fase 8 |
| MDR (Reg. UE 2017/745) – stile alimentare | Catalogo chiuso di stili di benessere, nessuna dieta terapeutica, nessuna diagnosi; esclusi gli stili restrittivi con condizioni a rischio; il piano del professionista ha sempre la priorità | ✅ Fase 2 (app) / 🟡 Fase 7 (server) |
| Reg. UE 1924/2006 – indicazioni sulla salute | Descrizioni neutre; il server sostituisce le motivazioni del modello con claim vietati ("brucia grassi", "detox", "previene", "cura"…) | 🟡 Fase 7 |
| GDPR art. 9 – domande di sicurezza | Basate sul consenso ai dati sanitari già raccolto; risposte usate solo per la richiesta e non salvate; lo stile scelto è salvato come dato sanitario | ✅ Fase 2 (app) |
| AI Act art. 50 – stile alimentare | Avviso che le proposte sono generate da un'AI e non sostituiscono il medico | ✅ Fase 2 |
| App Store 1.4.1 – app per la salute | Nessuna promessa di risultati; avvertenze su sintomi (stanchezza, capogiri) e invito a interrompere e sentire il medico; digiuno escluso per minorenni | ✅ Fase 2 |
| MDR – modalità gravidanza | Solo indicazioni pubbliche di sicurezza alimentare (Ministero della Salute, ISS, EFSA) e valori di riferimento EFSA; nessuna diagnosi, nessun integratore o dosaggio; rinvio a ginecologo/ostetrica; nessun deficit calorico | ✅ Fase 2 (app) |
| GDPR art. 9 – gravidanza | Dato sanitario facoltativo, con il consenso ai dati sanitari; modificabile e cancellabile da Profilo › Gravidanza; incluso nell'export e cancellato con l'account | ✅ Fase 2 (app) / ✅ Fase 3–4 (DB, nel profilo) |
| Gravidanza – tutele non a pagamento | Mai deficit calorico, niente digiuni o stili restrittivi ed elenco degli alimenti da evitare valgono anche con Free; i suggerimenti AI escludono sempre gli alimenti da evitare; con Pro la dieta completa (settimana, avvisi automatici) | ✅ Fase 2 |
| GDPR art. 7(1) – prova del consenso | Consensi in `consents`, ogni modifica registrata da trigger in `consent_events` (consenso, valore, data); leggibili solo dal titolare | ✅ Fase 3 |
| GDPR art. 25/32 – accesso ai dati | RLS su tutte le tabelle: ogni utente vede solo le proprie righe; profilo e obiettivi scritti solo dalla funzione `save-profile` dopo la rivalidazione; nessun accesso al ruolo anonimo; service_role solo nelle Edge Functions | ✅ Fase 3 |
| GDPR art. 17 / App Store 5.1.1(v) – eliminazione account | Funzione `delete-account` (cancellazione a cascata di tutti i dati). Da completare: revoca del token Apple (*Sign in with Apple REST API*) e cancellazione delle foto dallo storage | ✅ Fase 3 / 🟡 Fase 9 |
| GDPR art. 8 – età minima | 16 anni, verificati in onboarding e di nuovo dal server (`save-profile`) | ✅ Fase 3 |
| App Store 1.5 – assistenza | Impostazioni › Assistenza: domande frequenti, "Scrivici" (email precompilata con sola versione app, versione iOS e modello, nessun dato sanitario), pagina web di supporto; stesso URL in App Store Connect | ✅ app / 🟡 pagina web Fase 9 |
| GDPR art. 9 – offerta gravidanza | Il dato serve a mostrare l'offerta solo dentro l'app, con il consenso ai dati sanitari già raccolto; non va ad Apple (il prodotto è scelto in app), né a terzi, né per marketing o email. Da indicare nell'informativa privacy (finalità: personalizzazione dell'offerta in app) | ✅ app / 🟡 informativa Fase 9 |
| Codice del Consumo art. 17-bis (Omnibus) – sconto 30% | Lo sconto è calcolato sul prezzo normale di Pro mensile, invariato negli ultimi 30 giorni; la card mostra prezzo scontato, prezzo normale, durata (3 mesi) e prezzo dopo. Non alzare il prezzo di Pro subito prima di lanciare l'offerta | ✅ app / ⚠️ regola per i prezzi |
| App Store 3.1.2 – offerta gravidanza | Prezzo e durata da StoreKit, rinnovo automatico e disdetta scritti accanto al pulsante, "Continua con il piano Free" sempre visibile; nessun linguaggio di pressione o timer | ✅ Fase 8 |
| App Store 1.4.1 – gravidanza | Avvisi informativi con fonti, limiti del riconoscimento dichiarati ("controlla l'etichetta"), nessuna promessa sulla salute | ✅ Fase 2 |
| 3.1.1 / 3.2.2 Premi per gli inviti | Il premio è solo un codice offerta Apple (sconto sul primo mese), mai uno sblocco gestito dall'app; nessun obbligo di invitare per usare funzioni; nessun premio per recensioni o download di altre app | 🟡 Fase 8 |
| GDPR art. 5(1)(c) Minimizzazione negli inviti | Niente accesso ai contatti; il referrer vede solo conteggi; righe cancellate con l'account; DeviceCheck senza identificatori | 🟡 Fase 4 |
| Codice del Consumo artt. 20-23 – limiti delle scansioni | Numeri dichiarati ovunque (Plus 4, Pro 15 al giorno; Free senza scanner AI): paywall, guida, FAQ e sito. Mai la parola "illimitate" | ✅ app / 🟡 Termini Fase 9 |
| Codice del Consumo (pratiche commerciali) | Regolamento dell'invito chiaro in app e nei Termini: premio unico non accumulabile, solo primo mese, scadenza, rinnovo a prezzo pieno; trasparenza sul prezzo dopo lo sconto | 🟡 Fase 8 |
| 3.1.2 Abbonamenti: titolo, durata, prezzo, link a Termini/EULA e Privacy, ripristino acquisti | Paywall | ✅ UI |
| 4.8 Sign in with Apple quando c'è un login di terze parti | Apple mostrato per primo accanto a Google | ✅ |
| 5.1.1(i) Informativa privacy accessibile in app e in App Store Connect | Link in più punti | ✅ |
| 5.1.1(v) Cancellazione dell'account in app | Privacy e account | ✅ UI · 🟡 backend |
| 5.1.2 Nessun uso dei dati sanitari per pubblicità o data mining | Nessun SDK pubblicitario o di analytics di terze parti | ✅ |
| 5.1.3 Salute: dati sanitari non salvati in iCloud | Dati solo su Supabase; nessun uso di iCloud/HealthKit | ✅ |
| Privacy Manifest (`PrivacyInfo.xcprivacy`) | `ios/CaloScan/Resources/` | ✅ |
| Permessi con motivazione (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`) | `project.yml` | ✅ |
| Notifiche: facoltative, non promozionali senza consenso (4.5.4) | Promemoria locali e push disattivati di default; permesso chiesto solo quando l'utente attiva un'opzione; massimo 2 push a settimana | ✅ |
