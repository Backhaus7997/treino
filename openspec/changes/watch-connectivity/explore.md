# Exploration: watch-connectivity

**Change**: watch-connectivity
**Owner**: Backhaus
**Date**: 2026-08-03
**Fase**: Sin asignar — feature nueva, fuera del roadmap actual (propuesta por el usuario, no una etapa planeada)
**Artifact store**: openspec (sin Engram — esta sesión no tiene acceso al MCP Engram local de esta máquina)

---

## Scope Summary

Conectar TREINO con Apple Watch para reflejar la sesión de entrenamiento activa (ejercicio actual, serie objetivo, descanso) en la muñeca, y permitir loguear series desde el reloj hacia `SessionNotifier`.

Wear OS queda **explícitamente diferido**: `pubspec.yaml` declara el proyecto como "iOS-only, mobile-only" (`flutter_launcher_icons: android: false`) — aunque el directorio `android/` existe con Gradle real (`build.gradle.kts`, `app/`, wrapper), no se shippea. Wear OS empareja con un teléfono Android; sin ese teléfono en producción no hay contraparte con la que emparejar un reloj. Se elige de entrada un paquete Dart que cubra ambos lados (`watch_connectivity`) para no pagar costo de migración el día que Android shippee, pero **la única app nativa que se construye en v1 es watchOS**.

---

## Current State

### Flutter / pubspec

- No existe ninguna dependencia de watch connectivity (`watch_connectivity`, `flutter_wear_os_connectivity`, etc.) en `pubspec.yaml`.
- `flutter_launcher_icons: { ios: true, android: false }` con comentario explícito "For now: iOS-only, mobile-only project" — confirma el scope actual del producto.
- No hay ningún target watchOS en `ios/` (no lo genera `flutter create` por defecto; requiere agregarlo a mano en Xcode).

### Feature workout (punto de enganche)

- `lib/features/workout/application/session_notifier.dart` (26 KB) — Riverpod `Notifier` dueño de la sesión activa (ejercicio actual, set actual, estado del descanso). Es el estado que hay que espejar hacia el reloj.
- `lib/features/workout/application/session_state.dart` — shape del estado que consume `session_notifier.dart`.
- `lib/features/workout/presentation/session_player_screen.dart` (95 KB — el archivo más grande del feature) — pantalla de entrenamiento activo. Candidato natural para montar un indicador "reloj conectado".
- `lib/features/workout/presentation/widgets/set_entry_sheet.dart` — UI de carga de una serie (reps/peso). El reloj necesita disparar una acción equivalente.
- `lib/features/workout/data/session_repository.dart` (16 KB) — persistencia Firestore de la sesión. No debería tocarse — el bridge lee el `SessionNotifier` ya existente, no la capa de datos directamente.
- `lib/features/workout/domain/session.dart`, `set_log.dart`, `set_limits.dart` — modelos freezed existentes, reusables para construir el payload del reloj y para validar inputs entrantes.

### Precedente reusable: `features/notifications` (push-notifications-fcm, Fase 6 Etapa 2)

Mismo tipo de problema (una capability nueva que envuelve un SDK nativo con permisos + lifecycle):
- Feature folder standalone (`application/`, `data/`, `presentation/`) en vez de vivir dentro de `workout/`.
- Servicio delgado (`FcmService`) + repository + Riverpod provider de lifecycle (`ref.listen(authStateProvider)`) — mismo patrón aplicable acá con `ref.listen(sessionNotifierProvider)`.
- Prerequisito nativo manual documentado en `docs/setup/*.md` (allí: APNs key; acá: crear el target watchOS en Xcode) — no bloquea el merge de código, sí el smoke end-to-end.
- Limitación de emulación: FCM no es emulable, requiere dispositivo real. Acá: el pairing iPhone↔Watch tampoco es confiable en simulador.

### Verificación de scope-out del producto

No hay ninguna mención previa a "watch"/"wear"/"reloj"/"smartwatch" en `docs/roadmap.md`, `docs/product.md`, `docs/performance.md` ni en `.atl/skill-registry.md` (catálogo de 24 skills). Es territorio 100% nuevo — no hay decisiones tomadas previamente que respetar más allá de las reglas generales de `AGENTS.md` (Riverpod, freezed, `AppPalette`, `TreinoIcon`, i18n es-AR, etc.).

---

## What Needs to Be Built (borrador — se cierra en proposal)

### Dependencia

- `pubspec.yaml`: `watch_connectivity` (pub.dev, publisher verificado `rexios.dev`, release activo — envuelve `WatchConnectivity` en iOS y la Wearable API en Android bajo una sola superficie Dart).

### Feature nuevo `lib/features/watch/` (nombre a confirmar en proposal)

- `data/watch_bridge_service.dart` — wrapper delgado sobre el paquete: enviar contexto (`updateApplicationContext`), escuchar mensajes entrantes, exponer `isPaired`/`isReachable`.
- `domain/watch_session_dto.dart` — DTO chico (freezed) con el subconjunto de `SessionState` que viaja al reloj.
- `application/watch_bridge_providers.dart` — Riverpod: escucha `sessionNotifierProvider`, arma el DTO, llama al service; escucha mensajes entrantes del reloj y despacha acciones sobre `SessionNotifier`.
- `presentation/watch_connection_chip.dart` — indicador visual (paired/reachable), a montar en `session_player_screen.dart`.

### Nativo (fuera de Dart)

- Target watchOS nuevo en Xcode (Swift/SwiftUI) — pantalla única: ejercicio + serie actual, botón para cargar serie. Trabajo manual, no generable desde este entorno (no hay Xcode disponible acá).
- `docs/setup/watchos-target.md` — nuevo doc, mismo rol que `docs/setup/fcm-apns.md`: pasos para crear el target, bundle id, capacidades.

### Tests

- `test/features/watch/data/watch_bridge_service_test.dart` — mocktail sobre el paquete.
- `test/features/watch/application/watch_bridge_providers_test.dart` — verifica que cambios en `SessionNotifier` disparan `sendContext`, y que mensajes entrantes disparan las acciones correctas.

---

## Approach Options

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **A — Paquete `watch_connectivity` (RECOMENDADO)** | Una sola superficie Dart para iOS ahora y Android/Wear OS a futuro. Mantenido activamente (release reciente, publisher verificado). Menos código propio que mantener. | El target watchOS igual hay que crearlo a mano en Xcode — el paquete no genera la app nativa. | Medio |
| **B — `MethodChannel` propio sobre `WCSession`** | Control total, cero dependencias de terceros. | Reinventa serialización, reachability, application-context-vs-message-vs-file-transfer que el paquete ya resuelve. Más superficie propia para mantener a largo plazo. | Alto |
| **C — Diferir hasta que Android shippee y evaluar Wear OS a la par** | Evita construir sobre una plataforma (iOS-only) que podría expandirse pronto. | No resuelve el pedido actual — el usuario quiere Apple Watch ahora, no "algún día". | N/A (no shippea nada) |

**Recomendación: A.**

---

## Open Questions for Proposal

1. **Nombre/ubicación del feature**: ¿`lib/features/watch/` standalone (como `notifications`), o vive dentro de `lib/features/workout/`? Recomendado: standalone, mismo motivo que `notifications` — evita acoplar una capability de plataforma al feature de dominio.
2. **Subconjunto de estado espejado**: ¿qué campos exactos de `SessionState` viajan al reloj? El DTO debe ser chico — `updateApplicationContext` tiene límite práctico de tamaño, no está pensado para blobs grandes.
3. **¿El reloj puede iniciar una sesión?** Recomendado: NO en v1 — solo refleja y loguea una sesión ya iniciada desde el teléfono. Reduce superficie y riesgo.
4. **Transporte**: `updateApplicationContext` (best-effort, no requiere reachability, se pisa) vs `sendMessage` (requiere reachability, con ack) — probablemente ambos, cada uno para un propósito distinto.
5. **¿Quién crea el target watchOS?** Es un paso manual (Xcode + Mac), análogo al APNs key de push-notifications-fcm — no bloquea merge de código Dart, sí bloquea smoke end-to-end.
6. **¿Indicador de conexión en la UI del teléfono?** Recomendado: sí, chip chico en `session_player_screen.dart`.
7. **¿Rest timer en vivo segundo a segundo en el reloj?** Recomendado: NO en v1 — actualizar solo en transiciones de estado (nueva serie, nuevo ejercicio, descanso iniciado/terminado), no tick continuo, para no saturar `updateApplicationContext`.
8. **Branch/scope**: `feat/workout-watch-connectivity` (scope `workout` según `docs/workflow.md`) — a confirmar si el scope debería ser uno nuevo (`watch`) dado que el feature vive standalone.

---

## Risks

1. **No existe target watchOS en el repo.** Crearlo requiere Xcode + Mac — no se puede generar desde este entorno. Mitigación: documentar como prerequisito manual out-of-band (mismo patrón que la APNs key).
2. **`session_player_screen.dart` (95 KB) y `session_notifier.dart` (26 KB) son archivos grandes y de alto tráfico.** Cualquier hook debe ser aditivo, nunca refactor — y el PR debe mantenerse chico igual que el resto de las SDDs del proyecto (<400 LOC).
3. **El simulador de iOS no es confiable para probar pairing con un Watch simulado.** Smoke real requiere iPhone + Apple Watch físicos — análogo a "FCM no es emulable" en push-notifications-fcm.
4. **Feature 100% nuevo para el equipo** — ningún reviewer tiene contexto previo de wearables. Puede implicar más ida y vuelta en review que una feature típica.
5. **Riesgo de reintroducir mecánicas out-of-scope** (Retos/Missions/Bets/Gamificación) en la superficie del reloj sin querer — un reloj es una superficie tentadora para ese tipo de features. El spec debe dejarlo explícitamente prohibido.
6. **Wear OS queda como "código muerto" potencial** — el paquete soporta Android pero no hay app ni testing. Si alguien lo activa antes de que Android shippee, puede fallar silenciosamente o de forma confusa. Mitigación: documentar explícitamente "no soportado hasta que Android sea un target real" en el spec.

---

## Ready for Proposal

**SÍ.** El punto de enganche (`session_notifier.dart`) está identificado, no hay conflicto con decisiones previas (no existían), y el approach (A) tiene un precedente directo y reciente en el propio repo (`push-notifications-fcm`) para calcar la forma del PR y el manejo del prerequisito manual.

**Nota de proceso**: esta exploración (y el resto del ciclo — proposal/spec/design) fue armada a mano por Claude fuera de `gentle-ai`/`/sdd-new`, porque esta sesión de Cowork corre en la nube y no tiene acceso al `~/.claude/` local donde vive el CLI de `gentle-ai` ni al MCP de Engram de esta máquina. Las "Locked Decisions" de `proposal.md` son un borrador razonado, no una decisión de equipo — deberían revisarse como tales antes de pasar a `tasks`/`apply`, ya sea acá o retomando con `/sdd-new` local.

---

## Artifacts

- File: `openspec/changes/watch-connectivity/explore.md`
