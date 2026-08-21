# Design: watch-connectivity

**Change**: watch-connectivity
**Proposal ref**: `openspec/changes/watch-connectivity/proposal.md`
**Spec ref**: `openspec/changes/watch-connectivity/spec.md`
**ADR range**: ADR-WC-001 … ADR-WC-009

---

## 1. Scope Summary

Reflejar la sesión activa de `SessionNotifier` en un Apple Watch companion vía `watch_connectivity`, y loguear series desde el reloj. Feature nuevo standalone `lib/features/watch/`. PR#1: bridge + DTO + providers + tests, sin UI, sin dependencia de un target watchOS real (todo mockeable). PR#2: chip UI + wiring en `session_player_screen.dart` + doc del prerequisito nativo. Wear OS: superficie del paquete presente pero deliberadamente inerte en v1.

---

## 2. Architecture Overview

### Flujo teléfono → reloj (contexto)

```
SessionNotifier (Riverpod)
     │ ref.listen
     ▼
watchBridgeLifecycleProvider
     │ construye WatchSessionDto, compara con el último enviado
     ▼
WatchBridgeService.sendContext(dto)
     │ dto.toJson()
     ▼
WatchConnectivity(pkg).updateApplicationContext(json)
     │ (best-effort, se pisa, no requiere reachability inmediata)
     ▼
   watchOS app (Swift) — WCSession.didReceiveApplicationContext
```

### Flujo reloj → teléfono (acciones)

```
watchOS app — WCSession.sendMessage({"action": "logSet", "reps":.., "weight":..})
     │
     ▼
WatchConnectivity(pkg).incomingMessages (nombre exacto a confirmar contra el API real)
     │
     ▼
WatchBridgeService (parsea el Map entrante)
     │
     ▼
watchBridgeLifecycleProvider despacha:
     ├── "logSet"       → sessionNotifier.logSet(reps, weight)
     ├── "completeSet"  → sessionNotifier.completeSet()
     └── desconocida    → log + no-op (REQ-WC-BRIDGE-005)
```

### Estado de conexión (UI)

```
WatchBridgeService.isPaired / isReachable (streams)
     │
     ▼
watchConnectionStateProvider (derivado)
     │
     ▼
WatchConnectionChip  (montado en session_player_screen.dart, solo si hay sesión activa)
```

---

## 3. Architecture Decision Records (ADRs)

### ADR-WC-001 — `WatchSessionDto` — 7 campos, sin el `Session` completo

**Contexto**: REQ-WC-DATA-001 fija el shape. `updateApplicationContext` no está pensado para blobs grandes ni objetos con campos irrelevantes para una pantalla de 40mm.

**Decisión**: `WatchSessionDto` freezed con `sessionId, exerciseName, setIndex, totalSets, targetReps, targetWeight, restSecondsRemaining`. Construido a mano desde `SessionState` en el listener, no vía `Session.toJson()` directo.

**Consecuencias**: cambios futuros al modelo `Session` (freezed) no rompen automáticamente el contrato del reloj — hay un mapeo explícito de traducción en un solo lugar (`watch_bridge_providers.dart`), fácil de mantener sincronizado en review.

**Status**: ACCEPTED

---

### ADR-WC-002 — Transporte dual: `updateApplicationContext` + `sendMessage`

**Contexto**: Proposal Locked Decision #4. El paquete `watch_connectivity` expone ambos mecanismos de `WatchConnectivity`/`WCSession` bajo una superficie Dart (nombres exactos de los métodos a confirmar contra la versión instalada al momento de implementar — este design asume la superficie pública típica de este tipo de paquete: algo como `updateApplicationContext(Map)`, `sendMessage(Map)`, streams para contexto/mensajes entrantes, `isPaired`, `isReachable`).

**Decisión**:
- Teléfono → reloj (estado "current"): `updateApplicationContext`. No requiere reachability inmediata — el reloj lo recibe la próxima vez que esté disponible.
- Reloj → teléfono (acciones puntuales `logSet`/`completeSet`): `sendMessage`, que sí requiere reachability y da la posibilidad de ack/error inmediato del lado nativo.

**Consecuencias**: si el reloj manda un `logSet` mientras el teléfono está inalcanzable (poco común, pero posible), el mensaje falla en el lado nativo — v1 no implementa cola de reintento; se documenta como limitación conocida, no bloqueante.

**Status**: ACCEPTED

---

### ADR-WC-003 — Wiring vía `Provider` + `ref.listen`, mismo patrón que `FcmService`/`fcmLifecycleProvider`

**Contexto**: `push-notifications-fcm` (ADR-PN-003) ya estableció el precedente para este tipo de servicio delgado + lifecycle provider en este codebase — no hay motivo para inventar un patrón distinto.

**Decisión**:
- `WatchBridgeService` — clase plana con `sendContext(dto)`, `Stream<Map<String,dynamic>> get incomingMessages`, `Stream<bool> get isReachable`, `Stream<bool> get isPaired`. Envuelve la instancia del paquete.
- `watchBridgeServiceProvider` — `Provider<WatchBridgeService>` la construye una vez.
- `watchBridgeLifecycleProvider` — `Provider<void>` que hace `ref.listen(sessionNotifierProvider, ...)` (envía contexto en transiciones relevantes) y se subscribe a `incomingMessages` (despacha acciones). Se lee desde `session_player_screen.dart` (ver ADR-WC-004), NO desde `app.dart` como hace FCM.

**Alternativas rechazadas**: wiring eager en `app.dart` — rechazado porque el bridge solo tiene sentido mientras hay una sesión activa/pantalla de entreno abierta; mantenerlo vivo para toda la vida de la app desperdicia batería reenviando estado vacío.

**Status**: ACCEPTED

---

### ADR-WC-004 — Lifecycle atado a `session_player_screen.dart`, no a `app.dart`

**Contexto**: Spec open question #1. A diferencia de FCM (necesita estar vivo mientras el usuario esté logueado, sea cual sea la pantalla), el bridge de reloj solo importa mientras hay una sesión de entrenamiento en curso.

**Decisión**: `ref.watch(watchBridgeLifecycleProvider)` se lee dentro de `SessionPlayerScreen`, con `autoDispose` — se activa al entrar a la pantalla, se desactiva al salir. Si el usuario reabre `session_player_screen` con una sesión ya en curso, el listener se re-arma y el primer ciclo debe enviar el contexto actual inmediatamente (no solo en el próximo cambio) — cubierto también por ADR-WC-006.

**Alternativas rechazadas**: eager en `app.dart` — desperdicia recursos fuera del momento de uso.

**Status**: ACCEPTED

---

### ADR-WC-005 — Acciones entrantes: `Map<String,dynamic>` con clave `action`

**Contexto**: Spec open question #2.

**Decisión**: Todo mensaje entrante tiene la forma `{"action": <string>, ...payload}`. Acciones soportadas en v1: `logSet` (`{reps: int, weight: double}`), `completeSet` (sin payload adicional). El dispatcher es un `switch` sobre `action` con un caso `default` que loguea y no hace nada (REQ-WC-BRIDGE-005).

**Consecuencias**: agregar una acción nueva en el futuro (ej. `skipRest`) es un caso más en el switch, sin cambios de forma. Extensible sin romper compatibilidad con la app watchOS ya instalada, siempre que las acciones viejas no cambien de forma.

**Status**: ACCEPTED

---

### ADR-WC-006 — Detección de "cambio relevante" y reenvío en reconexión

**Contexto**: Spec open question #3 + REQ-WC-BRIDGE-001/002 + SCENARIO-WC-023.

**Decisión**: `watchBridgeLifecycleProvider` guarda el último `WatchSessionDto` enviado (`_lastSent`). En cada emisión de `sessionNotifierProvider`, construye el DTO nuevo y compara con `_lastSent` usando la igualdad estructural de freezed (`==`). Si difiere, llama `sendContext` y actualiza `_lastSent`. Además, se subscribe a `isReachable`: cuando pasa de `false` a `true`, reenvía `_lastSent` sin esperar un cambio de estado — cubre el caso "el reloj se reconectó a mitad de sesión".

**Consecuencias**: la igualdad estructural de freezed hace la comparación gratis (no hay que mantener a mano una lista de "campos relevantes" — dado que el DTO ya excluye campos irrelevantes por construcción, ADR-WC-001, comparar el DTO completo es equivalente a comparar "los campos relevantes").

**Status**: ACCEPTED

---

### ADR-WC-007 — Target watchOS: prerequisito manual, sin capability/entitlement especial

**Contexto**: REQ-WC-CX-008. A diferencia de Push Notifications (que requiere una APNs key y el capability "Push Notifications" en el Apple Developer portal), `WatchConnectivity`/`WCSession` NO requiere ningún capability especial en el portal — solo que exista un target de Watch App en el mismo proyecto Xcode, con el mismo Team ID que ya usa TREINO para iOS.

**Decisión**:
- Un dev con Mac + Xcode agrega un target nuevo: `File → New → Target → Watch App` (SwiftUI lifecycle), lo asocia a la app iOS existente como su companion.
- `docs/setup/watchos-target.md` (nuevo, PR#2) documenta: creación del target, bundle id sugerido (`<bundle-id-ios>.watchkitapp`), y que NO hace falta ningún capability adicional en el Apple Developer portal (corrige la hipótesis inicial de `explore.md` §Risks-1, que asumía un paso equivalente a la APNs key).
- La app watchOS en sí (Swift/SwiftUI) queda fuera del alcance de este PR de Flutter — se construye en una sesión aparte con acceso a Xcode.

**Consecuencias**: el prerequisito es más liviano de lo que `explore.md` anticipaba — no hay que esperar aprobación de Apple para un capability, solo tiempo de un dev con Mac.

**Status**: ACCEPTED (corrige la hipótesis de `explore.md` §Risks-1)

---

### ADR-WC-008 — Estrategia de testing

| Capa | Herramienta | Qué cubre |
|---|---|---|
| `WatchSessionDto` | `flutter_test` puro | Serialización, igualdad estructural. |
| `WatchBridgeService` | `mocktail` sobre el paquete `watch_connectivity` | `sendContext` llama al método nativo correcto; streams se exponen tal cual. |
| `watchBridgeLifecycleProvider` | `mocktail` + `ProviderContainer` | Comparación `_lastSent`, throttling, dispatch de acciones, reenvío en reconexión, no-op en acción desconocida. |
| `WatchConnectionChip` | Widget test, `ProviderScope` con overrides | Los 3 estados visuales (no emparejado / emparejado no alcanzable / conectado) + no-render sin sesión. |
| Pairing real / entrega end-to-end | NO AUTOMATIZABLE | Smoke manual en iPhone + Apple Watch físicos, bloqueado hasta que exista el target watchOS (ADR-WC-007). |

**Status**: ACCEPTED

---

### ADR-WC-009 — Wear OS: superficie presente, invocación bloqueada explícitamente

**Contexto**: REQ-WC-CX-002. El paquete `watch_connectivity` expone la misma API para Android/Wear OS. No queremos que alguien la "descubra" y la prenda sin querer antes de que Android sea un target real.

**Decisión**: `WatchBridgeService` no agrega ningún guard de plataforma en tiempo de ejecución más allá de lo que el propio paquete ya hace (en Android sin un companion Wear OS instalado, `isPaired`/`isReachable` simplemente devuelven `false` — comportamiento ya cubierto por REQ-WC-CX-001). La prevención es de PROCESO, no de código: un comentario en `watch_bridge_service.dart` documentando que Android/Wear OS no está probado ni soportado en v1, y `docs/setup/watchos-target.md` aclara que es exclusivamente para iOS/watchOS.

**Consecuencias**: si el día de mañana Android shippea, la superficie Dart ya existe y funciona (según lo que el paquete garantice) — el trabajo pendiente sería construir la app Wear OS nativa y validar, no tocar `lib/features/watch/`.

**Status**: ACCEPTED

---

## 4. File-by-file structure

### PR#1 — Bridge + DTO + providers (NUEVO)

| Path | Propósito | LOC est. |
|---|---|---|
| `lib/features/watch/domain/watch_session_dto.dart` | DTO freezed (ADR-WC-001). | ~40 |
| `lib/features/watch/data/watch_bridge_service.dart` | Wrapper sobre el paquete (ADR-WC-002). | ~70 |
| `lib/features/watch/application/watch_bridge_providers.dart` | Providers + lifecycle (ADR-WC-003, 004, 005, 006). | ~100 |
| `test/features/watch/domain/watch_session_dto_test.dart` | Serialización + igualdad. | ~30 |
| `test/features/watch/data/watch_bridge_service_test.dart` | Mocktail sobre el paquete. | ~60 |
| `test/features/watch/application/watch_bridge_providers_test.dart` | Throttling, dispatch, reconexión, no-op. | ~120 |

### PR#1 — Modificado

| Path | Cambio | LOC est. |
|---|---|---|
| `pubspec.yaml` | + `watch_connectivity`. | +1 |

**PR#1 total estimado**: ~420 LOC (test-heavy, apenas sobre el límite — ver §7).

### PR#2 — UI + wiring + doc nativa (NUEVO)

| Path | Propósito | LOC est. |
|---|---|---|
| `lib/features/watch/presentation/watch_connection_chip.dart` | Chip de estado (ADR-WC-008, REQ-WC-UI-001/002). | ~60 |
| `test/features/watch/presentation/watch_connection_chip_test.dart` | 3 estados visuales + no-render sin sesión. | ~50 |
| `docs/setup/watchos-target.md` | Prerequisito manual (ADR-WC-007). | ~35 |

### PR#2 — Modificado

| Path | Cambio | LOC est. |
|---|---|---|
| `lib/features/workout/presentation/session_player_screen.dart` | Monta `WatchConnectionChip` + lee `watchBridgeLifecycleProvider` (ADR-WC-004). Estrictamente aditivo. | +15 |

**PR#2 total estimado**: ~160 LOC.

### BORRADO

Ninguno.

---

## 5. PR boundary

| PR | Capa | Por qué este corte |
|---|---|---|
| **PR#1** | Bridge, DTO, providers, tests | 100% testeable sin dispositivo real ni target watchOS — todo mockeado. Puede mergear y quedar "inerte" (nadie lo llama todavía) sin riesgo. |
| **PR#2** | UI + wiring + doc | Depende de PR#1 mergeado. El smoke real depende además del prerequisito out-of-band (target watchOS) — el código mergea igual, el smoke queda pendiente hasta que exista. |

---

## 6. Riesgos — tabla de resolución

| Riesgo (de proposal) | ADR / Mitigación |
|---|---|
| No existe target watchOS | ADR-WC-007 — prerequisito manual, más liviano de lo esperado (sin capability especial). |
| Archivos grandes/sensibles (`session_player_screen.dart`, `session_notifier.dart`) | Cambios aditivos únicamente — un `ref.watch` + un widget montado en PR#2; PR#1 no toca esos archivos en absoluto. |
| Simulador no confiable | ADR-WC-008 — todo lo automatizable se cubre con mocktail; pairing real es smoke manual, documentado como no automatizable. |
| Reviewer sin contexto previo | Spec + design explícitos, mismo nivel de detalle que `push-notifications-fcm`, para minimizar preguntas de review. |
| Gamificación colándose | REQ-WC-CX-003 + revisión de diseño de la app watchOS antes de construirla. |
| Wear OS como código muerto | ADR-WC-009 — documentado explícitamente, sin UI ni tests Android. |

---

## 7. Open questions for tasks phase

1. PR#1 estimado en ~420 LOC, apenas sobre el límite de 400 — decidir en `tasks` si se parte en PR#1a (DTO+service) / PR#1b (providers+lifecycle), o si se pide `size:exception`.
2. Confirmar el nombre exacto de los métodos del paquete `watch_connectivity` contra la versión real instalada (`flutter pub add watch_connectivity` + inspección del API) antes de escribir el primer test — este design asume nombres típicos, no verificados contra código fuente real.

---

## 8. Hard constraints (enforceable)

1. Única dependencia nueva: `watch_connectivity`.
2. `WatchSessionDto` — exactamente 7 campos (ADR-WC-001).
3. `updateApplicationContext` para estado, `sendMessage` para acciones (ADR-WC-002).
4. Lifecycle atado a `session_player_screen.dart`, `autoDispose` — NO eager en `app.dart` (ADR-WC-004).
5. Acciones entrantes soportadas en v1: únicamente `logSet`, `completeSet` (ADR-WC-005).
6. Sin capability/entitlement de Apple Developer nuevo requerido (ADR-WC-007) — si al implementar resulta que sí hace falta algo, es una señal para volver a `design`.
7. Cero HEX literals, cero `PhosphorIcons.X` directo.
8. Cero referencias a Wear OS/Android como soportado en v1.
9. Cero mecánicas de Retos/Missions/Bets/Gamificación.
10. Strict TDD, conventional commits, sin atribución de IA.
11. PRs ≤ 400 LOC o `size:exception`.

---

## 9. Artifact references

- Proposal: `openspec/changes/watch-connectivity/proposal.md`
- Spec: `openspec/changes/watch-connectivity/spec.md`
- Explore: `openspec/changes/watch-connectivity/explore.md`

---

**Status**: listo para `sdd-tasks` (o para que un dev del equipo lo revise antes de continuar — ver nota de proceso en `explore.md`).
