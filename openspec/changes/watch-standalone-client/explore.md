# Exploration: watch-standalone-client

**Change**: watch-standalone-client
**Owner**: Backhaus
**Date**: 2026-08-04
**Supersede**: `openspec/changes/watch-connectivity/` (explore/proposal/spec/design)
**Fase**: Sin asignar — capability nueva, fuera del roadmap actual
**Artifact store**: openspec

---

## Por qué existe este change

El ciclo `watch-connectivity` está construido sobre un modelo **"el teléfono manda, el reloj espeja"**: un bridge `watch_connectivity` que empuja un DTO chico a la muñeca y recibe dos acciones puntuales. Al revisar sus Locked Decisions con el dueño (que su propio `state.yaml` pedía revisar, porque eran un borrador sin validar), quedó claro que el producto pedido es otro:

> "poder iniciar un entrenamiento, ir marcando los datos de pesos y repes y marcando ejercicios finalizados hasta marcar como finalizado el entrenamiento, viendo un resumen final […] que la app en el reloj pueda funcionar sin tener la aplicación abierta o controlando de fondo o directamente con el celu cerca […] siempre y cuando se maneje bien lo del historial, que independientemente si es del reloj o del celular, siempre se guarde historial y registros bien"

Eso es un **cliente autónomo**, no un companion. El plan anterior no sirve de base: no le falta un pedazo, parte de una premisa distinta.

---

## Correcciones al ciclo anterior (verificadas contra el código)

El ciclo `watch-connectivity` fue armado en una sesión sin acceso al repo local. Cuatro de sus afirmaciones no resisten verificación:

| Afirmación del plan viejo | Realidad verificada |
|---|---|
| Locked Decision #3: "iniciar sesión implica seleccionar rutina/día, UI que no tiene sentido en 40mm" | **Falso.** `lib/features/home/application/todays_routine_provider.dart` ya resuelve el entreno de hoy solo (`nextDayNumber = (lastDayNumber % numDays) + 1`, rota Día 5 → Día 1). Es lo que alimenta la card "HOY". Iniciar es un botón, no un picker. |
| Hard constraint #5: acciones v1 = `logSet` + `completeSet` | **`completeSet()` no existe** en `SessionNotifier`. Los métodos reales son `logSet`, `addSet`, `updateSet`, `removeSet`, `retryLastLogError`, `abandonSession`, `finishSession`. |
| ADR-WC-005: `sessionNotifier.logSet(reps, weight)` | Firma real: `Future<void> logSet(SetLog setLog)`. `SetLog` exige `id, exerciseId, exerciseName, setNumber, reps, weightKg, completedAt`. El `WatchSessionDto` bloqueado en 7 campos **no incluye `exerciseId`** → no se podía construir un `SetLog` válido ni deduplicar. |
| ADR-WC-002: stream `incomingMessages` | Nombre real del paquete: `messageStream` (y `contextStream` para contexto). |
| Proposal §1: "`pubspec.yaml` declara el producto iOS-only, mobile-only" | La frase existe (`pubspec.yaml:80`) pero es un comentario sobre la config de `flutter_launcher_icons`. El `description` del pubspec dice "multiplataforma", y existen `android/` y `web/`. |

Además, `ref.listen(sessionNotifierProvider, ...)` del design no compila: es `AutoDisposeFamilyAsyncNotifier<SessionState, SessionInit>`, se usa siempre como `sessionNotifierProvider(init)`.

---

## Current State

### Autenticación

- TREINO autentica con **Google Sign-In** (`google_sign_in: ^7.1.0`) y **Sign in with Apple** (`sign_in_with_apple: ^7.0.1`). No hay email/password como camino primario.
- Sign in with Apple funciona nativo en watchOS. **Google Sign-In no tiene SDK de watchOS** → un usuario de Google no puede autenticarse en el reloj por su cuenta.

### Datos

- Toda la persistencia es Firestore. `lib/features/workout/data/session_repository.dart` expone `create({uid, routineId, routineName, startedAt, …})` y `finish({uid, sessionId, finishedAt, totalVolumeKg, durationMin, wasFullyCompleted})`.
- `firestore.rules` protege el acceso por uid.

### Lógica de sesión (lo que el reloj tendría que replicar)

- `SessionNotifier` es `AutoDisposeFamilyAsyncNotifier<SessionState, SessionInit>` — **atado a que `session_player_screen` esté montada**. Si la pantalla no está, el notifier se dispone y la sesión se muere.
- `SessionInit` es sealed: `FreshSession({routineId, dayNumber, weekNumber})` y `ResumeSession({sessionId})`.
- `SessionState` = `{session, day, setLogs, currentExerciseIndex, elapsedSeconds, setCountOverride}` + getters derivados (`activeWeek`, `totalVolumeKg`, `durationMin`, `isFullyCompleted`, resolución de sets por semana).
- `logSet` es idempotente por **identidad lógica `exerciseId + setNumber`** (session_notifier.dart:215) — la clave de cualquier reconciliación futura.
- `finishSession()` **tira `StateError` si `isFullyCompleted` es false** (session_notifier.dart:493).
- `setCountOverride` es un override ABSOLUTO por ejercicio (nunca delta), poblado solo por `addSet`/`removeSet`.

### Tamaño medido

| | líneas (sin generados) |
|---|---|
| `lib/features/workout/` completo | 24.986 |
| `domain` + `application` + `data` (la lógica, sin UI) | **5.701** |
| `test/features/workout/` | **34.311** |

---

## Restricciones de plataforma (verificadas)

1. **Firebase en watchOS es community-supported, no oficial.** Auth ✅, Storage ✅, Crashlytics ✅, Analytics ✅ (watchOS 8+). **Firestore ❌ — no figura en la lista de productos soportados.**
2. **La REST API de Firestore acepta ID tokens de Firebase Auth como `Authorization: Bearer {token}`, y las Security Rules SE APLICAN** a esas requests. O sea `firestore.rules` cubre al reloj sin modelo de auth paralelo.
3. La REST API **no da** persistencia offline ni listeners en tiempo real. Ambos hay que construirlos del lado del reloj.
4. watchOS 6+ soporta apps independientes con almacenamiento y red propios (WiFi/LTE) — la premisa de autonomía es correcta.

---

## Approach Options

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **A — Cliente autónomo Swift + Firestore REST (ELEGIDO)** | Autonomía real: el reloj funciona con el celular guardado o ausente. Las Security Rules siguen valiendo. | Reimplementar la lógica de sesión en Swift. Persistencia offline y reconciliación propias. Dos implementaciones de las mismas reglas que van a divergir si no se controla. | **Alto** — segundo cliente |
| B — Buffer local + reconciliación por el teléfono | Autonomía de INPUT sin Firestore en el reloj ni segundo cliente. Reusa la idempotencia existente. | El historial llega recién cuando el reloj reencuentra al teléfono. Reloj perdido antes de sincronizar = entreno perdido. | Medio |
| C — Control remoto (el plan `watch-connectivity`) | Barato, reusa todo. | Exige el teléfono a mano con la app viva. **No es lo pedido.** | Bajo |

**Elegido: A**, por decisión explícita del dueño tras exponerle el costo (segundo cliente, ~5.700 líneas de lógica a portar, 34k de tests que no se transfieren).

---

## Riesgos

1. **Divergencia entre las dos implementaciones.** Es EL riesgo estructural de esta arquitectura: las reglas de negocio (idempotencia, `setCountOverride`, resolución de semana, `isFullyCompleted`) van a vivir en Dart y en Swift. Cuando una cambie y la otra no, el historial del usuario se corrompe silenciosamente. Mitigación propuesta: **fixtures de conformidad compartidos** — los mismos escenarios en JSON corridos contra ambas implementaciones en CI.
2. **Auth de usuarios de Google.** Google Sign-In no corre en watchOS. Requiere que el teléfono entregue la credencial al reloj al menos una vez.
3. **Sin persistencia offline de Firestore.** Hay que construir la cola local, el reintento y la resolución de conflictos a mano en Swift.
4. **`firestore.rules` no está testeada contra escrituras REST.** Las reglas se aplican, pero nadie verificó que las escrituras que haría el reloj pasen. Riesgo del patrón ya conocido en este repo: reglas testeadas pero no desplegadas, fallando mudas.
5. **Escala del workstream.** No es una feature de 2 PRs; es un cliente. Necesita fases con corte de riesgo, no un big bang.
6. **Firestore en watchOS es community-supported aun para lo que sí soporta** (Auth). Un cambio upstream puede romper sin SLA de Google.
7. **Gamificación colándose** en una superficie nueva y tentadora (Retos/Missions/Bets siguen prohibidos en todo el producto).

---

## Open Questions for Proposal

1. **Handoff de credencial**: ¿el teléfono entrega el refresh token al reloj vía WatchConnectivity (una vez, en el pairing), o el reloj exige su propio Sign in with Apple y los usuarios de Google quedan sin reloj?
2. **Alcance de la lógica portada**: ¿el reloj replica TODA la resolución de series (incluido `setCountOverride` y semanas), o v1 se limita a rutinas de una semana sin edición de series en vivo?
3. **Estrategia de conflicto**: si el mismo entreno se toca desde los dos lados, ¿quién gana? La idempotencia por `exerciseId + setNumber` da dedupe, no merge.
4. **Fixtures de conformidad**: ¿entran en la fase 1 (caros pero atajan el riesgo #1 desde el principio) o se difieren?
5. **`finishSession` y `isFullyCompleted`**: ¿el reloj puede finalizar un entreno incompleto, o replica el `StateError`?

---

## Ready for Proposal

**SÍ**, con la advertencia de escala: este change describe un segundo cliente. El proposal tiene que fasear por corte de riesgo (lo más riesgoso primero: auth + una escritura REST autenticada que pruebe que las rules dejan pasar), no por capas.

---

## Artifacts

- File: `openspec/changes/watch-standalone-client/explore.md`
- Supersede: `openspec/changes/watch-connectivity/` (se conserva intacto como registro)
