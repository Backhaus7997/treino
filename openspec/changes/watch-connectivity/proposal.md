# Proposal: watch-connectivity

**Change**: watch-connectivity
**Branch**: `feat/workout-watch-connectivity`
**Depende de exploración**: `openspec/changes/watch-connectivity/explore.md`

---

## 1. TL;DR

Agregar `watch_connectivity` a TREINO para reflejar la sesión de entrenamiento activa (ejercicio actual, serie objetivo, descanso) en un Apple Watch companion, y permitir loguear series desde la muñeca. v1 es iOS-only, coherente con el scope actual del producto (`pubspec.yaml` declara "iOS-only, mobile-only"). Wear OS queda con la superficie Dart lista (el paquete elegido cubre ambos lados) pero **sin app nativa, sin testing, sin distribución** — explícitamente diferido a cuando Android shippee. Requiere un target watchOS nuevo creado a mano en Xcode — documentado como prerequisito manual, mismo patrón que la APNs key de `push-notifications-fcm`. Feature nuevo standalone `lib/features/watch/`, sin tocar `session_notifier.dart` más que agregar un listener aditivo.

---

## 2. Motivation

`session_player_screen.dart` es la pantalla que se usa durante el momento de mayor fricción física del producto: en medio de una serie, con las manos ocupadas o sudadas, el usuario tiene que sacar el teléfono para ver qué sigue o cargar el peso levantado. Un companion en la muñeca — reflejar el ejercicio/serie actual y permitir cargar una serie con un tap — ataca exactamente ese momento.

No hay nada de esto en el roadmap actual ni en ninguna decisión previa del proyecto (verificado contra `roadmap.md`, `product.md`, `performance.md` y el catálogo de skills) — es una capability nueva, propuesta directamente por el usuario, no una etapa de una fase ya planeada.

---

## 3. Scope

### In Scope (v1)

- Dependencia `watch_connectivity` en `pubspec.yaml`.
- Feature nuevo `lib/features/watch/` (`domain/`, `data/`, `application/`, `presentation/`) — no vive dentro de `workout/`, mismo criterio que `notifications` (capability de plataforma, no de dominio).
- `WatchSessionDto` — subconjunto chico de `SessionState`: nombre de ejercicio, número de serie / total de series, reps y peso objetivo, segundos de descanso restantes, id de sesión.
- Bridge teléfono→reloj: en cada transición relevante de `SessionNotifier` (nueva serie, nuevo ejercicio, descanso iniciado/terminado), `updateApplicationContext` con el DTO. **Sin tick continuo por segundo.**
- Bridge reloj→teléfono: `sendMessage` para acciones puntuales (`logSet`, `completeSet`) que el bridge traduce en llamadas a métodos ya existentes de `SessionNotifier`.
- Indicador "reloj conectado/no conectado" en `session_player_screen.dart` (chip chico, `AppPalette`/`TreinoIcon`).
- watchOS companion app mínima (Swift/SwiftUI, target nuevo en Xcode): ejercicio + serie actual, control para cargar una serie. Funcional, no pixel-perfect.

### Out of Scope (v1)

- **Wear OS**: superficie Dart lista (el paquete la soporta) pero sin app Android, sin testing, sin distribución. Diferido a cuando el proyecto shippee Android.
- Iniciar una sesión desde el reloj — solo reflejar/loguear una sesión ya iniciada en el teléfono.
- Rest timer en vivo segundo a segundo en el reloj (solo transiciones de estado).
- Complications de watch face.
- HealthKit / heart rate / datos biométricos (posible v2, no acá).
- Notificaciones push al Watch.
- Cualquier mecánica ya out-of-scope del producto (Retos/Missions/Bets/Gamificación) — el reloj no es una excepción a esa regla.

---

## 4. Locked Decisions

| # | Decisión | Elegido | Justificación |
|---|---|---|---|
| 1 | Ubicación del feature | `lib/features/watch/` standalone | Mismo criterio que `notifications`: capability de plataforma, no debe vivir dentro de `workout/` ni acoplar ese feature a un SDK nativo. `watch/` depende de `workout` (lee `sessionNotifierProvider`), nunca al revés. |
| 2 | Subconjunto de estado espejado | `{sessionId, exerciseName, setIndex, totalSets, targetReps, targetWeight, restSecondsRemaining}` | Payload chico a propósito — `updateApplicationContext` no está pensado para blobs grandes ni para el `Session` freezed completo (tiene campos irrelevantes para una pantalla de reloj). |
| 3 | ¿El reloj inicia sesión? | NO | Reduce superficie v1. Iniciar una sesión implica seleccionar rutina/día, UI que no tiene sentido reconstruir en una pantalla de 40mm. |
| 4 | Transporte | `updateApplicationContext` (estado "current", best-effort) + `sendMessage` (acciones puntuales reloj→teléfono, con ack) | Cada mecanismo para lo que mejor resuelve: contexto no requiere reachability inmediata (se entrega cuando el reloj se reconecta); una acción como "cargué la serie" sí necesita confirmación. |
| 5 | Creación del target watchOS | Prerequisito manual, out-of-band, un dev con Xcode | Análogo a la APNs key de `push-notifications-fcm`: no bloquea merge de código Dart, sí bloquea smoke end-to-end. Documentado en `docs/setup/watchos-target.md` (nuevo). |
| 6 | Indicador de conexión en el teléfono | Sí — chip chico en `session_player_screen.dart`, usando `isPaired`/`isReachable` del paquete | Sin esto, un usuario con el reloj desparejado no tiene forma de saber por qué "no pasa nada" en la muñeca. |
| 7 | Rest timer en vivo | NO — solo transiciones de estado | Actualizar cada segundo satura `updateApplicationContext` (pensado para snapshots poco frecuentes) y no aporta valor proporcional al costo/riesgo. |
| 8 | Branch / scope | `feat/workout-watch-connectivity`, scope `workout` | El feature vive standalone en `lib/features/watch/`, pero el *motivo* del cambio es una capability de `workout` — coherente con cómo el scope de commits se elige por la superficie afectada, no por el nombre de la carpeta nueva. |

---

## 5. Approach Summary

**Approach A — paquete `watch_connectivity` + DTO chico + bridge unidireccional con throttling en transiciones** (confirmado desde `explore.md` §Approaches).

- `WatchBridgeService` (en `features/watch/data/`) envuelve el paquete: `sendContext(WatchSessionDto)`, `Stream<Map<String, dynamic>> get incomingMessages`, `Stream<bool> get isReachable`, `Stream<bool> get isPaired`.
- `watchBridgeLifecycleProvider` (`Provider<void>`, `autoDispose`) hace `ref.listen(sessionNotifierProvider, (prev, next) { ... })`, arma el DTO solo cuando cambian los campos relevantes (no en cada rebuild), y llama a `sendContext`. Simétricamente, escucha `incomingMessages` y despacha `ref.read(sessionNotifierProvider.notifier).logSet(...)` / `.completeSet()` según la acción recibida.
- `WatchConnectionChip` es un widget chico montado en `session_player_screen.dart`, observando `isReachable`/`isPaired`.

Rechazado: Approach B (`MethodChannel` propio) reinventa lo que el paquete ya resuelve bien; Approach C (diferir todo) no responde al pedido actual.

---

## 6. Deliverable Surface

- `pubspec.yaml` — + `watch_connectivity` (rango de versión a resolver con `flutter pub add` al momento de implementar).
- `lib/features/watch/domain/watch_session_dto.dart` — freezed, chico (ver Locked Decision #2).
- `lib/features/watch/data/watch_bridge_service.dart` — wrapper sobre `WatchConnectivity`.
- `lib/features/watch/application/watch_bridge_providers.dart` — providers + lifecycle listener.
- `lib/features/watch/presentation/watch_connection_chip.dart` — indicador UI.
- `lib/features/workout/presentation/session_player_screen.dart` — modificado, aditivo: monta `WatchConnectionChip`.
- `docs/setup/watchos-target.md` — nuevo, pasos manuales para crear el target Xcode.
- `test/features/watch/domain/watch_session_dto_test.dart`, `test/features/watch/data/watch_bridge_service_test.dart`, `test/features/watch/application/watch_bridge_providers_test.dart`, `test/features/watch/presentation/watch_connection_chip_test.dart`.
- Target watchOS (Xcode, fuera de este PR — manual).

---

## 7. Risks & Mitigations

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| 1 | No existe target watchOS — no se puede crear desde este entorno | ALTA | Prerequisito manual documentado (Locked Decision #5); código Dart mergeable sin él, smoke bloqueado hasta que exista. |
| 2 | Archivos grandes/sensibles (`session_player_screen.dart`, `session_notifier.dart`) | MEDIA | Cambios estrictamente aditivos (un listener + un widget montado), nunca refactor de esos archivos en este change. |
| 3 | Simulador no confiable para pairing | MEDIA | Smoke manual en iPhone + Apple Watch reales, igual que el patrón "no emulable" de FCM. |
| 4 | Feature 100% nuevo, sin reviewer con contexto previo | BAJA-MEDIA | PR chico, spec/design explícitos con decisiones ya cerradas para minimizar idas y vueltas. |
| 5 | Riesgo de reintroducir gamificación en la superficie del reloj | BAJA | REQ explícito en spec prohibiéndolo. |
| 6 | Wear OS como código muerto potencial | BAJA | Documentado explícitamente como no soportado hasta que Android shippee; sin UI ni tests Android en v1. |

---

## 8. Out-of-band Prerequisites (NO en el PR)

1. Target watchOS creado en Xcode (`File → New → Target → Watch App`) por un dev con Mac.
2. Confirmar que la cuenta de Apple Developer ya usada para iOS habilita Watch (ver ADR-WC-007 en `design.md` — no debería requerir nada nuevo).
3. iPhone + Apple Watch físicos para smoke — el simulador no es confiable para reachability/pairing.

---

## 9. Success Criteria

- [ ] Tests Dart existentes siguen verdes + nuevos para `watch_bridge_service`/`watch_bridge_providers`/`watch_connection_chip`.
- [ ] `flutter analyze` → 0 issues. `dart format .` limpio.
- [ ] Smoke en dispositivo real: iniciar sesión en el teléfono → el Watch muestra ejercicio/serie actual dentro de unos segundos; cargar serie desde el Watch → aparece reflejada en `session_player_screen` sin reabrir la pantalla.
- [ ] Reloj no pareado/no reachable: la app no crashea, el chip muestra el estado correcto, ninguna otra feature se degrada.
- [ ] Cero HEX literals, cero `PhosphorIcons.X` directo.
- [ ] Copy en es-AR, tageado (marcador `// i18n: watch-connectivity`, dado que no hay Fase asignada).
- [ ] PR(s) ≤ 400 LOC o `size:exception` aprobado.
- [ ] Conventional commits, sin `Co-Authored-By`/atribución de IA.

---

## 10. Open Questions Carrying to Spec/Design

1. Punto exacto de inicialización de `watchBridgeLifecycleProvider` — ¿eager en `app.dart` (como `fcmLifecycleProvider`) o lazy al entrar a `session_player_screen`? Impacta si el reloj puede reflejar una sesión ya en curso al reabrir la app.
2. Formato exacto del `Map<String,dynamic>` para `sendMessage` (shape de la acción `logSet`).
3. Manejo de reconexión: si `isReachable` pasa de `false` a `true` a mitad de una sesión, ¿se reenvía el contexto completo inmediatamente?

---

## 11. PR Plan

**2 PRs encadenados** (mismo patrón que `push-notifications-fcm`, para mantener cada uno chico):

| PR | Scope | Verificación |
|---|---|---|
| **PR#1 — Bridge + DTO + providers** | `pubspec.yaml`, `watch_session_dto.dart`, `watch_bridge_service.dart`, `watch_bridge_providers.dart`, tests. Sin UI. | `flutter test` verde, `flutter analyze` 0 issues. Sin dispositivo real todavía — todo mockeable. |
| **PR#2 — UI + wiring + doc nativa** | `watch_connection_chip.dart`, montaje en `session_player_screen.dart`, `docs/setup/watchos-target.md`. | Smoke manual una vez exista el target watchOS (prerequisito out-of-band). |

---

## 12. Artifact References

- File: `openspec/changes/watch-connectivity/proposal.md`
- Exploración: `openspec/changes/watch-connectivity/explore.md`

**Status**: listo para `spec` y `design` (pueden correr en paralelo, mismo criterio que `push-notifications-fcm`).
