# Traspaso — cliente watchOS autónomo

Documento para retomar el trabajo en una sesión nueva sin perder contexto.
Escrito el 2026-08-10, sobre la rama `feat/workout-watch-connectivity`
(43 commits, **nada pusheado**).

---

## 1. Qué se está construyendo

Un **companion de Apple Watch autónomo** para TREINO. No espeja al teléfono:
tiene credencial propia y habla Firestore por su cuenta, así que funciona con
el celular guardado en el bolso.

Frase del dueño que define el alcance: **"el reloj es un complemento 100x100"**.
Lo que se marca en un lado tiene que verse en el otro, y terminar en uno tiene
que terminar en los dos.

### La restricción que manda sobre todo

**Firestore NO existe en watchOS.** Firebase watchOS es community-supported y
Firestore no figura entre sus productos. El reloj habla la **REST API** con ID
tokens de Firebase Auth como Bearer.

Verificado contra el emulador: **las Security Rules SÍ se aplican** a esas
requests. Es la premisa sobre la que descansa toda la arquitectura.

Consecuencias que hay que tener presentes SIEMPRE:

- El reloj **no tiene listeners**. No hay push. Se entera de las cosas cuando
  relee: al cambiar de página, al volver a primer plano, o cuando el teléfono
  le manda un aviso por WatchConnectivity.
- El target watchOS tiene **cero dependencias de Firebase**.
- No hay persistencia offline del SDK: la que hay está escrita a mano
  (`WorkoutSessionStore`, un JSON en disco).

---

## 2. Arquitectura, archivo por archivo

### Reloj (`ios/TreinoWatch Watch App/`)

| Archivo | Qué hace |
|---|---|
| `FirestoreREST.swift` | Cliente HTTP contra Firestore. Sin SDK. Incluye los helpers `FS.*` para desarmar los value-wrappers. |
| `FirebaseAuthREST.swift` | Canje de custom token y renovación de ID token. |
| `CredentialStore.swift` | Keychain. **Sobrevive a la desinstalación de la app.** |
| `CredentialCoordinator.swift` | Estado de credencial, carga de la rutina, y recepción de avisos del teléfono (`WCSessionDelegate`). |
| `RoutineCatalog.swift` | Las 4 queries de rutinas. **Puerto de `routine_repository.dart`** — los filtros tienen que coincidir campo por campo. |
| `TodaysWorkout.swift` | Resuelve el entreno. Dos variantes: por rutina activa, y **por posición explícita** (ver §4). |
| `WorkoutCoordinator.swift` | Sesión en curso: empezar, adoptar una remota, cargar series, sincronizar, terminar. |
| `HistorySync.swift` | Lectura/escritura del historial. Idempotencia por `exerciseId__setNumber`. |
| `ContentView.swift` | Navegación de 3 páginas + HOY. |
| `RoutineListView.swift` | Listas laterales (planes / plantillas) y hoja de detalle. |
| `WorkoutView.swift` | Pantalla de entreno. |

### Teléfono (Dart)

| Archivo | Qué cambió |
|---|---|
| `lib/features/watch/` | Handoff de credencial + `WatchNudgeService` (avisos al reloj). |
| `session_repository.dart` | `watchRevision`, `watchSetLogs`, `watchSessionFinished`. |
| `session_providers.dart` | `sessionsRevisionProvider` — una señal que dispara refetch. |
| `session_notifier.dart` | Escucha la sesión en vivo, invariante anti-duplicados, avisos al reloj. |
| `session_player_screen.dart` | Sale del player si el reloj cerró el entreno. |
| `home_screen.dart` | El aviso de retomar solo sale si Home es la ruta visible. |
| `functions/src/mint-watch-credential.ts` | CF que mintea la credencial del reloj. |

---

## 3. Contrato de conformidad — NO romper

`conformance/*.json` son fixtures que corren **los dos lenguajes**:

- Dart: `flutter test test/conformance/`
- Swift: `bash conformance/run_swift.sh` (también en CI, job `conformance-swift`)

Cubren tres reglas portadas a mano a Swift: avance de plan, elección de rutina
activa, y resolución de series por semana. **Si tocás una de las dos
implementaciones sin la otra, CI se pone rojo.**

⚠️ **El contrato cubre la DECISIÓN, no de dónde salen los datos.** Ya se
colaron tres bugs por ese hueco (§4).

---

## 4. Las trampas que costaron tiempo — leer antes de tocar nada

### 4.1 `finishedAt`: "ausente" ≠ "nulo explícito"

El teléfono escribe la clave con `nullValue`; el reloj la omite. Preguntar
`campo == nil` en Swift da lo CONTRARIO de lo que uno quiere sobre documentos
del teléfono.

Usar **`FS.isEmpty` / `FS.isPresent`**, nunca `== nil`, sobre cualquier campo
que el teléfono pueda escribir nulo.

Rompía cuatro cosas, tres anteriores a este ciclo — la peor: el reloj
adelantaba el día del plan a mitad de entreno.

Las `firestore.rules` ya documentaban la misma trampa del lado servidor.

### 4.2 El id del documento sale del PATH, no de un campo

Los docs creados por la app no guardan `id` adentro; solo los del seed. Leerlo
de los campos dejaba las rutinas reales con id vacío.

### 4.3 Cada cliente genera ids distintos para la misma serie

Teléfono: autogenerado (`.doc()`). Reloj: determinístico
(`exerciseId__setNumber`). La misma serie escrita de los dos lados creaba DOS
documentos.

**No se puede pasar el teléfono a ids determinísticos**: al borrar una serie
renumera las siguientes, y eso obligaría a mover documentos.

Las defensas originales —`remoteDocId` en el reloj y el aviso por cada serie—
**no alcanzaban, y está medido**: las dos preguntan por el estado LOCAL, que es
tan fresco como el último snapshot que llegó. En el emulador el teléfono creó su
duplicado **37 segundos** después del reloj. 13 de 77 sesiones tenían duplicados.

Desde `fix/watch-sync-bugs` la deduplicación vive en la ESCRITURA:

- El teléfono consulta la ruta determinística del reloj antes de crear su
  documento, y escribe SOBRE ese si ya está.
- `WorkoutCoordinator.sync` LEE el historial ANTES de subir lo pendiente. Ese
  orden es parte del contrato: estaba al revés y por eso no había nada que pisar.
- La fórmula del id quedó bajo `conformance/set_log_identity.json`, porque vive
  escrita en los dos lenguajes y una divergencia de un carácter vuelve a
  duplicar en silencio.

⚠️ **La identidad se decide por los CAMPOS, nunca por la ruta.** Al renumerar,
`updateSetLog` conserva el id, así que `sentadilla__3` puede contener la serie 2.
Escribir ahí confiando en el path PIERDE esa serie — peor que el duplicado.

### 4.4 La posición del plan la manda el HISTORIAL, no el cálculo

Para una sesión que ya existe hay que usar
`TodaysWorkoutResolver.resolve(...dayNumber:weekNumber:)`. La variante sin
posición calcula el día que TOCARÍA HOY con `nextPlanPosition`, que no tiene
por qué ser el de la sesión abierta.

Ese bug se veía como "dejó de sincronizar": los datos cruzaban perfecto, pero
cada dispositivo miraba un día distinto del plan.

### 4.5 Hacer algo reactivo tiene efectos en cascada

**Tres bugs seguidos salieron de esto.** Al agregar un stream o volver
reactivo un provider, preguntarse SIEMPRE quién más está escuchando:

- El stream de setLogs hizo que `logSet` contara la serie dos veces (la propia
  escritura dispara su snapshot).
- `activeSessionForUidProvider` reactivo hizo que el aviso de retomar saltara
  encima del entreno recién empezado, porque Home queda montada abajo del
  player.
- **Y mordió una tercera vez, en `removeSet`** (2026-08-13). Renumeraba con un
  DELTA (`setNumber - 1`) sobre el estado re-leído después del await; el
  snapshot de su propia escritura ya venía renumerado, así que el delta se
  aplicaba dos veces: 3 → 2 → 1. El estado quedaba con dos series en el mismo
  número y la fila del medio sin tildar.

**La lección, ya con tres casos: no preguntarse "¿el stream ya pasó?" — hacer
que el camino sea IDEMPOTENTE.** Aplicar valores absolutos, no deltas. Y pasar
siempre por el invariante `_dedupedLogs`: `removeSet` era el único camino de
mutación que lo salteaba, y por eso las dos series duplicadas sobrevivían.

---

## 5. Trampas de herramientas y entorno

- **`analyze` no ejecuta nada.** No detecta un mock incompleto. 42 tests se
  cayeron por eso y `analyze` estaba en verde.
- **No lanzar dos builds de Xcode en paralelo**: comparten DerivedData y se
  pisan. Encadenarlos.
- **Typecheck rápido del reloj** (segundos, contra +20 min de `xcodebuild`):
  ```
  xcrun swiftc -typecheck -sdk $(xcrun --sdk watchos --show-sdk-path) \
    -target arm64_32-apple-watchos26.2 "ios/TreinoWatch Watch App/"*.swift
  ```
- **El Keychain sobrevive a la desinstalación** en watchOS. Para limpiar
  credencial de verdad: `xcrun simctl erase`.
- **`flutter run` del teléfono construye LAS DOS apps** (el reloj está en
  `Embed Watch Content` de Runner): un solo build de Xcode, ~20 min. Pero
  **NO reinstala el companion en el reloj emparejado** — hay que hacerlo a mano:
  ```
  xcrun simctl install <watch-udid> \
    build/ios/Debug-watchsimulator/"TreinoWatch Watch App.app"
  ```
- **Para saber si el binario instalado es el tuyo, usá `shasum -a 256`** del
  instalado contra el construido. `nm` y `strings` NO sirven en el binario del
  reloj: devuelve 105 símbolos, todos `OUTLINED_FUNCTION`, y cero cadenas de
  Swift. Validá siempre el instrumento contra algo que SEPAS que está, antes de
  creerle un resultado negativo.
- **Los timestamps de Firestore son UTC.** Argentina es UTC-3. Leerlos como hora
  local inventa un desfase de 3 horas y arruina cualquier cronología.
- **El listado REST de Firestore PAGINA.** `.../sessions` sin `pageToken`
  devolvía 30 de 77 sesiones. Cualquier conteo sobre el historial tiene que
  seguir `nextPageToken` o subestima.
- **`pod install` necesita `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`**; si no, tira
  `Encoding::CompatibilityError` y el error REAL queda tapado por el crash del
  generador de reportes.
- **`sd` reemplaza TODAS las ocurrencias.** `sd 'runFoo()' 'runFoo()\nrunBar()'`
  pisa también la línea `private func runFoo() {` y rompe la compilación.
- **La escala de los screenshots del simulador no es 2.0.** Con el iPhone 17 Pro
  Max (440×956 pt) es ~2.09×. Calibrala con un toque que SÍ haya funcionado; si
  no, los toques caen fuera del botón y parece que la app no responde.
- **`-sdk iphonesimulator` pisa el SDKROOT de TODOS los targets** y compila el
  reloj contra iOS, dando errores falsos. Usar `-destination`.
- **Un target tiene que declarar su propio `SUPPORTED_PLATFORMS`.** El template de
  Flutter lo setea en `iphoneos` a nivel PROYECTO, pero **sólo en Release y
  Profile — en Debug no está**. El target del reloj declaraba `SDKROOT = watchos`
  y heredaba el resto: en Debug Xcode derivaba `watchos watchsimulator` y andaba;
  en Release el `iphoneos` heredado le ganaba y Xcode resolvía la plataforma del
  reloj como iOS. Síntoma: `actool` corría con `--platform iphoneos` sobre un
  catálogo con idioms `watch` y el build moría con *"the app icon set named
  AppIcon did not have any applicable content"* apuntando a la carpeta del reloj,
  **que estaba perfecta**. El ícono nunca fue la causa: el target entero se
  compilaba contra iOS, y por eso también aparecían errores de disponibilidad de
  Swift (`'onChange(of:initial:_:)' is only available in iOS 17.0 or newer`) —
  esos NO eran falsos, eran el bug. Arreglado en `2d05fa02`. Se diagnostica en
  segundos, sin builds de 20 minutos:
  ```
  xcodebuild -showBuildSettings -project ios/Runner.xcodeproj \
    -target "TreinoWatch Watch App" -configuration Debug|Release \
    | rg SUPPORTED_PLATFORMS
  ```
- **`flutter build ios --simulator` NO arranca sin `-d`** mientras haya companion
  de reloj: *"A device ID is required to build an app with a watchOS companion
  app"*. Muere antes de compilar una línea, así que un "falló el build" ahí no
  dice absolutamente nada sobre el código.
- **El exit code de un comando piped o en background MIENTE.** `xcodebuild | tail`
  devuelve el de `tail`; `cmd; echo EXIT=$?` lanzado en background devuelve el del
  `echo`. Un `firebase deploy` que salió con 2 se reportó como 0 y casi pasa por
  bueno. Capturar el código REAL dentro del log, o buscar `BUILD SUCCEEDED`.
  (`timeout` tampoco existe en macOS: es `gtimeout`, de coreutils.)
- **App Attest NO funciona con un build firmado para desarrollo.** `flutter build
  ios --release` compila Dart en release pero firma con el perfil de desarrollo:
  `aps-environment=development`, `get-task-allow=true` y sin el entitlement
  `com.apple.developer.devicecheck.appattest-environment`. iOS atestigua entonces
  contra el ambiente *development* de Apple y Firebase valida contra *production*.
  Resultado: `mintWatchCredential` (que tiene `enforceAppCheck: true`) rechaza con
  *"Decoding App Check token failed"*, `deliverCredential` se lo traga en su
  `catch (_)`, y **el reloj nunca recibe credencial sin un solo error visible**.
  Para probar en hardware real: o TestFlight, o `AppleProvider.debug` sin
  commitear con el token registrado en Console — esto último deja
  `enforceAppCheck` PRENDIDO en el servidor, que es lo que uno quiere.
- **Firebase hace públicas las callables Gen2 con `invokerIamDisabled`, NO con un
  binding `allUsers → run.invoker`.** En `treino-dev` ese binding es además
  **imposible**: `constraints/iam.allowedPolicyMemberDomains` está enforced con
  `allowedValues: [C03bxdsb7]`. Una callable puede figurar en `functions:list` y
  **no ser invocable**. Se lee como anotación en el describe normal:
  ```
  gcloud run services describe <servicio> --region=<region> --format=json \
    | rg invoker-iam-disabled
  # /metadata/annotations/run.googleapis.com/invoker-iam-disabled = true
  ```
  Distinguir por la FORMA de la respuesta: **403 HTML** = el frontend de Google
  bloquea antes del contenedor; **401 JSON `UNAUTHENTICATED`** = contestó la
  función (ese 401 es el resultado CORRECTO sin token de Auth). Se arregla con
  `gcloud run services update <servicio> --no-invoker-iam-check`.
- **Los servicios de Cloud Run van en MINÚSCULAS** (`addalias`, no `addAlias`), y
  `gcloud run services get-iam-policy <nombreMalEscrito>` **no da 404**: devuelve
  `{"etag":"ACAB"}`, indistinguible de un servicio real sin bindings. Un typo de
  mayúsculas se lee como un hallazgo.
- **Un filtro de ruido puede comerse la respuesta.** Diffeando el `describe` de
  dos servicios de Cloud Run para encontrar por qué uno era alcanzable y el otro
  no, el filtro que sacaba claves ruidosas incluía `annotations/run` — justo
  donde vive `invoker-iam-disabled`. El diff salió "sin diferencias de
  autorización" y llevó a concluir que el dato no estaba en esa API. **Estaba.**
  Corolario del ítem de arriba sobre validar el instrumento: cuando un diff no
  encuentra nada, sospechá del filtro antes que de los datos.
- **`CFBundleIconName` en watchOS vive ANIDADO** bajo `CFBundleIcons →
  CFBundlePrimaryIcon`, no en la raíz del plist. `plutil -extract CFBundleIconName`
  contra la raíz da un falso negativo.
- La suite completa a veces tira caídas del runner (`Cannot close sink while
  adding stream`, SIGTERM) por contención de recursos. Confirmar corriendo los
  archivos aislados antes de creer que es el código.

---

## 6. Cómo correr todo

```bash
# emuladores (firestore 8080, auth 9099, functions 5001)
firebase emulators:start --only firestore,auth,functions

# app del telefono
flutter run -d <iphone-udid> --dart-define=USE_EMULATOR=true

# app del reloj
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme "TreinoWatch Watch App" -destination "id=<watch-udid>" build
xcrun simctl install <watch-udid> "<DerivedData>/Debug-watchsimulator/TreinoWatch Watch App.app"
```

Simuladores emparejados usados:
`iPhone 17 Pro Max 6D8702CE-7635-4B4A-BAC5-CBC9E7FB76AA` +
`Apple Watch Series 11 42mm EF0E3E46-7BA4-4746-9D2C-E9D78DD7A0D3`.

Atleta de prueba: `seed-athlete-001` (`martin@emulator.treino`).

Inspeccionar Firestore sin pasar por la app:
`curl -H "Authorization: Bearer owner" "http://localhost:8080/v1/projects/treino-dev/databases/(default)/documents/..."`

---

## 7. Estado: qué está verificado y qué no

### Verificado A MANO en el simulador

- Navegación de 3 páginas, activar rutina, empezar sin cambiar la activa
- El reloj entra en modo entreno solo cuando el celular arranca uno
- Marcar en el reloj aparece en el teléfono en vivo
- Terminar en el reloj cierra el player del teléfono
- El aviso "entrenamiento en curso" aparece solo cuando el reloj empieza
- Las series no se duplican en Firestore
- Al arrancar, ambos dispositivos muestran el MISMO día del plan

### Verificado el 2026-08-13 (los tres que estaban pendientes acá)

- **El descanso del reloj al marcar una serie desde el teléfono.** Banner en
  **177s** de los 180 planificados de press de banca, serie tildada y cursor
  movido a la siguiente — sin tocar el reloj.
- **El orden de series** (no dejar marcar la 3 sin la 2). Medido con la MISMA
  coordenada dos veces: con la serie 2 sin marcar no pasa nada, con la 2 hecha
  carga la 3. Así no se confunde con un toque perdido.
- **Descartar desde Home cierra el entreno también en el reloj.** La muñeca
  vuelve a HOY sola. Es un camino distinto del ABANDONAR del player, y
  `home_screen.dart` tiene su propio aviso al reloj porque ahí el notifier ni
  siquiera está vivo.

### Verificado el 2026-08-13 (build de release, `2d05fa02`)

- **La rama vuelve a generar builds de release.** `flutter build ios --release`
  verde en 467.7s. El reloj embebido reporta `platform WATCHOS / minos 26.2 /
  sdk 26.2`, y el build de simulador reporta `WATCHOSSIMULATOR` — las dos mitades
  de `SUPPORTED_PLATFORMS` quedaron ejercitadas, ninguna supuesta.
- **La app corre SUELTA en un iPhone físico**, sin cable ni debugger (PID vivo tras
  el lanzamiento con `devicectl`). Esto es lo que destraba medir en hardware real
  lo que el simulador no puede dar.
- `mintWatchCredential` **desplegada y alcanzable** en `treino-dev`. Verificado el
  recorrido completo de la sonda: `404` (no existía) → `403` (desplegada pero sin
  invocador) → `401 JSON UNAUTHENTICATED` (correcto). Ver la trampa de
  `invokerIamDisabled` en §5.

### Implementado pero NUNCA verificado corriendo

- **El handoff de credencial al reloj, end-to-end.** El teléfono SÍ llama a la
  función (3 invocaciones medidas en los logs de Cloud Run), lo que además prueba
  que `isPaired` da true. Pero **App Check rechaza el token** porque el build está
  firmado para desarrollo — ver §5. Hasta resolver eso, nada de lo que dependa de
  la credencial del reloj se puede probar en hardware.
- **Que el descanso siga corriendo con la muñeca baja.** Es el corazón del ciclo de
  HealthKit y hoy está medido SOLO en simulador (0 segundos perdidos en 72). El
  simulador no puede responder esta pregunta.

### Quality gates al último commit

`flutter analyze` 0 issues · conformidad Swift 50 casos · tests puros del reloj
**111 chequeos** · typecheck del reloj limpio · **backfill 22 tests**. Los cinco
con exit code 0 verificado aparte (ver la trampa de exit codes en §5).

Tres corredores nuevos desde el traspaso original:
`bash scripts/test_watch_swift.sh` (lógica pura del reloj, segundos), el
fixture `conformance/set_log_identity.json`, y `npm test` desde `scripts/`
(la decisión del backfill de duplicados, sin Firestore).

---

## 8. Deuda conocida — NO es de este ciclo

1. ~~**Sesiones abandonadas se acumulan para siempre.**~~ — **RESUELTA en
   `558759f1`**, verificada en código el 2026-08-13. `getActive` mira las 10
   `active` más nuevas (`_staleActiveSweep`, `session_repository.dart:49`) y
   **cierra con un write real** (`status: finished`, `wasFullyCompleted: false`,
   `:366-375`) todo lo que pase de `maxWorkoutDuration` = 8h. No es un filtro en
   memoria. Cubierto por tests en `session_repository_test.dart:212-314`.
   ~~⚠️ Pero el barrido lo dispara SÓLO el teléfono.~~ — **CERRADO.** El reloj
   ahora aplica la MISMA política: `StaleSessionRules.decidir` (archivo nuevo)
   decide qué adoptar y qué cerrar, y `findAnyActiveSession` la usa y cierra las
   colgadas con `HistorySync.closeStaleSession` (los mismos campos que escribe
   `getActive`: `status`, `finishedAt`, `wasFullyCompleted: false`, y nada más).
   El corte se DERIVA de `WorkoutDurationRules.maxMinutos`, no se copia, así que
   los dos lados no se pueden separar sin que caiga un test.
   Medido en el host: 9 chequeos en `ios/watch_tests/main.swift`
   (`runStaleSessions`), con control negativo — sacando el corte se ponen rojos 5,
   incluido "una sesión de hace tres días NO se adopta".
   Sigue drenando de a 10 por lectura, y el cierre es best-effort igual que en el
   teléfono. **NO verificado corriendo en la muñeca**: la regla está medida, el
   write no.
2. **`racha` / `workoutsCount`** los escribe el cliente del teléfono en
   `SessionRepository.finish`, así que terminar desde el reloj los deja
   desactualizados. Candidato: moverlos a `rankingAggregateOnSession`.
3. ~~**No hay salida de un entreno que no podés completar.**~~ — **RESUELTA en
   `558759f1`**, verificada en código el 2026-08-13. `WorkoutView.swift:57-87`
   muestra "Abandonar entreno" en la rama donde antes sólo había un texto muerto,
   detrás de un `confirmationDialog` (`:91-103`). `abandon()` delega en `finish()`
   (`WorkoutCoordinator.swift:304-306`), que cierra la sesión con
   `wasFullyCompleted: false`. En el teléfono nunca fue deuda.
   ~~⚠️ Dos huecos que quedan~~ — **CERRADOS los dos.** El coordinator publica
   ahora `closeFailure` (`WorkoutCloseFailure`, archivo nuevo), que distingue
   `seriesSinSubir(n)` de `historialNoRespondio`, y `WorkoutView` lo renderiza en
   un banner naranja con **Reintentar** — el mismo contrato que
   `_showFinishError` del teléfono. `syncError` se queda como detalle técnico
   para diagnóstico; lo que ve el atleta es el motivo y la salida.
   El cartel se limpia solo cuando la cola se drena en un `sync()` de fondo.
   Medido en el host: 6 chequeos (`runCloseFeedback`).
   ⚠️ **NO verificado corriendo**: el banner no se vio en la muñeca todavía. Lo
   que está medido es el mensaje, no el render.
   ⚠️ Efecto lateral conocido: `finish()` llama a `stopRest()` antes de intentar
   cerrar, así que un abandono fallido deja al atleta sin el descanso que estaba
   corriendo. Ya pasaba antes —en silencio—; ahora al menos se entera de que
   sigue en el entreno.
4. **El duplicado del estado local se tapó con un invariante**, no con la causa
   raíz. Si vuelve a aparecer algo relacionado, **instrumentar el notifier** en
   vez de sumar defensas.
5. ~~**Discrepancia "PLAN COMPLETADO" (celu) vs "Sem 2/3" (reloj)**~~ —
   **RESUELTA, y NO era un bug.** `openspec/changes/repetir-plan-completado`
   decidió (AD-2, firmada) que el rollover infinito de `todaysRoutineProvider`
   *"was never wrong — it was only contradicted by this screen. Both stay."* El
   problema era que la pantalla de detalle BLOQUEABA mientras Home rotaba; ese
   candado se sacó y `planComplete` quedó como señal, con REPETIR de acción.
   El reloj rota igual que Home, así que son consistentes.
   **Antes de "arreglar" algo del avance de plan, leer `openspec/changes/`.**
6. ~~`WCErrorCodeWatchAppNotInstalled` al entregar la credencial no tiene
   reintento.~~ — **RESUELTA**, verificada en código el 2026-08-13. Hay reintento
   por resume en `watch_credential_providers.dart:107-109`, que corta bien en
   `notSupported` / `noWatchPaired` / `delivered` para no pegarle a la CF en cada
   foreground.
   ⚠️ **Cubre por superconjunto, no por detección**: el `catch (_)` de
   `watch_credential_service.dart:119` colapsa ese error con cualquier otro, y no
   hay alternativa realista porque el plugin sólo expone el `WCErrorCode` dentro
   de `localizedDescription`.
   ~~**Race NO cubierta**~~ — **CERRADA en código.** `noWatchPaired` pasó a
   reintentable, y el arranque hace hasta `watchPairingRaceRetries` (2)
   re-chequeos con `watchPairingRaceDelay` (2s) antes de creerle a un `isPaired`
   que puede haber respondido antes de la activación.
   ⚠️ **El motivo por el que estaba excluido era FALSO**, y por eso se pagaba de
   más: decía que reintentar sería "un viaje a la CF en cada foreground", pero
   `deliverCredential` corta en `isPaired` **antes** de tocar `_functions` —
   `watch_credential_service_test.dart:54` ya lo afirmaba con un `verifyNever`
   sobre `httpsCallable`. Un reintento sin reloj cuesta un MethodChannel.
   El reintento por resume no alcanzaba solo: la race pasa en el arranque en
   frío y un atleta que abre la app y la usa **puede no generar un resume en toda
   la sesión**. Por eso los reintentos van en el arranque, no en el resume.
   Cierra además el caso de emparejar el reloj con la app ya abierta.
   Medido con control negativo en las dos mitades (la reclasificación y el bucle
   acotado), 4 tests nuevos. **Sigue sin confirmarse en dispositivo real**: lo
   que está medido es la política, no el timing verdadero de `WCSession`.
7. **Sin confirmar si `WCSession` exige algún capability nuevo en Signing &
   Capabilities.** SIGUE ABIERTA — una sesión la dio por cerrada, se verificó el
   2026-08-13 y **la afirmación era falsa**: `docs/setup/watchos-target.md:279-284`
   y `state.yaml:153-156` siguen diciendo "sin verificar". Lo único que el repo
   sostiene es más débil: hoy **no hay ningún entitlement de WatchConnectivity en
   ningún target** y el reloj compila así. Eso no lo prueba — un capability
   faltante no rompe la compilación (`test_watch_capabilities.sh:12-15` documenta
   exactamente ese modo de falla), y el build de simulador no firma contra el App
   ID del portal. **Se cierra firmando el reloj para un Apple Watch físico**, no
   leyendo código.
8. ~~`ios/Runner.xcodeproj/project.pbxproj` lo reescribe Flutter en cada build.~~
   — **DESMENTIDA por medición el 2026-08-13.** Un `flutter build ios --release`
   completo NO lo tocó: `git diff --stat` devolvió exactamente las 3 líneas
   agregadas a mano. Los fixes de build settings sobreviven a los builds de
   Flutter; no hace falta reaplicarlos.
9. **Los duplicados que YA existen no se limpian.** Medido el 2026-08-12 en el
   emulador: 24 documentos de más en 13 de 77 sesiones, **11.450 kg fantasma**.
   ⚠️ Corrección al texto anterior, que decía "falta decidir si va un backfill":
   **la decisión ya se tomó y el backfill ya está escrito** —
   `scripts/backfill_dedupe_setlogs.js`, ~400 líneas con respaldo, batch atómico
   por sesión, idempotencia y restore, commiteado el 2026-08-13. También corrige
   `totalVolumeKg`, que es lo único que leen rankings e insights. Lo que queda es
   **APLICARLO**, y a propósito todavía no se hizo: el propio script exige
   (`:76-92`) que primero salga la app con el fix preventivo y que el padrón
   actualice, porque correrlo antes vuelve a ensuciar todo.
   ~~⚠️ Riesgo vivo más grande que los 24 documentos: el script no tiene NI UN
   test.~~ — **CERRADO.** La DECISIÓN se extrajo a `scripts/lib/dedupe_setlogs_plan.js`
   (`planSesion`, puro, sin Firestore) y tiene **22 tests** en
   `scripts/test/dedupe_setlogs_plan.test.js` (`node:test`, sin dependencias
   nuevas; `npm test` desde `scripts/`). Cubren las cuatro salvaguardas, la
   idempotencia, quién sobrevive por `createTime`, el contrato `__timestamp__`
   con el restore, y el caso real `ZTjx8jVA6Ru5vCVLLy5x` (3850 en documentos,
   2200 reales, 1650 en el campo).
   El refactor está MEDIDO, no supuesto: original y refactorizado corridos con
   `--dry-run` contra el emulador sobre 100 sesiones dan **salida idéntica byte a
   byte**. Control negativo: desactivando las salvaguardas 1 y 2 se ponen rojos 4
   tests.

   ⚠️ **HALLAZGO NUEVO — decidir ANTES de correr `--apply`.** Escribiendo los
   tests apareció que la salvaguarda 1 **no cubre el ejemplo que ella misma
   documenta** cuando las series son idénticas. El reloj nunca renumera sus
   sombras, así que `press__2` sigue con `setNumber=2`, la numeración queda densa
   {1,2,3}, y `enConflicto` no ve nada porque los valores son iguales. Resultado
   medido: se borra la serie 3 REAL renumerada y sobrevive la serie que el atleta
   BORRÓ, con el volumen subiendo de 1000 a 1500.
   La salvaguarda 1 sí cubre la OTRA forma (cuando el renumerado es un id
   determinístico) y la 2 cubre el caso de valores distintos; el cruce queda
   afuera de las dos.
   **No se arregló a propósito**: desde el estado final de los documentos ese
   caso es indistinguible de uno legítimo (reloj escribió 4 series, teléfono 3 —
   que es la mayor parte del valor del script). Cerrarlo pide una señal nueva:
   `completedAt`, que en un duplicado real difiere 1-6 segundos (medido, §del
   ciclo) y acá difiere lo que tardó una serie entera. Es una decisión de
   política sobre un script que borra producción, no un bugfix.
   Queda fijado en el test `⚠️ renumeración CON series idénticas`, que hoy afirma
   la conducta actual y se pone rojo el día que alguien agregue la salvaguarda.
10. **El dedupe de escritura NO es atómico.** La secuencia `get` → (el reloj
    escribe) → `set` sigue siendo posible; lo que cambia es el TAMAÑO de la
    ventana, de 37 segundos medidos a un round-trip. Cerrarla del todo pide una
    transacción, que no se agregó porque `fake_cloud_firestore` resuelve
    `runTransaction` con un `_DummyTransaction` sin atomicidad ni reintento: la
    garantía quedaría afirmada y no medida.
11. **El cuelgue de `_buildResume` no se pudo reproducir a pedido** (tres
    intentos: arranque limpio, ciclo segundo plano→primer plano, seis toques
    seguidos). Se acotaron las lecturas para que colgarse deje de ser un estado
    posible, pero el disparador exacto sigue sin identificarse. Si vuelve a
    aparecer, ahora deja `TimeoutException` en vez de silencio.
12. **El reloj no tiene concepto de "plan completado".** Rota infinito, igual
    que Home. Es consistente con la decisión de §8.5, pero el atleta no recibe
    ninguna señal en la muñeca de que terminó el plan. Es una feature, no un bug.

---

## 9. Reglas del dueño

- **NUNCA `git add -A`.** Agregar por ruta explícita. Esa carpeta ya se filtró
  dos veces en commits ajenos.
- Nunca `Co-Authored-By` ni atribución de IA. Conventional commits.
- **No pushear** sin que lo pida.
- Sesión paralela en el worktree `wizardly-dijkstra-a16063` toca
  `lib/features/feed/**`, `lib/features/profile/**`, `firestore.rules`,
  `functions/src/**` y los ARB. **Avisar antes de tocar `pubspec.yaml` o ARBs.**
- **MEDÍ, no teorices.** Un test que pasa sin el fix no prueba nada:
  comprobar siempre que se ponga ROJO al remover el arreglo.
- Verificar corriendo antes de declarar algo listo. En esta sesión, cada vez
  que se declaró algo sin verlo correr, estaba mal.
