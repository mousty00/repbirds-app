# RepBirds App

**RepBirds**: app mobile (iOS / Android, gira anche sul web) per allenarsi da soli o in gruppo.
È il client di [repbirds-api](https://github.com/mousty00/repbirds-api) e ne usa le API REST con autenticazione JWT.

![Schermate](docs/screens.png)

## Avvio rapido

```bash
flutter pub get

# backend locale (context-path /api)
flutter run --dart-define=API_BASE_URL=http://localhost:8080/api

# emulatore Android → il localhost della macchina è 10.0.2.2
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api

# produzione
flutter run --release --dart-define=API_BASE_URL=https://<tuo-dominio>/api
```

### Modalità mock (senza backend)

Per provare solo UX e UI in locale, l'app può girare con dati finti in memoria, senza nessuna API:

```bash
flutter run -t lib/main_mock.dart

# equivalente, con il flag
flutter run --dart-define=USE_MOCK=true

# anche nel browser
flutter run -d chrome -t lib/main_mock.dart
```

Da VS Code scegli la configurazione **RepBirds (mock)** in Run and Debug; da Android Studio apri `lib/main_mock.dart` e premi Run. Il flag `--dart-define` vale solo da un avvio completo: un hot reload o hot restart non lo applica.

Se avvii l'app normale e il server non risponde, in debug il login mostra il pulsante **Usa dati demo**, che passa ai dati finti senza riavviare. Nelle build di release questo pulsante non c'è e l'app usa sempre l'API vera.

- Qualunque username e password fanno il login come `mousty`, con amici, schede, storico, gruppi e post già pronti.
- Tutte le azioni funzionano (like, commenti, nuovi post con foto, schede, sessioni, inviti, amicizie) e restano valide finché l'app è aperta. Al riavvio i dati tornano quelli iniziali.
- Per provare i casi di errore: lo username `nonverificato` simula l'email non verificata, la password `sbagliata` simula credenziali errate, il codice OTP `000000` viene sempre rifiutato.
- Il backend finto è in `lib/core/mock/mock_backend.dart`: è un interceptor di dio che risponde alle stesse rotte di gymbro-api, quindi repository e schermate non cambiano.

Requisiti: Flutter 3.38+ (Dart 3.9+). Testato con Flutter 3.47.

> Per il web il backend deve accettare l'origine dell'app in CORS (`app.cors.allowed-origins`, il default `http://localhost:*` va bene per `flutter run -d chrome`).
> Le build debug e profile accettano `http://` verso il backend locale (Android: `usesCleartextTraffic` nei manifest debug/profile; iOS: `NSAllowsLocalNetworking`). La release usa solo `https://`.
> Da un telefono vero `localhost` è il telefono stesso: usa l'IP della macchina, es. `--dart-define=API_BASE_URL=http://192.168.1.20:8080/api`.

### Test end to end contro l'API

`test/e2e/api_e2e_test.dart` usa i repository dell'app contro un gymbro-api vero e prova tutti i flussi: registrazione con OTP, login (anche email non verificata e password errata), refresh del token, utenti e foto profilo, esercizi, schede, storico, amicizie, post con foto, like e commenti, gruppi e inviti, password dimenticata, logout ed eliminazione account.

Serve gymbro-api avviato con un server SMTP di sviluppo che salva le email in un file, perché il test legge da lì gli OTP. Lo storage S3 può essere un S3 compatibile in locale. Poi:

```bash
flutter test test/e2e/api_e2e_test.dart \
  --dart-define=E2E_API=http://localhost:8080/api \
  --dart-define=E2E_MAILS=/percorso/mails.log
```

Senza i due `--dart-define` il test viene saltato, quindi un normale `flutter test` resta veloce e non ha bisogno del backend.

### Corsa

Dalla Home (card **Corsa**) o dal **+**:

- **Percorsi**: disegni il giro toccando la mappa; l'API aggancia i punti a strade e sentieri
  (OpenRouteService, se configurato sul server) e calcola distanza e dislivello. I percorsi restano
  salvati per rifarli. Se lo rendi **pubblico**, i tuoi amici lo vedono nella scheda *Amici* e
  possono salvarne una copia per correrlo da soli.
- **Di gruppo**: da un tuo percorso organizzi una corsa con giorno, ora, punto di ritrovo e amici
  invitati (ricevono la notifica, accettano o rifiutano). Ognuno registra la sua corsa e i tempi
  compaiono nei risultati.
- **Registrazione**: GPS con tempo, distanza, passo attuale e medio, pausa, avviso se esci dal
  tracciato; continua a schermo spento. Ogni corsa e ogni percorso si esportano in GPX.

Le mappe usano [flutter_map](https://pub.dev/packages/flutter_map) con le tile di OpenStreetMap,
configurabili con `--dart-define=MAP_TILE_URL=...` e `MAP_ATTRIBUTION` (in produzione serve un
provider con chiave, vedi `DEPLOY.md`). In modalità mock la corsa è simulata lungo il percorso a
5'30"/km, così il flusso si prova anche sul simulatore o nel browser.

### Notifiche push

Niente plugin Firebase: il codice nativo passa a Dart il token del dispositivo
(canale `repbirds/push`, vedi `lib/core/push/push_service.dart`), che dopo il login
lo registra su `POST /devices` e al logout lo cancella.

- **iOS:** APNs direttamente, senza Firebase (`ios/Runner/AppDelegate.swift`). Serve
  la capability Push Notifications sull'App ID (l'entitlement è già in
  `ios/Runner/Runner.entitlements`); la chiave APNs (.p8) va solo sull'API.
- **Android:** FCM, l'unico canale per le push ad app chiusa sui telefoni con Play
  Store. Scarica `google-services.json` dal progetto Firebase (solo l'app Android)
  in `android/app/`. Senza quel file l'app si compila uguale e non riceve push.

In ogni caso le notifiche restano visibili nella schermata Notifiche.

Con l'app aperta le notifiche arrivano anche in tempo reale da `GET /notifications/stream`
(Server-Sent Events, `lib/data/notification_stream.dart`): il numero sulla campanella segue
le non lette e la lista si ricarica a ogni nuova notifica. In background lo stream si chiude
(lì ci sono le push) e si riapre al ritorno. Nella schermata Notifiche una riga si cancella
scorrendola verso sinistra, e il cestino in alto le cancella tutte.

## Funzionalità

| Area | Cosa fa | Endpoint |
|---|---|---|
| Accesso | Login, registrazione, verifica email con OTP, reinvio codice, reset password, logout, refresh automatico del token | `/auth/*` |
| Home | Saluto, attività della settimana, statistiche, schede di oggi, prossimi allenamenti di gruppo, post degli amici | vari |
| Community | Feed amici / esplora, like, commenti, nuovo post con foto, modifica ed eliminazione | `/posts`, `/likes`, `/comments`, `/friendship/posts` |
| Allenamenti | Le mie schede, schede pubbliche, crea / modifica / elimina, giorni e orario, esercizi con serie, ripetizioni, peso e recupero | `/workouts`, `/workout-exercises` |
| Sessione live | Cronometro, serie da spuntare, timer di recupero, note, salvataggio nello storico (anche di gruppo) | `/workout-history` |
| Esercizi | Libreria con ricerca e filtro per gruppo muscolare, esercizi personalizzati pubblici o privati | `/exercises` |
| Gruppi | Crea un allenamento di gruppo, invita amici, accetta / rifiuta inviti, esci, rimuovi membri, storico del gruppo | `/workout_groups`, `/group_members` |
| Amici | Cerca utenti, invia / accetta / rifiuta richieste, blocca, profilo pubblico con i post | `/users/search`, `/friendship/*` |
| Profilo | Foto profilo (upload S3), statistiche, storico, i miei post, eliminazione account | `/users/*`, `/auth/profile` |

## Struttura

```
lib/
  core/        config (base URL), client HTTP dio + refresh token, storage sicuro, tema, router, widget comuni
  models/      modelli che rispecchiano i DTO del backend (parsing manuale, niente code generation)
  data/        repository per dominio + provider Riverpod condivisi
  features/    una cartella per area: auth, home, feed, workouts, exercises, groups, friends, profile, shell
```

- **Stato**: Riverpod 3 (`FutureProvider` per le letture, `AsyncNotifier` per la sessione).
- **Navigazione**: go_router con `StatefulShellRoute` per le 5 tab e redirect in base alla sessione.
- **Rete**: dio; ogni richiesta porta `Authorization: Bearer …`, su 401 l'app chiama `/auth/refresh` una sola volta e ripete la richiesta; se fallisce torna al login.
- **Token**: `flutter_secure_storage` (Keychain / Keystore).
- **UI**: tema chiaro, gradienti azzurro / lilla, card arrotondate, barra di navigazione flottante a pillola, font Plus Jakarta Sans.

## Note sul backend

- `POST /posts/create` richiede sempre un'immagine (`imageFile` è obbligatorio), quindi l'app chiede una foto per ogni post.
- Le richieste di amicizia inviate non hanno un endpoint di lettura: l'app mostra solo quelle ricevute.
- Chi è solo invitato non può leggere il gruppo: l'invito porta con sé nome, creatore e data (`groupName`, `groupCreatedBy`, `groupScheduledFor`, da gymbro-api PR #14). Con un backend più vecchio l'app mostra un testo generico.
- Un commento lo può eliminare solo chi l'ha scritto, anche sui propri post.
- Le rotte `/auth/**` hanno un rate limit di 20 richieste al minuto per IP: l'app mostra "Troppi tentativi" invece dell'errore 429.
