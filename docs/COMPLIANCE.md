# Conformità: normative UE e App Store

Questo documento elenca i requisiti legali e di piattaforma che CaloScan deve rispettare e dove sono implementati.
Va aggiornato a ogni fase. **Non è una consulenza legale**: prima della pubblicazione fai verificare informativa,
termini e valutazione d'impatto da un professionista (DPO o avvocato privacy).

Legenda stato: ✅ implementato · 🟡 parziale (completato nella fase indicata) · ⏳ da fare

## 1. GDPR (Regolamento UE 2016/679)

| Requisito | Dove | Stato |
|---|---|---|
| Base giuridica per dati sanitari: consenso esplicito (art. 9(2)(a)) | Onboarding → passo "I tuoi dati": casella separata, non preselezionata, obbligatoria | ✅ UI · 🟡 registrazione in `consents` (Fase 4) |
| Consenso libero, specifico, separato dai termini (art. 7) | Registrazione: termini e privacy in casella separata; analisi AI foto facoltativa con alternativa manuale | ✅ |
| Revoca del consenso facile quanto la concessione (art. 7(3)) | Profilo → Privacy e account | ✅ UI · 🟡 backend (Fase 4/9) |
| Informativa (art. 13) | Link in Welcome, Registrazione, Onboarding, Paywall, Impostazioni | ✅ link · ⏳ testo dell'informativa (a cura tua) |
| Età minima per il consenso digitale (art. 8) | 16 anni, la soglia più alta nell'UE (`AgePolicy.minimumAccountAge`) | ✅ |
| Minimizzazione (art. 5(1)(c)) | Sesso biologico facoltativo; foto ridimensionate e senza EXIF/GPS; nessun SDK di tracciamento | ✅ |
| Limitazione della conservazione (art. 5(1)(e)) | Foto cancellate dopo `SCAN_IMAGE_RETENTION_DAYS` (default 30) | 🟡 Fase 4/5 |
| Diritto di accesso e portabilità (art. 15, 20) | Privacy e account → Esporta i miei dati (JSON) | ✅ UI · 🟡 `export-data` (Fase 9) |
| Diritto alla cancellazione (art. 17) | Privacy e account → Elimina account e dati | ✅ UI · 🟡 `delete-account` (Fase 9) |
| Sicurezza del trattamento (art. 32) | HTTPS/ATS, token nel Keychain, RLS su ogni tabella, bucket privato, chiavi solo lato server | 🟡 Fase 4 |
| Valutazione d'impatto DPIA (art. 35) | Obbligatoria: trattamento su larga scala di dati sanitari | ⏳ a cura tua, prima del lancio |
| Trasferimenti extra UE (capo V) | Supabase in regione UE; fornitore AI e USDA con clausole contrattuali standard / DPF | ⏳ verificare i DPA dei fornitori |
| Registro dei trattamenti (art. 30) e nomina responsabili (art. 28) | DPA con Supabase, fornitore AI, provider email | ⏳ a cura tua |

## 2. Regolamento UE sull'intelligenza artificiale (AI Act, 2024/1689)

| Requisito | Dove | Stato |
|---|---|---|
| Trasparenza: l'utente sa che interagisce con un'AI (art. 50) | Banner fisso nel Coach; etichette "coach AI" e "stima" su risultati e consigli | ✅ |
| Contenuti generati da AI riconoscibili | Risultati di scansione marcati come stime con grado di affidabilità | ✅ |
| Classificazione del rischio | Uso wellness/informativo, nessuna diagnosi → non ad alto rischio. Da mantenere evitando funzioni mediche | ✅ by design |

## 3. Dispositivi medici (MDR 2017/745)

CaloScan è un'app di benessere: non diagnostica, non tratta e non monitora patologie. Per restare fuori dall'ambito MDR:
- avvertenza "non è un dispositivo medico" in onboarding, profilo e coach ✅
- nessun obiettivo terapeutico; le "esigenze alimentari" sono note libere, non piani clinici ✅
- il coach rifiuta diagnosi e diete terapeutiche (prompt e filtri lato server, Fase 7) 🟡
- soglie di sicurezza: mai sotto 1.200/1.500 kcal né sotto il BMR, nessun deficit per i minori, peso obiettivo non sotto BMI 18,5 ✅

## 4. Consumatori e accessibilità

| Requisito | Dove | Stato |
|---|---|---|
| Direttiva 2011/83/UE e Omnibus: prezzi chiari, rinnovo, recesso | Paywall: prezzo localizzato da StoreKit, periodo, rinnovo automatico, come disdire; il recesso è gestito da Apple | ✅ |
| European Accessibility Act (dal 28/06/2025) | Dynamic Type, etichette VoiceOver, contrasti WCAG AA, target ≥ 44 pt, dark mode, animazioni che rispettano "Riduci movimento", popup annunciati da VoiceOver | ✅ base · ⏳ audit completo (Fase 10) |
| Lingua | Interfaccia in italiano; localizzazioni aggiuntive in `Localizable.xcstrings` | 🟡 Fase 10 |

## 5. App Store Review Guidelines

| Linea guida | Dove | Stato |
|---|---|---|
| 1.4.1 Salute: dati e stime con avvertenze, nessuna affermazione medica | Avvertenze in onboarding, scanner, coach | ✅ |
| 2.1 Completezza: niente funzioni finte | Nessun pulsante decorativo; i servizi non ancora collegati mostrano un errore esplicito | ✅ |
| 3.1.1 Acquisti in-app per contenuti digitali | Solo StoreKit 2, nessun link a pagamenti esterni | 🟡 Fase 8 |
| 3.1.2 Abbonamenti: titolo, durata, prezzo, link a Termini/EULA e Privacy, ripristino acquisti | Paywall | ✅ UI |
| 4.8 Sign in with Apple quando c'è un login di terze parti | Apple mostrato per primo accanto a Google | ✅ |
| 5.1.1(i) Informativa privacy accessibile in app e in App Store Connect | Link in più punti | ✅ |
| 5.1.1(v) Cancellazione dell'account in app | Privacy e account | ✅ UI · 🟡 backend |
| 5.1.2 Nessun uso dei dati sanitari per pubblicità o data mining | Nessun SDK pubblicitario o di analytics di terze parti | ✅ |
| 5.1.3 Salute: dati sanitari non salvati in iCloud | Dati solo su Supabase; nessun uso di iCloud/HealthKit | ✅ |
| Privacy Manifest (`PrivacyInfo.xcprivacy`) | `ios/CaloScan/Resources/` | ✅ |
| Permessi con motivazione (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`) | `project.yml` | ✅ |
| Notifiche: facoltative, non promozionali senza consenso (4.5.4) | Promemoria locali e push disattivati di default; permesso chiesto solo quando l'utente attiva un'opzione; massimo 2 push a settimana | ✅ |
