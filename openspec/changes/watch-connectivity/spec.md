# Spec: watch-connectivity

**Change**: watch-connectivity
**Proposal ref**: `openspec/changes/watch-connectivity/proposal.md`
**Scenario range**: SCENARIO-WC-001..SCENARIO-WC-028 (numeración local a este change — ver nota abajo)

> **Nota de numeración**: el resto de las specs del proyecto (ej. `push-notifications-fcm`, rango SCENARIO-619..693) usan un contador global, probablemente mantenido por Engram/gentle-ai. Esta sesión no tiene acceso a ese contador, así que numeré localmente (`SCENARIO-WC-NNN`). Si retomás esto con `/sdd-new` local, puede que quieras renumerar a la secuencia global del proyecto.

---

## Overview

Capability nueva: reflejar la sesión de entrenamiento activa en un Apple Watch companion y loguear series desde la muñeca. No hay specs previas de las que hacer delta — todos los requirements son NUEVOS. Wear OS queda explícitamente fuera de v1 (ver REQ-WC-CX-002). Entregado en 2 PRs: PR#1 (bridge + providers, sin UI) y PR#2 (UI + wiring + doc nativa).

---

## Requirements

---

### REQ-WC-DEP-001 — Única dependencia nueva: `watch_connectivity`

El proyecto DEBE agregar `watch_connectivity` como única dependencia nueva para esta capability. NO DEBE agregarse ningún otro paquete de conectividad con wearables (`flutter_wear_os_connectivity`, `flutter_smart_watch`, etc.).

#### SCENARIO-WC-001: pubspec.yaml lista watch_connectivity y ningún otro paquete de wearables
- **Given** `pubspec.yaml` después de mergear este change
- **When** se inspeccionan las dependencias
- **Then** `watch_connectivity` está presente
- **And** ningún otro paquete de conectividad con wearables está presente
- **Test target**: revisión manual en PR
- **REQ**: REQ-WC-DEP-001

---

### REQ-WC-DATA-001 — Forma del `WatchSessionDto`

El sistema DEBE definir un `WatchSessionDto` (freezed) con exactamente estos campos: `sessionId` (String), `exerciseName` (String), `setIndex` (int), `totalSets` (int), `targetReps` (int?), `targetWeight` (double?), `restSecondsRemaining` (int?). NO DEBE incluir el objeto `Session` completo ni campos ajenos a lo que la UI del reloj necesita mostrar.

#### SCENARIO-WC-002: DTO serializa solo los campos definidos
- **Given** un `SessionState` activo con ejercicio, serie y descanso en curso
- **When** se construye el `WatchSessionDto` correspondiente
- **Then** el DTO serializado (`toJson()`) contiene únicamente los 7 campos definidos
- **Test target**: `test/features/watch/domain/watch_session_dto_test.dart`
- **REQ**: REQ-WC-DATA-001

---

### REQ-WC-BRIDGE-001 — Envío de contexto en transiciones relevantes

`WatchBridgeService.sendContext(WatchSessionDto)` DEBE invocar `updateApplicationContext` del paquete cuando cambia el DTO resultante respecto al último enviado (ejercicio, serie, descanso, etc.). NO DEBE invocarse si el DTO no cambió respecto al último envío.

#### SCENARIO-WC-003: cambio de ejercicio dispara sendContext
- **Given** una sesión activa en el ejercicio A, serie 1
- **When** `SessionNotifier` avanza al ejercicio B
- **Then** `WatchBridgeService.sendContext` es invocado con un DTO reflejando el ejercicio B
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-001

#### SCENARIO-WC-004: rebuild sin cambios relevantes no dispara sendContext
- **Given** una sesión activa sin cambios en ejercicio/serie/descanso
- **When** `SessionNotifier` emite un rebuild por un campo no reflejado en el DTO
- **Then** `WatchBridgeService.sendContext` NO es invocado
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-001

---

### REQ-WC-BRIDGE-002 — Sin actualizaciones continuas por segundo

El bridge NO DEBE enviar un `sendContext` por cada segundo de cuenta regresiva del descanso. Solo DEBE enviar en las transiciones: descanso iniciado, descanso terminado.

#### SCENARIO-WC-005: countdown de descanso no genera un sendContext por tick
- **Given** un descanso de 60 segundos en curso
- **When** el contador interno de `SessionNotifier` decrementa segundo a segundo
- **Then** `sendContext` es invocado únicamente al iniciar el descanso y al terminarlo — no en cada tick intermedio
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-002

---

### REQ-WC-BRIDGE-003 — Mensaje entrante `logSet` despacha a `SessionNotifier`

Un mensaje entrante con `{"action": "logSet", "reps": <int>, "weight": <double>}` DEBE resultar en una llamada a `sessionNotifier.logSet(reps: ..., weight: ...)` para la sesión activa, aplicando la misma validación de `set_limits.dart` que ya aplica para inputs del teléfono.

#### SCENARIO-WC-006: logSet desde el reloj carga la serie en el teléfono
- **Given** una sesión activa con el reloj reachable
- **When** llega un mensaje `{"action": "logSet", "reps": 10, "weight": 40.0}`
- **Then** `sessionNotifier.logSet(reps: 10, weight: 40.0)` es invocado
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-003

---

### REQ-WC-BRIDGE-004 — Mensaje entrante `completeSet` avanza la sesión

Un mensaje entrante `{"action": "completeSet"}` DEBE resultar en una llamada equivalente a la que dispara el botón "completar serie" ya existente en `set_entry_sheet.dart`.

#### SCENARIO-WC-007: completeSet desde el reloj avanza a la siguiente serie
- **Given** una sesión activa en la serie 2 de 4
- **When** llega un mensaje `{"action": "completeSet"}`
- **Then** el `SessionNotifier` avanza a la serie 3, igual que si se hubiera tocado "completar" en el teléfono
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-004

---

### REQ-WC-BRIDGE-005 — Acción desconocida se ignora de forma segura

Un mensaje entrante con un `action` no reconocido, o sin sesión activa en curso, DEBE ser ignorado silenciosamente (log, sin excepción, sin crash).

#### SCENARIO-WC-008: acción desconocida no crashea
- **Given** cualquier estado de sesión
- **When** llega un mensaje `{"action": "unknownAction"}`
- **Then** no se lanza ninguna excepción
- **And** se emite una línea de log indicando la acción desconocida
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-005

#### SCENARIO-WC-009: mensaje sin sesión activa se ignora
- **Given** ninguna sesión activa (`sessionNotifierProvider` en estado vacío/nulo)
- **When** llega cualquier mensaje del reloj
- **Then** no se lanza ninguna excepción y no se muta ningún estado
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-005

---

### REQ-WC-BRIDGE-006 — El reloj no puede iniciar una sesión

El bridge NO DEBE exponer ninguna acción entrante capaz de iniciar una sesión nueva (`startSession` o equivalente). Esto es una restricción de producto v1, no una limitación técnica del paquete.

#### SCENARIO-WC-010: acción startSession no existe / se ignora como desconocida
- **Given** el mapa de acciones soportadas por el bridge
- **When** se inspecciona el código de despacho de acciones
- **Then** no existe ninguna rama para `startSession` (o similar) — cae en el manejo de acción desconocida de REQ-WC-BRIDGE-005 si algún cliente la manda
- **Test target**: revisión de código en PR
- **REQ**: REQ-WC-BRIDGE-006

---

### REQ-WC-UI-001 — Chip de conexión refleja `isReachable`/`isPaired`

`WatchConnectionChip` DEBE mostrar tres estados posibles derivados de los streams `isReachable`/`isPaired` del paquete: "no emparejado", "emparejado, no alcanzable", "conectado". NO DEBE mostrarse (o no ocupar espacio visual relevante) si no hay sesión activa.

#### SCENARIO-WC-011: chip muestra "conectado" cuando isReachable es true
- **Given** `WatchBridgeService.isReachable` emite `true`
- **When** `WatchConnectionChip` se reconstruye
- **Then** el chip muestra el estado "conectado"
- **Test target**: `test/features/watch/presentation/watch_connection_chip_test.dart`
- **REQ**: REQ-WC-UI-001

#### SCENARIO-WC-012: chip muestra "no emparejado" cuando isPaired es false
- **Given** `WatchBridgeService.isPaired` emite `false`
- **When** `WatchConnectionChip` se reconstruye
- **Then** el chip muestra el estado "no emparejado"
- **Test target**: `test/features/watch/presentation/watch_connection_chip_test.dart`
- **REQ**: REQ-WC-UI-001

#### SCENARIO-WC-026: chip no se muestra si no hay sesión activa
- **Given** el usuario está en `session_player_screen.dart` sin sesión activa
- **When** la pantalla se renderiza
- **Then** `WatchConnectionChip` no ocupa espacio visual relevante (o no se monta)
- **Test target**: `test/features/workout/presentation/session_player_screen_test.dart`
- **REQ**: REQ-WC-UI-001

---

### REQ-WC-UI-002 — Cero HEX literales, cero PhosphorIcons directo

`WatchConnectionChip` y cualquier widget nuevo de este change DEBEN usar `AppPalette.of(context)` para color y `TreinoIcon.X` para íconos. Cero literales HEX, cero `PhosphorIcons.X` directo.

#### SCENARIO-WC-013: rg no encuentra HEX literals ni PhosphorIcons directo en los archivos nuevos
- **Given** el diff de este change
- **When** se corre `rg '#[0-9a-fA-F]{3,8}'` y `rg 'PhosphorIcons\.'` sobre los archivos nuevos de `lib/features/watch/`
- **Then** no hay matches (fuera del propio `treino_icon.dart`, wrapper autorizado)
- **Test target**: revisión manual / lint en PR
- **REQ**: REQ-WC-UI-002

---

### REQ-WC-CX-001 — Comportamiento correcto sin reloj emparejado

Si el usuario no tiene Apple Watch, o lo tiene pero no está emparejado/alcanzable, la app NO DEBE crashear ni degradar ninguna otra funcionalidad de `session_player_screen.dart`. El chip DEBE reflejar el estado sin bloquear la pantalla.

#### SCENARIO-WC-014: sesión funciona normalmente sin reloj
- **Given** un usuario sin Apple Watch emparejado
- **When** inicia y completa una sesión de entrenamiento normalmente
- **Then** ninguna funcionalidad de `session_player_screen.dart` se ve afectada
- **And** no se lanza ninguna excepción relacionada al bridge
- **Test target**: `test/features/workout/presentation/session_player_screen_test.dart` (extendido)
- **REQ**: REQ-WC-CX-001

---

### REQ-WC-CX-002 — Sin activación de Android/Wear OS en v1

El bridge NO DEBE incluir ninguna UI, texto, o lógica condicional específica para Wear OS/Android en v1. La superficie Android del paquete `watch_connectivity` existe porque el paquete la trae, pero NO DEBE invocarse, probarse, ni documentarse como soportada.

#### SCENARIO-WC-015: no hay referencias a Wear OS en el código o UI de este change
- **Given** el diff de este change
- **When** se buscan menciones a "Wear OS", "Android watch" en `lib/features/watch/`
- **Then** no hay ninguna (fuera de comentarios explicativos que documenten el diferimiento)
- **Test target**: revisión manual en PR
- **REQ**: REQ-WC-CX-002

---

### REQ-WC-CX-003 — Sin mecánicas fuera de scope del producto

Ninguna superficie de este change (chip, DTO, app watchOS) DEBE introducir Retos, Missions, Bets, Levels/XP, ni ninguna mecánica de Gamificación general.

#### SCENARIO-WC-016: revisión confirma ausencia de mecánicas out-of-scope
- **Given** el diseño de la app watchOS y el DTO
- **When** se revisan contra la lista de out-of-scope de `docs/product.md`
- **Then** ninguna mecánica prohibida aparece
- **Test target**: revisión manual en PR / design review
- **REQ**: REQ-WC-CX-003

---

### REQ-WC-CX-004 — Copy en es-AR con marcador

Todo string user-facing nuevo en Dart DEBE estar en es-AR y llevar el comentario `// i18n: watch-connectivity` adyacente.

#### SCENARIO-WC-017: strings nuevos llevan el marcador i18n
- **Given** cualquier archivo `.dart` nuevo de este change con un string user-facing
- **When** se inspecciona el archivo
- **Then** hay al menos un comentario `// i18n: watch-connectivity` adyacente al string
- **Test target**: revisión manual en PR
- **REQ**: REQ-WC-CX-004

---

### REQ-WC-CX-005 — Strict TDD

Cada commit de implementación DEBE estar precedido por un commit RED (test que falla) antes del commit GREEN.

#### SCENARIO-WC-018: commit RED precede a GREEN en el git log
- **Given** cualquier par de tareas de `tasks.md` (cuando exista)
- **When** se revisa el git log de este change
- **Then** el commit del archivo de test aparece antes del commit de implementación
- **Test target**: git log, revisión manual en PR
- **REQ**: REQ-WC-CX-005

---

### REQ-WC-CX-006 — Conventional commits, sin atribución de IA

Todos los commits DEBEN seguir el formato `tipo(scope): mensaje` y NO DEBEN incluir `Co-Authored-By` ni ninguna atribución de IA.

#### SCENARIO-WC-019: mensajes de commit son conventional y sin atribución
- **Given** cualquier commit de este change
- **When** se lee el mensaje
- **Then** sigue el formato `tipo(scope): descripción`
- **And** no contiene líneas `Co-Authored-By`
- **Test target**: git log, revisión manual en PR
- **REQ**: REQ-WC-CX-006

---

### REQ-WC-CX-007 — Presupuesto de LOC por PR

Cada PR DEBE mantenerse en ≤ 400 líneas modificadas (adiciones + borrados) o llevar `size:exception` aprobado explícitamente.

#### SCENARIO-WC-020: PR#1 dentro del presupuesto
- **Given** el diff de PR#1 en GitHub
- **When** se suman adiciones + borrados
- **Then** el total es ≤ 400 líneas (estimado ~420 — ver open question en `design.md` sobre partirlo)
- **Test target**: diff de GitHub, revisión manual
- **REQ**: REQ-WC-CX-007

#### SCENARIO-WC-021: PR#2 dentro del presupuesto
- **Given** el diff de PR#2 en GitHub
- **When** se suman adiciones + borrados
- **Then** el total es ≤ 400 líneas (estimado ~160, sin contar el proyecto Xcode nativo que no cuenta como LOC Dart)
- **Test target**: diff de GitHub, revisión manual
- **REQ**: REQ-WC-CX-007

---

### REQ-WC-CX-008 — Target watchOS como prerequisito manual

El target watchOS en Xcode DEBE tratarse como un prerequisito manual, out-of-band, que bloquea el smoke end-to-end pero NO el merge de código Dart — mismo patrón que la APNs key en `push-notifications-fcm`.

#### SCENARIO-WC-022: smoke end-to-end requiere el target watchOS existente
- **Given** PR#1 y PR#2 mergeados, sin target watchOS creado todavía
- **When** se intenta un smoke test completo (reloj mostrando la sesión)
- **Then** no es posible — se documenta como bloqueado por el prerequisito manual, no como bug de código
- **Test target**: smoke manual, documentado en PR
- **REQ**: REQ-WC-CX-008

---

## Additional Scenarios — Edge Cases

#### SCENARIO-WC-023: reconexión reenvía el contexto completo
- **Given** el reloj estaba `unreachable` durante una sesión activa y vuelve a estar `reachable`
- **When** el bridge detecta el cambio de `isReachable` a `true`
- **Then** se reenvía el `WatchSessionDto` completo actual (no se asume que el reloj tenga el último estado)
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-001

#### SCENARIO-WC-024: fin de sesión limpia el contexto del reloj
- **Given** una sesión activa siendo reflejada en el reloj
- **When** el usuario termina/cancela la sesión desde el teléfono
- **Then** se envía un contexto vacío/neutral (o una acción `sessionEnded`) para que el reloj no quede mostrando una sesión fantasma
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-001

#### SCENARIO-WC-025: logSet con valores fuera de rango se valida igual que desde el teléfono
- **Given** `set_limits.dart` define rangos válidos de reps/peso
- **When** llega un `logSet` del reloj con un valor fuera de rango
- **Then** `sessionNotifier.logSet` aplica la misma validación que ya aplica para inputs del teléfono (sin un camino paralelo sin validar)
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-003

#### SCENARIO-WC-027: múltiples logSet consecutivos no duplican series
- **Given** un `logSet` ya procesado para la serie actual
- **When** llega un segundo mensaje `logSet` idéntico (reintento de red del lado del reloj)
- **Then** el comportamiento es el mismo que si el usuario tocara "completar" dos veces en el teléfono — no hay lógica especial de deduplicación en el bridge (delegada a `SessionNotifier`, si existe)
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-003

#### SCENARIO-WC-028: dispose de la sesión cancela las subscripciones del bridge
- **Given** `watchBridgeLifecycleProvider` con subscripciones activas a `incomingMessages` e `isReachable`
- **When** el provider se destruye (`autoDispose` al salir de `session_player_screen`)
- **Then** ambas subscripciones se cancelan sin leak
- **Test target**: `test/features/watch/application/watch_bridge_providers_test.dart`
- **REQ**: REQ-WC-BRIDGE-001

---

## Coverage Matrix

| REQ ID | Descripción | SCENARIOs | PR |
|---|---|---|---|
| REQ-WC-DEP-001 | Única dependencia `watch_connectivity` | WC-001 | PR#1 |
| REQ-WC-DATA-001 | Forma del `WatchSessionDto` | WC-002 | PR#1 |
| REQ-WC-BRIDGE-001 | sendContext en transiciones relevantes | WC-003, WC-004, WC-023, WC-024, WC-028 | PR#1 |
| REQ-WC-BRIDGE-002 | Sin updates continuos por segundo | WC-005 | PR#1 |
| REQ-WC-BRIDGE-003 | logSet despacha a SessionNotifier | WC-006, WC-025, WC-027 | PR#1 |
| REQ-WC-BRIDGE-004 | completeSet avanza la sesión | WC-007 | PR#1 |
| REQ-WC-BRIDGE-005 | Acción desconocida se ignora | WC-008, WC-009 | PR#1 |
| REQ-WC-BRIDGE-006 | Reloj no inicia sesión | WC-010 | PR#1 |
| REQ-WC-UI-001 | Chip refleja isReachable/isPaired | WC-011, WC-012, WC-026 | PR#2 |
| REQ-WC-UI-002 | Cero HEX / PhosphorIcons directo | WC-013 | PR#2 |
| REQ-WC-CX-001 | Comportamiento correcto sin reloj | WC-014 | PR#1 + PR#2 |
| REQ-WC-CX-002 | Sin activación Android/Wear OS | WC-015 | PR#1 + PR#2 |
| REQ-WC-CX-003 | Sin mecánicas out-of-scope | WC-016 | PR#2 |
| REQ-WC-CX-004 | Copy es-AR con marcador | WC-017 | PR#2 |
| REQ-WC-CX-005 | Strict TDD | WC-018 | ambos |
| REQ-WC-CX-006 | Conventional commits, sin atribución IA | WC-019 | ambos |
| REQ-WC-CX-007 | Presupuesto LOC por PR | WC-020, WC-021 | ambos |
| REQ-WC-CX-008 | Target watchOS como prerequisito manual | WC-022 | fuera de banda |

---

## Open Questions for Design

1. Punto exacto de inicialización de `watchBridgeLifecycleProvider` (eager en `app.dart` vs lazy/autoDispose en `session_player_screen`).
2. Shape exacto del `Map<String,dynamic>` para cada acción entrante (`logSet`, `completeSet`) — claves y tipos.
3. Mecanismo concreto de "detectar cambio relevante" para el throttling de REQ-WC-BRIDGE-001/002 (comparación campo a campo vs. igualdad estructural del DTO).

---

## Hard Constraints

1. Única dependencia nueva: `watch_connectivity`.
2. NO Wear OS/Android activado, probado ni documentado como soportado en v1.
3. NO el reloj puede iniciar una sesión.
4. NO actualizaciones continuas por segundo del descanso — solo transiciones.
5. Cero HEX literals, cero `PhosphorIcons.X` directo.
6. Copy es-AR con marcador `// i18n: watch-connectivity`.
7. Strict TDD — RED antes que GREEN.
8. Conventional commits, sin atribución de IA.
9. PRs ≤ 400 LOC o `size:exception`.
10. Target watchOS es un prerequisito manual — bloquea smoke, no bloquea merge.
11. Cero mecánicas de Retos/Missions/Bets/Gamificación en cualquier superficie de este change.

---

## Artifact References

- File: `openspec/changes/watch-connectivity/spec.md`
- Proposal: `openspec/changes/watch-connectivity/proposal.md`
- Explore: `openspec/changes/watch-connectivity/explore.md`
