# Moduli funzionali

Ogni cartella contiene `View` + `ViewModel` (+ eventuali sotto-componenti) di un'area. Mappa schermate → modulo → fase:

| # | Schermata | Modulo | Fase |
|---|---|---|---|
| 1 | Splash | App (launch screen + RootView) | 2 |
| 2–4 | Welcome, Registrazione, Login (+ recupero password) | Auth | 2–3 |
| 5–7 | Onboarding, Dati fisici, Obiettivi | Onboarding | 2–3 |
| 8, 24 | Scelta piano, Paywall Plus/Pro | Subscription | 2, 8 |
| 9 | Home Dashboard | Home | 2, 6 |
| 10–13 | Fotocamera, Risultato, Modifica alimento, Ricerca manuale | Scanner | 2, 5 |
| 14–18 | Diario, Calendario, Statistiche giorno/settimana/mese | Diary | 2, 6 |
| 19 | AI Nutrition Coach | Coach | 2, 7 |
| 20 | Monitoraggio peso e misure | Progress | 2, 6 |
| 21 | Profilo | Profile | 2 |
| 22, 25 | Impostazioni, Privacy e gestione account | Settings | 2, 9 |
| 23 | Gestione abbonamento | Subscription | 8 |

Regole: le View non fanno rete; i ViewModel sono `@Observable @MainActor` e dipendono solo dai protocolli in `Core/Services`; ogni schermata gestisce caricamento, vuoto ed errore.
