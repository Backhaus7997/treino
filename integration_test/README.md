# TREINO — E2E integration tests

Cinco suites end-to-end que manejan la `TreinoApp` **real** contra los
**emuladores de Firebase** locales: Firestore `8080`, Auth `9099`, Functions
`5001` y Storage `9199`. Corren en el **simulador de iOS** de la Mac (es donde
se verificaron, la última vez el 2026-11-02) y deberían correr igual en un AVD
de Android, que hoy no hay ninguno creado en la máquina.

> ⚠️ **Sin nube.** `initFirebaseForEmulators()` llama a
> `conectarEmuladores()` —la misma función que usa `main.dart` con
> `USE_EMULATOR=true`— y conecta los cuatro servicios emulados. Lo que no tiene
> emulador lo apaga `pumpTreinoApp`: Analytics va con un no-op y no se registra
> el token de FCM. Hasta el 2026-11-02 el helper conectaba solamente Auth y
> Firestore: las callables, Storage, los eventos de Analytics y el token de FCM
> de una suite salían al proyecto real, que es **producción** (ver `AGENTS.md`,
> § Entornos).

## Suites

| Archivo | Flujo |
|---|---|
| `login_to_home_test.dart` | login → `/home` |
| `register_to_home_test.dart` | registro → profile-setup (5 pasos) → código del mail → `/home` |
| `workout_session_flow_test.dart` | sesión nueva → confirmar una serie → terminar → resumen |
| `coach_athlete_chat_test.dart` | chat 1-1 alumno ↔ PF |
| `my_routine_edit_test.dart` | editar una rutina propia, guardar y releerla |
| `support/e2e_helpers.dart` | bootstrap + helpers de manejo (no es una suite) |
| `support/emulator_admin.dart` | lectura/escritura del emulador salteando las reglas (no es una suite) |
| `support/seed_ids.dart` | **generado** desde `scripts/lib/e2e_seed_contract.js` (no editar a mano) |

El paquete `integration_test` ya está en `dev_dependencies` de `pubspec.yaml`.

## Correrlas

**1. Emuladores, completos** (con Functions: el registro le pide el código de
verificación a una callable). El script fija `--project treino-dev`, el
namespace donde siembra el seed, y cierra Secret Manager y la credencial de las
Functions — no lo reemplaces por un `firebase emulators:start` a mano:

```bash
./scripts/emulator.sh
```

Los puertos están fijos en el código (`lib/core/firebase/emuladores.dart`). Si
el `8080` ya está ocupado suele ser el emulador de otra sesión: no lo mates.

**2. Seed** (en otra terminal; con los emuladores arriba):

```bash
npm --prefix scripts run seed:emulator
```

**3. Las suites**, contra el simulador (iOS) o el AVD (Android) booteado. Una
por vez es lo más legible; el primer build de iOS tarda ~15 min y los
siguientes ~1 min:

```bash
# iOS
flutter test integration_test/login_to_home_test.dart -d <udid-del-simulador> --dart-define=USE_EMULATOR=true
# Android: el flavor es obligatorio (hay dos, `phone` y `wear`)
flutter test integration_test/login_to_home_test.dart -d <id-del-avd> --flavor phone --dart-define=USE_EMULATOR=true
```

o todas juntas:

```bash
# iOS
flutter test integration_test/ -d <udid-del-simulador> --dart-define=USE_EMULATOR=true
# Android
flutter test integration_test/ -d <id-del-avd> --flavor phone --dart-define=USE_EMULATOR=true
```

Sin `--flavor phone` el build de Android no compila: `android/app/build.gradle.kts`
declara los flavors `phone` y `wear` y no hay uno por defecto. En iOS el flag NO
va: el proyecto sólo tiene el esquema `Runner`.

El UDID sale de `xcrun simctl list devices booted`; el id del AVD, de
`flutter devices`.

## Qué asume cada suite del entorno

- **Las cuentas y documentos sembrados** de `support/seed_ids.dart`. Las suites
  no declaran ids propios: un mail plausible que no corresponde a ningún usuario
  sembrado falla en el login hablando de credenciales, no de fixture.
- **El tour de onboarding** aparece encima de Inicio la primera vez que una
  cuenta con el perfil completo entra a la app. `signInViaUi` lo cierra con
  SALTAR, que lo marca visto: desde la segunda corrida contra el mismo emulador
  ya no aparece.
- **Ninguna sesión de entreno activa.** Con una, Inicio abre "Entrenamiento en
  curso" encima de lo que haya, tarde y sin poder cerrarse tocando afuera. Las
  suites de Martín la cierran antes del login con `closeActiveSessionsOf`
  (`support/emulator_admin.dart`), y NO tocando DESCARTAR en el modal, que hace
  dos `pop` y se lleva la página de abajo (bug de la app, reportado aparte).
- **El player se abre desde la pestaña Entrenar y con `push`**, como en la app.
  Empujado desde Inicio, Inicio sigue siendo la ruta actual de su navigator (el
  del `ShellRoute`) y su listener abre el modal de sesión en curso sobre la
  sesión que el player acaba de crear.
- **El registro prende el gate del mail** (`app_config/email_gate`) para la
  corrida y lo deja como estaba al terminar. El código lo recupera del hash que
  guarda el backend en `verificaciones_de_mail` (6 dígitos: prueba el millón),
  con `support/emulator_admin.dart`, que usa el `Bearer owner` del emulador para
  saltear las reglas. Ese token sólo existe en el emulador. No lo lee de
  `mail_queue`: `sendQueuedMail` borra el código de ahí apenas intenta mandar,
  y leerlo era una carrera contra el trigger.
- **Las suites dejan datos**: un mensaje en el chat de Coach, una sesión
  terminada de Martín, el nombre del día de su rutina propia cambiado y una
  cuenta nueva por cada registro. Están escritas para correr de nuevo sin
  re-sembrar (los textos llevan un nonce), y un `seed:emulator` deja todo como
  al principio.

## Notas

- **No uses `simctl launch` sobre la app que dejan instalada**: rompe las apps
  Flutter en debug y falla al leer datos, con cara de bug de reglas.
- **`pumpAndSettle` no sirve en el player de la sesión**: tiene un timer que
  corre siempre y el test cuelga hasta el timeout (medido: 10 min 25 s). Ahí van
  `pumpFor` / `pumpUntilFound` de `support/e2e_helpers.dart`, y `goTo(...,
  settle: false)`.
- **Los finders leen el copy del `.arb`** (`l10nOf(tester)`) siempre que la
  app lo saca de ahí: el día que "Iniciar sesión" pasó a "INICIAR SESIÓN" se
  cayeron todas las suites que loguean, sin que el login tuviera nada roto. Los
  textos que la app escribe a mano ("TERMINAR SESIÓN", "OTRO GYM / SIN GYM",
  los pasos del profile-setup) van como literales, con un comentario que lo dice.
- **Un build de iOS ocupa varios GB** (DerivedData + `build/`). Mirá
  `df -h /System/Volumes/Data` antes de culpar a un error de compilación raro.
- CI no corre estas suites: necesitan un simulador y los emuladores.
