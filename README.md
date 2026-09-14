# Rubbish Manager

App Flutter (Android + iOS) per gestire la casa: **smaltimento dei rifiuti** e
**manutenzioni periodiche**, condivisi con chi ci abita.

Interfaccia in italiano, codice in inglese.

---

## Cosa fa

Ogni abitazione contiene due aree, scelte da una pagina iniziale.

### Gestione rifiuti

- **Abitazioni**: crei un'abitazione e le associ i tipi di rifiuto da monitorare
  (Indifferenziato, Carta, Plastica, Umido, Verde leggero, Vetro — solo quelli
  che ti servono).
- **Ritiri gratuiti**: per ogni tipo scegli se hai un numero limitato di ritiri
  gratuiti all'anno, se sono illimitati o se sono tutti a pagamento.
- **Calendario**: per ogni tipo imposti i giorni della settimana e la frequenza
  (ogni settimana, ogni 2 settimane = "ogni 15 giorni", ogni 3 o 4 settimane).
- **Promemoria**: la sera prima di ogni ritiro arriva una notifica che dice cosa
  viene ritirato l'indomani e quanti ritiri gratuiti restano. La notifica ha due
  pulsanti, **Raccolta fatta** e **Salta**, che registrano l'esito senza aprire
  l'app.
- **Conteggio**: si incrementa dal pulsante in app o confermando la notifica.
- **Salta**: se quel giorno non porti fuori nulla, marchi il ritiro come
  saltato. Non consuma un ritiro gratuito, non compare nelle statistiche e
  zittisce il promemoria — ma resta nello storico ed è annullabile.
- **Storico**: tutte le raccolte degli ultimi 5 anni, modificabili ed
  eliminabili; i contatori si ricalcolano da soli.
- **Statistiche**: andamento mensile dell'anno scelto (colonne divise per tipo
  di rifiuto, toccabili per il dettaglio del mese) e confronto fra gli ultimi
  5 anni.

### Manutenzioni

- **Manutenzioni periodiche** della casa: caldaia, climatizzatore, fossa
  biologica, e altre 27 categorie con la loro icona.
- **Ricorrenza** libera: ogni N giorni, settimane, mesi o anni. La data
  dell'ultima esecuzione può restare vuota — i promemoria partono dalla prima
  esecuzione che registri.
- **Promemoria** il giorno della scadenza, con un sollecito dopo una settimana
  se nessuno la sistema. Dalla notifica puoi segnarla eseguita o saltarla.
- **Esegui**: registra l'esecuzione a oggi e ti lascia aggiornare costo, note e
  ricorrenza nello stesso momento.
- **Salta**: sposta la scadenza a quella successiva senza far risultare la
  manutenzione eseguita. Se sei molto in ritardo, le salta tutte in una volta.
- **Chiama**: il numero di chi fa la manutenzione, salvato dentro l'app e quindi
  visibile a tutti i membri. Si sceglie dalla rubrica o si scrive a mano.
- **Storico** per ogni manutenzione, con costi e chi l'ha registrata,
  modificabile ed eliminabile.

### In comune

- **Condivisione**: inviti un familiare con un codice a 6 caratteri e da quel
  momento vedete gli stessi ritiri, gli stessi contatori e le stesse
  manutenzioni. Non importa chi porta fuori il pattume o chiama il tecnico:
  tutto prosegue.

---

## Configurazione iniziale (da fare una volta)

Il codice è completo, ma l'app **non parte** finché non colleghi un progetto
Firebase. Questi passaggi richiedono il tuo account Google, quindi li devi fare
tu.

### 1. Crea il progetto Firebase

1. Vai su <https://console.firebase.google.com> → **Aggiungi progetto**.
2. Nome: `rubbish-manager` (o quello che preferisci).
3. Google Analytics: **disattiva**, non serve.
4. Resta sul piano **Spark (gratuito)**: l'app è progettata per non richiedere
   Cloud Functions.

### 2. Abilita i servizi

Nella console del progetto:

- **Authentication** → *Sign-in method* → abilita **Google**.
  (Solo Google: l'app non usa email/password.)
- **Firestore Database** → *Crea database* → posizione **`eur3` (europe-west)** →
  modalità **produzione** (le regole arrivano dal repository, al punto 5).

### 3. Collega l'app al progetto

Dalla cartella del progetto:

```bash
curl -sL https://firebase.tools | bash
```

```bash
firebase login
```

```bash
dart pub global activate flutterfire_cli
```

```bash
flutterfire configure --platforms=android,ios --android-package-name=it.davideorsini.rubbish_manager
```

Questo genera `lib/firebase_options.dart` e scarica
`android/app/google-services.json`.

> Questi file **non sono nel repository**: contengono le chiavi del progetto
> Firebase di chi li ha generati, quindi ognuno usa i propri. Finché non lanci
> il comando qui sopra il progetto non compila. Per sapere che forma deve avere
> il file c'è `lib/firebase_options.dart.example`.

### 4. Registra l'impronta SHA-1 (obbligatorio per l'accesso Google)

Senza questo passaggio l'accesso con Google fallisce con "errore 10".

```bash
cd android && ./gradlew signingReport
```

Copia il valore **SHA1** della variante `debug`, poi in console Firebase →
*Impostazioni progetto* → app Android → **Aggiungi impronta digitale**.

Infine ri-scarica il file di configurazione:

```bash
flutterfire configure --platforms=android,ios --android-package-name=it.davideorsini.rubbish_manager
```

> **Verifica**: apri `android/app/google-services.json` e controlla che contenga
> una voce `oauth_client` con `"client_type": 3`. È il client web da cui
> Google Sign-In ricava il token; se manca, l'accesso non funziona.

### 5. Pubblica le regole di sicurezza

**Obbligatorio**: senza questo passaggio Firestore rifiuta ogni lettura e
scrittura, quindi l'app mostra errori di permesso ovunque.

```bash
firebase deploy --only firestore:rules
```

Le regole (`firestore.rules`) fanno in modo che solo i membri di un'abitazione
possano leggerne e modificarne i dati, e che per entrare in un'abitazione serva
un codice di invito valido — verificato lato server, non lato app.

### 6. Avvia

```bash
flutter run
```

---

## Comandi utili

Test (dominio, ricorrenze, quote, promemoria):

```bash
flutter test
```

Analisi statica:

```bash
flutter analyze
```

APK da installare a mano su altri telefoni:

```bash
flutter build apk --release
```

Esce in `build/app/outputs/flutter-apk/app-release.apk`. È firmato con il
keystore di debug (vedi *Limiti noti*), che è lo stesso la cui impronta SHA-1 è
registrata su Firebase: l'accesso Google funziona anche su altri dispositivi.
Sul telefono di destinazione serve consentire l'installazione da origini
sconosciute.

Rigenerare l'icona dopo aver modificato `assets/icon/icon.svg`:

```bash
rsvg-convert -w 1024 -h 1024 assets/icon/icon.svg -o assets/icon/icon.png && dart run flutter_launcher_icons
```

---

## Come è fatto

```
lib/
  core/            valori e utilità puri (date, cataloghi, importi, telefono)
  domain/          entità, motori di ricorrenza, quote e scadenze
  data/            repository su Firestore e autenticazione
  notifications/   pianificazione promemoria, isolate di background
  features/        una cartella per area (hub, rifiuti, manutenzioni, …)
  widgets/         componenti condivisi
firestore.rules    regole di sicurezza multi-utente
```

### Le decisioni che spiegano il resto

**I contatori non sono memorizzati, sono ricavati.** Ogni raccolta è un
documento; "quanti gratuiti restano" si calcola contando quei documenti
nell'anno. Un contatore memorizzato andrebbe corretto a ogni modifica dello
storico, e un solo aggiornamento mancato lo farebbe divergere per sempre senza
modo di ripararlo. Così invece correggere lo storico corregge automaticamente
ogni totale, e funziona anche offline (le transazioni Firestore no).

**L'id di una raccolta programmata è deterministico**: `carta_2026-08-19`. Se tu
e tuo padre confermate lo stesso ritiro — uno dall'app, uno dalla notifica, uno
magari offline — le due scritture finiscono sullo stesso documento e il
conteggio resta 1. Nessuna transazione, nessuna race condition. Le raccolte
*extra* hanno invece un suffisso casuale, perché due sacchi extra nello stesso
giorno sono due eventi veri.

**Saltare è un evento, non un'assenza di evento.** Un ritiro saltato viene
scritto nel registro con lo *stesso* id deterministico di una raccolta, con
`status: skipped`. Così eredita gratis tutte le garanzie: se tu e tuo padre
saltate lo stesso ritiro conta comunque una volta sola, e se uno salta e
l'altro conferma vince l'ultima scelta invece di creare due record in conflitto.
Non consuma quota, esclude il ritiro dalle statistiche e ferma il promemoria.
I documenti scritti prima che il salto esistesse non hanno il campo `status` e
vengono letti come raccolte reali, che è ciò che erano.

**Le manutenzioni riusano la stessa disciplina.** La prossima scadenza non è
memorizzata: si ricava da un registro di esecuzioni, così come i contatori dei
rifiuti si ricavano dalle raccolte. Ne discende tutto il resto — due membri che
premono "Esegui" lo stesso giorno contano una volta, correggere lo storico
ricalcola le scadenze da solo, e i pulsanti della notifica sono sicuri anche
dall'isolate di background perché nessuna scrittura deve prima leggere.

Con una differenza voluta rispetto ai rifiuti: **un salto ha un id diverso da
un'esecuzione**. Condividerlo permetterebbe a un salto che arriva il giorno
della scadenza — il caso normale, visto che è quando arriva il promemoria — di
sovrascrivere un'esecuzione, cancellandone il costo e riportando indietro di un
intero periodo la data dell'ultima manutenzione.

**I promemoria sono notifiche locali, non push.** Funzionano offline e non
richiedono un server. Il testo però viene fissato quando la notifica è
programmata, quindi se tuo padre registra una raccolta dal suo telefono il
numero sul tuo potrebbe essere vecchio. L'app riscrive i promemoria a ogni
apertura e a ogni modifica dei dati (gli id sono stabili, quindi la
riprogrammazione sostituisce la notifica in sospeso), e per i ritiri a più di
due giorni aggiunge "(dati al gg/mm)" invece di dichiarare un numero come certo.

---

## Note sui test e sulla build

- I test coprono la parte a rischio: aritmetica delle date, motore delle
  ricorrenze (tutti i casi limite: settimane pari/dispari, ancora nel futuro,
  cambio dell'ora, confine d'anno), calcolo delle quote, testo e
  raggruppamento dei promemoria, e le invarianti del registro delle raccolte
  (idempotenza fra utenti, spostamenti, fusioni).
- **`fake_cloud_firestore` non è utilizzabile**: la versione 4.1.1 è
  incompatibile con `cloud_firestore` 6.x (la firma di `MockWriteBatch.update`
  non corrisponde più a quella del pacchetto reale). Al suo posto
  `test/collection_ledger_test.dart` modella il contratto che conta davvero —
  documenti indirizzati per id, dove riscrivere lo stesso id sovrascrive — e
  verifica su quello le invarianti del conteggio.
- **Build iOS non verificata**: `flutter build ios` si ferma su `pod install`
  per un problema noto di CocoaPods su Mac ARM con la Ruby di sistema
  (`Error: To set up CocoaPods for ARM macOS…`). Non dipende dal codice. Si
  risolve in uno dei due modi:

  ```bash
  brew install cocoapods
  ```

  oppure, con la Ruby di sistema (richiede la password):

  ```bash
  sudo gem uninstall ffi && sudo gem install ffi -- --enable-libffi-alloc
  ```

  Il codice Dart non ha percorsi solo-Android fuori dai controlli
  `Platform.isAndroid`, e `ios/Podfile` è già impostato su iOS 15 (minimo
  richiesto da Firebase Auth 6).
- **Avviso NDK durante la build Android**: alcuni plugin dichiarano di volere
  l'NDK 27, mentre installato c'è il 26.3. La build funziona (nessuno di questi
  plugin compila codice nativo qui). Per far sparire l'avviso serve scaricare
  l'NDK 27 (~1 GB) e aggiungere `ndkVersion = "27.0.12077973"` in
  `android/app/build.gradle.kts`.

## Limiti noti

- **Notifiche su telefoni aggressivi**: Xiaomi, Huawei e alcuni Samsung
  sospendono le app in background e possono ritardare o perdere i promemoria.
  Escludi l'app dall'ottimizzazione batteria nelle impostazioni di sistema. In
  *Impostazioni* dell'app c'è anche l'opzione "Orario preciso" se vuoi la
  notifica al minuto esatto.
- **Anno solare**: i ritiri gratuiti si azzerano il 1º gennaio. Se il tuo comune
  usa un periodo diverso, il punto da cambiare è
  `lib/domain/quota_calculator.dart`.
- **Manutenzioni molto trascurate**: il registro viene caricato fino a 10 anni
  indietro (di più per ricorrenze lunghe). Una manutenzione la cui ultima
  esecuzione è più vecchia del limite risulta "Mai eseguita" finché non ne
  registri una nuova. Il limite è in `logLowerBound`,
  `lib/domain/maintenance_schedule.dart`.
- **Un contatto per manutenzione**, nome e numero, copiati nell'app e visibili a
  tutti i membri dell'abitazione.
- **Storico limitato a 5 anni nell'interfaccia**: su Firestore non viene
  cancellato nulla, ma i selettori d'anno e le statistiche mostrano solo gli
  ultimi 5. Per cambiarlo, `historyYears` in `lib/domain/statistics.dart`.
- **Un calendario per tipo**: l'interfaccia imposta una sola regola di
  ricorrenza per rifiuto. Il modello dati ne supporta già una lista, quindi
  "lunedì ogni settimana + giovedì ogni 15 giorni" è solo lavoro di interfaccia.
- **Nessun trasferimento di proprietà**: chi crea l'abitazione resta il
  proprietario ed è l'unico che può eliminarla o rimuovere membri.
- **Massimo 10 membri** per abitazione (limite imposto dalle regole di
  sicurezza).
- **Firma di rilascio**: la build release usa ancora le chiavi di debug
  (`android/app/build.gradle.kts`). Va sostituita prima di distribuire l'app.
