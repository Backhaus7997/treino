# Traspaso — companion de Wear OS

Documento para retomar el trabajo en una sesión nueva sin perder contexto.
Escrito el 2026-08-13, sobre la rama `feat/wearos-companion`
(20 commits sobre `519b0318`, **nada pusheado**).

Worktree: `/Users/martinbackhaus/treino/.claude/worktrees/wearos-companion`

> Leé **`AGENTS.md`** primero. Y si venís del lado Apple, leé también
> `openspec/changes/watch-standalone-client/HANDOFF.md` — pero ojo, porque
> buena parte de ese diseño **NO aplica acá**. Ver §1.

---

## 1. La idea central: esto NO es un port

Toda la arquitectura del companion de Apple existe para esquivar **una**
limitación: **Firestore no tiene SDK para watchOS**. De ahí salió el cliente
REST a mano (`FirestoreREST.swift`), la ausencia total de listeners, la máquina
de avisos por WatchConnectivity (`WatchNudgeService`), `RoutineCatalog.swift`
reimplementando las queries en Swift, y los fixtures de `conformance/` para que
las reglas escritas dos veces no diverjan.

**Wear OS es Android: el SDK de Firebase anda.** Eso se verificó CORRIENDO, no
se asumió (§2). Consecuencias:

- **No hacen falta los avisos.** Los listeners empujan solos. Todo el mecanismo
  de `externalRefresh` y el `refreshToken` que watchOS usa para releer al
  cambiar de página **no tiene razón de existir acá**.
- **No hay que reimplementar reglas en otro lenguaje**, así que no se reproduce
  la familia de bugs "el contrato cubre la decisión pero no las entradas" que
  costó cuatro incidentes en el ciclo de Apple.
- **Un solo target de conformidad**, no un tercero.

---

## 2. Lo que está MEDIDO (no asumido)

Todo esto se verificó corriendo en un **Samsung SM-L500, Wear OS 6 /
Android 16 / API 36, ARM 32 bits, 438 px @ 340 dpi = 206 dp de diámetro**.

| Premisa | Resultado |
|---|---|
| Firestore con listeners en el reloj | Push mediana **206 ms**, `fromCache=false` |
| Reuso del dominio Dart sin tocarlo | **22/22** casos de `conformance/`, `git diff` vacío |
| Supervivencia durante el entreno | **100.0%** de cobertura con FGS vs **22.6%** sin |
| Alerta del descanso | **8 ms** de error con pantalla apagada, y se sintió |
| Health Services | Pulso y calorías reales en pantalla |

### ⚠️ EL EMULADOR MIENTE

Es la lección más cara de este ciclo. En el emulador de Wear OS **la app
sobrevivía todo**: `frozen 0`, `suspend 0`, cobertura perfecta en las tres
condiciones probadas. En el reloj físico, el mismo control rojo perdió el 78%
del tiempo despierto y hubo una ventana de **casi 6 minutos** sin ejecutar una
línea, con el proceso vivo.

**El emulador no hace suspend-to-RAM.** Un verde ahí es verde falso por
construcción. Cualquier medición de supervivencia, batería o alarmas **exige
hardware**. Runbook completo en `docs/wearos-medicion-hardware.md`.

---

## 3. Arquitectura, archivo por archivo

### Kotlin — `android/app/src/wear/kotlin/com/treino/app/`

| Archivo | Qué hace |
|---|---|
| `MainActivity.kt` | Registra el plugin, pide permisos, y **captura la corona rotatoria** |
| `workout/WorkoutForegroundService.kt` | FGS tipo `health`. **Es lo que mantiene vivo el proceso.** |
| `workout/ExerciseSessionController.kt` | Única clase que toca `androidx.health`. Pulso y calorías. |
| `workout/RestDeadline.kt` | Lógica PURA del descanso. Sin Android. Testeable en JVM. |
| `workout/RestStore.kt` | Persiste el deadline. Detecta reboot. |
| `workout/RestAlarm.kt` | La alarma + el wakelock acotado + la vibración. |
| `workout/WearWorkoutPlugin.kt` | MethodChannel. **Emite deadlines, nunca cuentas regresivas.** |

`src/phone/kotlin/.../MainActivity.kt` es una `FlutterActivity` pelada: el
teléfono no carga nada de esto.

### Dart

| Archivo | Qué hace |
|---|---|
| `lib/main_wear.dart` | Entrypoint. **Corre con DATOS DE MUESTRA** (ver §6). |
| `features/watch/data/wear_workout_service.dart` | Puente al canal nativo |
| `features/watch/application/wear_rest_providers.dart` | Riverpod: descanso y esfuerzo |
| `presentation/wear/wear_root.dart` | Máquina de estados del emparejamiento |
| `presentation/wear/wear_home.dart` | HOY → PLANES → PLANTILLAS |
| `presentation/wear/wear_pager.dart` | Paginado + salida implementada a mano |
| `presentation/wear/wear_round_scaffold.dart` | **Geometría de pantalla redonda** |
| `presentation/wear/wear_rotary.dart` | **La corona** |
| `presentation/wear/wear_today_page.dart` | Vista previa del entreno |
| `presentation/wear/wear_routine_list.dart` | Listas + detalle (Empezar / Activar) |
| `presentation/wear/wear_workout_screen.dart` | La pantalla de entreno |
| `presentation/wear/wear_set_format.dart` | Puerto exacto de `WorkoutView.describe` |

---

## 4. Las trampas que costaron tiempo — leer antes de tocar nada

### 4.1 El emulador da verde falso

Ver §2. **No declares nada verde sin hardware.**

### 4.2 Dos permisos donde la documentación miente

Los dos se descubrieron midiendo, contra lo que dice la doc:

1. **`BODY_SENSORS` vs `android.permission.health.READ_HEART_RATE`**: la doc
   dice que el corte depende del `targetSdkVersion` de la APP. **Falso**: con
   target 35 sobre un reloj API 36, `startExercise` tiró
   `SecurityException: Missing permissions: [READ_HEART_RATE]`. **Manda la
   versión del DISPOSITIVO.** Se declaran los dos y se pide por
   `Build.VERSION.SDK_INT`.

2. **`ACTIVITY_RECOGNITION` es obligatorio, y su ausencia ENGAÑA**: sin él
   `startExercise` falla, **pero el pulso se ve igual en pantalla** porque lo
   entrega `prepareExercise` (el calentamiento), que sólo pide el permiso de HR.
   Faltan las calorías y el tracking real.
   **Regla: "se ve el pulso" NO prueba que el ejercicio arrancó.** Buscá
   `ejercicio arrancado` en el log.

### 4.3 Doze difiere las alarmas 21 minutos

`setExact` fue corrida **+21m10s** por `device_idle`. El diagnóstico está en
`adb shell dumpsys alarm`: la línea `policyWhenElapsed:` **nombra a la política
responsable**. Es EL comando para cualquier problema de alarmas.

- `setExactAndAllowWhileIdle` dispara en Doze pero con **cuota de 1 cada 9
  minutos** — inservible para descansos de 60-90 s.
- La variante con `OnAlarmListener` (la que no pide permiso) **recién existe en
  Android 17**.

**La salida**: un wakelock parcial ACOTADO al descanso. Doze ignora los
wakelocks, así que esto no "arregla" la alarma — mantiene despierto el SoC, y
**sin suspensión el dispositivo no entra en Doze**, y sin Doze la alarma dispara
puntual. Así se evita pedir `USE_EXACT_ALARM` (riesgo de política de Play) y
`SCHEDULE_EXACT_ALARM` (fricción de UX).

### 4.4 Flutter descarta los eventos de la corona

`AndroidTouchProcessor.onGenericMotionEvent` exige `SOURCE_CLASS_POINTER` y el
rotary es `SOURCE_CLASS_NONE`. **Cero menciones de `SOURCE_ROTARY_ENCODER` en
todo flutter/flutter**; el issue está abierto desde 2016. No lo arregla una
actualización: hay que capturarlos en `MainActivity.onGenericMotionEvent`.

Y **la corona tiene que alimentar `ScrollPosition.drag()`**, no `jumpTo`.
`jumpTo` saltea la física entera: sin fricción, sin inercia, sin fling. Se
intentó suavizar con interpolación, ticker y refuerzo por velocidad — y el dueño
lo siguió viendo como "bloques con cortes". **Ningún suavizado sobre `jumpTo`
produce inercia, porque la inercia no está.**

### 4.5 En Wear OS el swipe izquierda→derecha cierra la app

Y **desde cualquier punto de la pantalla**, no desde un borde. Un pager
horizontal compite contra el gesto de salida en el 100% de la superficie.

Solución adoptada (idea del dueño): **HOY primero, todo lo demás hacia la
derecha**. Avanzar usa el dedo de derecha a izquierda, que es la dirección
libre. Se apagó `windowSwipeToDismiss` en el tema del flavor `wear`, así que
**la salida es responsabilidad nuestra** — está en `wear_pager.dart`, por
overscroll en la primera página.

### 4.6 La pantalla redonda no se resuelve con un cuadrado

El cuadrado inscripto desperdicia el **36% del área**. Los márgenes correctos
son **5.2% lateral** y **12-36% vertical según el TIPO del primer y último
ítem** (constantes reales de `ScalingLazyColumnDefaults` de Horologist,
codificadas en `WearItemType`).

El vertical va como `padding` de la LISTA, no del andamio: en el contenedor
recortaría el viewport en vez de correr el scroll.

**No usar `ShaderMask` para el desvanecido de bordes**: fuerza un `saveLayer`
por frame y con tres páginas vivas traba la app en un reloj de 32 bits.

### 4.7 Áreas táctiles: el problema es el TAMAÑO, no el `HitTestBehavior`

Costó dos bugs opuestos:
- `opaque` sobre la **pantalla entera** se dispara solo — el log mostró
  `startRest → cancelRest → startRest` con un segundo entre medio.
- `deferToChild` sobre una fila con un `Spacer` deja un **agujero en el medio**
  donde el toque no registra.

`opaque` sobre un área ACOTADA de 48 dp mínimo.

### 4.8 Probá en PROFILE, no en debug

Debug es JIT sin optimizaciones. En un reloj ARM de 32 bits eso solo explica
buena parte de cualquier lentitud percibida.

```bash
flutter build apk --profile --flavor wear -t lib/main_wear.dart
```

### 4.9 Reglas de producto portadas de watchOS — NO cambiarlas sin preguntar

- **Sólo la primera serie sin marcar es tocable.** Sin eso se marcaba la 3 sin
  la 2 y quedaba un hueco: el historial mostraba series salteadas.
- **"Terminar" sólo con TODAS las series de TODOS los ejercicios.** Pedido del
  dueño: tenerlo a la vista invita a cerrar el entreno de más.
- **«Activar» SÓLO sobre planes, nunca sobre plantillas.**
  `resolveActiveRoutineId` busca el marcador dentro de las listas de asignadas y
  auto-creadas: escribir el id de una plantilla es una escritura que sale bien y
  **no hace nada**.
- **Si no hay pulso ni calorías NO se dibuja fila, ni vacía. Y nunca un guion ni
  un cero.** Una lectura negada por el atleta es indistinguible de "todavía no
  hay datos", así que cualquier texto sería adivinar.
- **La semana sólo se muestra en planes periodizados.**

---

## 5. Cómo correr todo

```bash
# emuladores de Firebase (para cuando se cablee la sesión real)
firebase emulators:start --only firestore,auth,functions

# emparejar el reloj (Wi-Fi debugging; los relojes no tienen USB de datos)
adb pair <IP>:<PUERTO_EMPAREJAMIENTO>     # código de 6 dígitos en el reloj
adb connect <IP>:<PUERTO_CONEXION>
# si se cae: `adb mdns services` muestra el puerto nuevo. El pairing sobrevive.

# construir e instalar
flutter build apk --profile --flavor wear -t lib/main_wear.dart
adb -s <reloj> install -r -t build/app/outputs/flutter-apk/app-wear-profile.apk

# permisos por adb (evita depender del diálogo en la muñeca)
adb -s <reloj> shell pm grant com.treino.app android.permission.health.READ_HEART_RATE
adb -s <reloj> shell pm grant com.treino.app android.permission.ACTIVITY_RECOGNITION

# diagnóstico
adb -s <reloj> logcat -d -s TreinoFGS TreinoExercise TreinoRestAlarm flutter
adb -s <reloj> shell dumpsys activity services com.treino.app | rg "startForegroundCount|isForeground"
adb -s <reloj> shell dumpsys alarm | rg -A4 "treino.rest"
```

**El reloj tiene bloqueo por patrón.** Los taps automatizados van a la pantalla
de desbloqueo si está trabado — pedirle al dueño que lo desbloquee antes de
cualquier prueba por adb.

---

## 6. Estado: qué está hecho y qué NO

### Verificado corriendo en hardware
- Firestore con listeners, dominio reusado, FGS, alerta del descanso,
  Health Services, y toda la UI navegable con corona.

### Implementado pero con datos de MUESTRA
- **`lib/main_wear.dart` corre con un entreno y rutinas hardcodeados.** La UI
  está completa y es navegable, pero **no hay nada conectado a Firestore**.

### NO hecho — es el próximo bloque grande
1. **Cablear la sesión REAL.** La cadena entera: credencial minteada por el
   teléfono (`functions/src/mint-watch-credential.ts`) → handoff por **Data
   Layer API** (no WatchConnectivity) → Firestore con listeners → resolución del
   entreno del día → escritura del historial. **Acá es donde el reuso del
   dominio empieza a pagar.**
2. **Probar de punta a punta con un teléfono.** Pedido explícito del dueño.
3. El descanso son **90 s fijos**; tiene que salir del `SetSpec` de la rutina.
4. Pantalla **"instalá TREINO en tu teléfono"**: requisito de plataforma para
   apps no-standalone.

### Sin verificar
- **La alarma desde Doze PROFUNDO.** Lo medido es n=1 con un confound: en la
  corrida que falló el reloj venía de mucho rato quieto; en la que funcionó,
  recién despertado. El control es dejarlo quieto 10-15 min y recién ahí
  arrancar el descanso.
- **Destrucción de la Activity.** El gesto de volver la dejó en `STOPPED`, no
  destruida. Si el sistema la destruye, `flutterEngine.destroy()` se lleva el
  isolate y el FGS **no lo protege** — protege el proceso, no el engine. No hay
  `FlutterEngineCache`.
- Que `isPaired` de `watch_connectivity` sirva en Android: la doc dice que ahí
  NO puede saber si hay reloj emparejado, sólo si están instaladas las apps de
  Wear OS / Galaxy Wearable.

---

## 7. Deuda conocida

1. **Los textos viven en `WearStrings` (constantes), no en los ARB.** La regla 3
   del design system lo admite, pero al pasar a producto tienen que mudarse.
   **No se tocaron los ARB a pedido del dueño.**
2. **`lib/main_wear_spike.dart` y `lib/main_wear_liveness_spike.dart` son
   THROWAWAY.** Instrumentos de diagnóstico, no producto. Borrarlos cuando el
   ciclo cierre.
3. **`android/key.properties` no existe en esta máquina**, así que el build de
   release cae a debug keys. Para el Data Layer alcanza (mismo debug keystore),
   pero para Play es bloqueante.
4. El `targetSdk` es 35. Wear OS 6 / API 36 cambia el always-on (Global AOD) y
   el permiso de HR. Deuda consciente.
5. `health-services-client` está en `1.0.0` (última estable). La última
   publicada es `1.1.0-rc02`, sin evaluar.

---

## 8. Antes del PR

- **4828 líneas** contra `519b0318`. La regla de la casa corta en **400** →
  PRs encadenados o `size:exception` aprobado.
- **`docs/wearos-medicion-hardware.md` es archivo nuevo en `docs/`**, y por
  `AGENTS.md` §8 el reviewer tiene que aprobar explícitamente.
- Gate: `flutter analyze` 0 issues · `dart format .` · tests verdes.

---

## 9. Reglas del dueño

- **NUNCA `git add -A`.** Agregar por ruta explícita.
- Nunca `Co-Authored-By` ni atribución de IA. Conventional commits.
- **No pushear** sin que lo pida.
- **Avisar antes de tocar `pubspec.yaml` o los ARB.**
- **MEDÍ, no teorices.** Un test que pasa sin el fix no prueba nada. En este
  ciclo, cada vez que se declaró algo sin verlo correr en hardware, estaba mal.
