# Proposal: watch-standalone-client

**Change**: watch-standalone-client
**Branch**: `feat/workout-watch-connectivity` (existente; renombrable a `feat/watch-standalone-client`)
**Depende de**: `openspec/changes/watch-standalone-client/explore.md`
**Supersede**: `openspec/changes/watch-connectivity/` — se conserva intacto como registro

---

## 1. TL;DR

Construir una app watchOS **autónoma** que permita iniciar un entrenamiento, cargar series, finalizarlo y ver un resumen **sin la app del teléfono abierta**. Como Firebase no soporta Firestore en watchOS, el reloj habla la **REST API de Firestore** con un ID token de Firebase Auth — las Security Rules existentes se aplican sin cambios. Eso implica portar la lógica de sesión a Swift y construir persistencia offline y reconciliación propias. **Es un segundo cliente, no una feature**: se fasea por corte de riesgo, con un spike que puede matar la arquitectura antes de invertir en ella.

---

## 2. Motivation

`session_player_screen.dart` se usa en el momento de mayor fricción física del producto: en medio de una serie, con las manos ocupadas. Hoy eso exige sacar el teléfono. La pedida del dueño es que el reloj sea suficiente para todo el entreno, con el teléfono como vista de detalle — incluso con el celular guardado en la mochila.

---

## 3. Scope

### In Scope

- App watchOS nativa (Swift/SwiftUI), target nuevo en Xcode.
- Auth en el reloj: handoff de credencial desde el teléfono, refresco autónomo contra Firebase Auth.
- Cliente Firestore REST en Swift: leer rutinas, escribir sesiones y series.
- Persistencia local en el reloj (cola de escrituras + estado de sesión) para operar sin red.
- Lógica de sesión portada a Swift: entreno de hoy, carga de series con idempotencia por `exerciseId + setNumber`, finalización, volumen y duración.
- Resumen final en el reloj, acotado a lo que entra sin apretar.
- Fixtures de conformidad compartidos Dart↔Swift (ver Locked Decision #6).

### Out of Scope

- **Wear OS** — decidido con el dueño: v1 es solo Apple Watch. Además arrastra arreglar la firma de release de Android (hoy en debug keys, `android/app/build.gradle:36`), porque el paquete exige misma clave entre reloj y teléfono.
- Complications de watch face.
- HealthKit / heart rate / biométricos.
- Notificaciones push al Watch.
- Edición de rutinas desde el reloj.
- Retos / Missions / Bets / Gamificación — prohibidos en todo el producto; el reloj no es excepción.

---

## 4. Locked Decisions

> Estas decisiones **necesitan sign-off del dueño antes de `spec`**. El ciclo anterior falló precisamente por bloquear decisiones que nadie revisó.

| # | Decisión | Propuesto | Justificación |
|---|---|---|---|
| 1 | Transporte de datos del reloj | REST API de Firestore con `Authorization: Bearer <ID token>` | Verificado: Firestore no tiene SDK de watchOS; la REST API acepta ID tokens de Firebase Auth y **las Security Rules se aplican**, así que `firestore.rules` cubre al reloj sin modelo paralelo. |
| 2 | Auth en el reloj | El teléfono entrega la credencial una vez vía WatchConnectivity; el reloj la guarda en su Keychain y refresca solo | Google Sign-In no tiene SDK de watchOS. Exigir login propio dejaría sin reloj a todos los usuarios de Google. El pairing pide el teléfono una vez; después el reloj es autónomo. |
| 3 | Iniciar entreno desde el reloj | SÍ, un botón "empezar el de hoy" | `todays_routine_provider.dart` ya resuelve el día que toca. No hace falta picker. Revierte la Locked Decision #3 del ciclo anterior, que se apoyaba en una premisa falsa. |
| 4 | Finalizar entreno incompleto | El reloj replica el `StateError`: no finaliza si `isFullyCompleted` es false | Mantener una sola regla de negocio. Relajarla en el reloj crea sesiones que el teléfono considera inválidas. |
| 5 | Alcance de la lógica portada en v1 | Rutinas de una semana, sin `addSet`/`removeSet` en vivo desde el reloj | `setCountOverride` y la resolución por semana son la parte más sutil del dominio. Portarlas de entrada multiplica la superficie de divergencia. El teléfono sigue pudiendo todo. |
| 6 | Control de divergencia | Fixtures de conformidad compartidos en CI desde la fase 1 | Riesgo #1 del explore. Los mismos escenarios JSON corridos contra Dart y Swift; si una implementación cambia y la otra no, CI se pone rojo. Sin esto, el historial se corrompe en silencio. |
| 7 | Conflicto reloj↔teléfono | Dedupe por `exerciseId + setNumber`, sin merge; last-write-wins a nivel sesión | Es la identidad lógica que `logSet` ya usa. Un merge real exige CRDTs o timestamps por campo — desproporcionado para v1. |
| 8 | Rest timer en vivo | SÍ, el reloj cuenta localmente | Siendo autónomo, el reloj tiene el estado; no hay costo de tráfico. Revierte la Locked Decision #7 del ciclo anterior, cuyo problema (saturar `updateApplicationContext`) ya no aplica. |

---

## 5. Fases (corte por riesgo, no por capa)

| Fase | Entrega | Qué riesgo mata |
|---|---|---|
| **F0 — Spike de cimientos** | Target watchOS + handoff de credencial + **una** escritura autenticada a Firestore vía REST que pase las rules | Prueba o mata la arquitectura entera antes de invertir. Si las rules rechazan o el handoff no cierra, se replantea acá y no en el mes 3. |
| **F1 — Lectura + conformidad** | El reloj lee la rutina y muestra el entreno de hoy. Fixtures de conformidad Dart↔Swift en CI. | Divergencia (riesgo #1), desde el principio y no como deuda. |
| **F2 — Sesión local** | Modelo de sesión en Swift + persistencia local: iniciar, cargar series, contar descanso. Sin escribir a Firestore todavía. | La lógica portada, aislada de la red. |
| **F3 — Escrituras + cola** | Cola de escrituras con reintento, dedupe por `exerciseId + setNumber`, sincronización. | Que el historial quede bien venga de donde venga — la condición explícita del dueño. |
| **F4 — Finalizar + resumen** | `finish` con volumen y duración, resumen en la muñeca. | Cierre del flujo completo. |

**F0 es la fase que importa.** Si algo va a tumbar esto, es ahí, y es barato descubrirlo ahí.

---

## 6. Prerequisitos out-of-band

1. Target watchOS creado en Xcode (`File → New → Target → Watch App`) — dev con Mac.
2. iPhone + Apple Watch **físicos**. El simulador no es confiable para pairing/reachability (mismo patrón "no emulable" que FCM).
3. Team Apple `J66AQRRM96`, bundle `com.backhaus.treino`. El firmado automático ya viene funcionando.

---

## 7. Risks & Mitigations

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| 1 | Divergencia Dart↔Swift de las reglas de negocio | **ALTA** | Locked Decision #6 — fixtures de conformidad en CI desde F1. |
| 2 | `firestore.rules` nunca se probó contra escrituras REST | ALTA | F0 lo verifica primero. Ojo con el patrón conocido del repo: reglas testeadas pero no desplegadas, fallando mudas. |
| 3 | Auth de usuarios Google en el reloj | MEDIA | Locked Decision #2 — handoff desde el teléfono. |
| 4 | Sin persistencia offline de Firestore: cola y conflictos a mano | MEDIA | F3 dedicada. Dedupe por identidad lógica ya existente. |
| 5 | Firebase watchOS es community-supported, sin SLA | MEDIA | Solo se usa Auth del SDK; los datos van por REST, que es API estable de Google. |
| 6 | Escala: es un segundo cliente | **ALTA** | Faseado con corte de riesgo. F0 puede matar el proyecto barato. |
| 7 | Gamificación colándose en la superficie nueva | BAJA | REQ explícito en spec. |

---

## 8. Success Criteria

- [ ] F0: una escritura del reloj llega a Firestore y **las rules la aceptan**, con el celular sin la app abierta.
- [ ] Entreno completo de punta a punta desde la muñeca: iniciar → cargar series → finalizar → resumen.
- [ ] El historial queda correcto venga del reloj o del teléfono, verificado con ambos orígenes en la misma rutina.
- [ ] Fixtures de conformidad verdes en CI para Dart y Swift.
- [ ] Tests Dart existentes siguen verdes (~4748). `flutter analyze` 0 issues. `dart format .` limpio.
- [ ] Cero HEX literals, cero `PhosphorIcons.X` directo en lo que toque Flutter.
- [ ] Conventional commits, sin `Co-Authored-By` ni atribución de IA.

---

## 9. Open Questions (para el dueño, antes de `spec`)

1. ¿Firmás las 8 Locked Decisions, en particular la #5 (v1 sin rutinas multi-semana ni edición de series en vivo desde el reloj)?
2. ¿F0 arranca ya, o primero querés ver el spec completo?
3. El branch actual se llama `feat/workout-watch-connectivity` y ya no describe el change. ¿Lo renombro?

---

## 10. Artifact References

- Exploración: `openspec/changes/watch-standalone-client/explore.md`
- Superseded: `openspec/changes/watch-connectivity/` (intacto)

**Status**: esperando sign-off del dueño sobre las Locked Decisions. **No avanzar a `spec` sin eso** — es exactamente el error que hundió el ciclo anterior.
