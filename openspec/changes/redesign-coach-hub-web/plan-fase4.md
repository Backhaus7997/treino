# Plan Fase 4 — Solicitudes e Invitaciones (Coach Hub Web)

> Artefacto de diseño (design/architecture). Fase 4 cerrada — WU-01 a WU-07 completos (commit del plan por WU-07).
> Backend activo: hybrid (engram `sdd/redesign-coach-hub-web/plan-fase4` + este archivo).

## 1. Dirección visual (norte)

Mockups leídos como imágenes:

- `docs/web-trainer/screens/solicitudes/view-general.png` — bandeja de solicitudes: header "SOLICITUDES" con subtítulo de conteo, **tabs de estado** (PENDIENTES · RESPONDIDAS · CONVERTIDAS · ARCHIVADAS con contadores) + **sub-chips de plan** (TODAS/ONLINE/PREMIUM/PREMIUM TRIM), y una **lista de tarjetas** por solicitud: avatar circular + nombre + edad/ciudad + badge de tag, mensaje libre, tags de objetivo, "hace 2 horas", y acciones verticales ACEPTAR (píldora accent) / RESPONDER / ARCHIVAR. Sidebar muestra "SOLICITUDES" con badge de pendientes.
- `docs/web-trainer/screens/solicitudes/detalles.png` — panel de detalle: cuestionario inicial, "% de match/conversión", plantilla de respuesta editable, fuente (Instagram), checklist "si acepto". **~90% es data inventada.**

Norte visual honesto: reproducir la ESTRUCTURA (header CAPS + chips de estado con contadores + lista de tarjetas por solicitud con avatar/nombre/tiempo/acciones) con el kit v2, dark+light pulidos, motion de estados y selección. **NO** reproducir el feed rico de mensajes/tags/plan-tier ni el detalle con cuestionario/%match/plantilla: no existen en el modelo (ver ADR-F4-03). Cuando mockup y design system chocan, MANDA el design system.

## 2. Realidad del código (censo de la sección)

**La sección es un placeholder puro.** `lib/features/coach_hub/presentation/sections/invitaciones/` contiene SOLO `routes.dart`, que renderiza `ProximamenteScreen(label: 'Invitaciones')`. Fue **removida del sidebar en la reducción W2** (`sidebar_registry.dart` la excluye; `sidebar_item.dart` lo documenta). La ruta `/invitaciones` sí está registrada en `coach_hub_router.dart` (`...invitacionesRoutes`).

Directorio real de la sección: **`invitaciones/`** (no existe `solicitudes/`). Se mantiene el nombre de directorio/ruta por estabilidad; la copia de usuario es "Solicitudes"/"SOLICITUDES" (ADR-F4-01).

### Capa de datos REAL (ya existe, no se crea backend)

- `trainerLinksStreamProvider` — `StreamProvider.autoDispose<List<TrainerLink>>` (real-time de los vínculos del PF). Definido en `lib/features/coach/application/trainer_link_providers.dart`.
- `TrainerLink` (`lib/features/coach/domain/trainer_link.dart`, freezed): `id, trainerId, athleteId, status, requestedAt, acceptedAt?, terminatedAt?, terminationReason?, pausedAt?, sharedWithTrainer`. **No hay** texto de mensaje, %conversión, edad, ciudad, plan-tier, ni cuestionario.
- `TrainerLinkStatus` (`lib/features/coach/domain/trainer_link_status.dart`): `pending | active | paused | terminated`.
- `TrainerLinkRepository` (`lib/features/coach/data/trainer_link_repository.dart`): `accept(id)` (pending→active), `decline(id)` (pending→terminated `declined`), `cancel`, `terminate`, `pause`, `resume`, `watchForTrainer`.
- `userPublicProfileProvider(athleteId)` → `displayName`, `avatarUrl` (para render de la tarjeta).
- `trainerLinkRepositoryProvider` para las acciones.

### Referencia espejo (patrón exacto a seguir)

`lib/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart` — usa el MISMO `trainerLinksStreamProvider` y **excluye explícitamente `pending`** con el comentario "esos son solicitudes, sección aparte". **Fase 4 es esa contraparte**: la bandeja de solicitudes `pending` del PF. Reutilizar de ahí el patrón: `TreinoStateSwitcher` sobre `.when`, `TreinoFilterChips` con `badgeCounts`, `TreinoSectionHeader`, `TreinoFadeSlideIn`+`AppMotion.stagger` para header/chips (NO la lista), `showTreinoDialog`/`TreinoDialog` para confirmación, `_confirmAction` helper.

El dashboard ya rediseñó el tile de pendiente en `sections/dashboard/widgets/dashboard_pending.dart` (keys `pending_request_*`/`accept_*`/`decline_*`, estado busy con spinner, snackbars con l10n existentes). Sirve como plantilla de la tarjeta y de las acciones.

### `.when` con spinner seco / duplicaciones

No hay spinner seco propio (la sección es placeholder). El riesgo de duplicación es re-implementar el tile de pendiente del dashboard: se extrae un `SolicitudCard` del kit de la sección (WU-03) que el dashboard PODRÍA adoptar luego (fuera de scope Fase 4). Segundo copy-paste del tile = componente.

## 3. Arquitectura de la fase

Patrón: **screen de sección Riverpod (sin Scaffold, ADR-CHW-005) → StateSwitcher sobre stream → lista de tarjetas del kit**. Capas:

```
routes.dart (/invitaciones) ──► InvitacionesScreen (ConsumerWidget)
   │                                 │
   │  TreinoSectionHeader (SOLICITUDES + count)   [FadeSlideIn stagger 0]
   │  TreinoFilterChips (Pendientes/Aceptadas/Rechazadas + counts) [stagger 1]
   │  TreinoStateSwitcher
   │     ├─ loading → TreinoListRow(loading) x N (shimmer)
   │     ├─ empty   → TreinoEmptyState (honesto por tab)
   │     ├─ error   → retry (invalidate trainerLinksStreamProvider)
   │     └─ data    → Column de SolicitudCard(filtrados por tab)
   │
   ├─ solicitudes_providers.dart
   │     ├─ SolicitudTab { pendientes, aceptadas, rechazadas }
   │     ├─ matchesSolicitudTab(TrainerLink, SolicitudTab)  (pura)
   │     ├─ _solicitudTabProvider (StateProvider, default pendientes)
   │     └─ invitacionesPendingCountProvider (Provider<int?>)  ──► badge sidebar
   │
   └─ widgets/solicitud_card.dart (presentational)
         avatar + nombre + requestedAt relativo + status pill
         pending → botones Aceptar/Rechazar (busy state) via callbacks
         aceptada/rechazada → read-only (historial)
```

Data flow: `trainerLinksStreamProvider` → filtro por tab → por fila `userPublicProfileProvider(athleteId)` → acciones `trainerLinkRepositoryProvider.accept/decline` con `TreinoDialog` de confirmación + snackbar (l10n existentes) → el stream real-time saca la tarjeta (feedback animado por `TreinoStateSwitcher`/rebuild).

Boundaries limpios (ADR-F4-02): **Solicitudes = bandeja de triage** (solo `pending` es accionable: aceptar/rechazar). **Alumnos = gestión de vínculos activos** (pause/terminate). Las tabs Aceptadas/Rechazadas de Solicitudes son **historial read-only** (sin acciones de gestión), no duplican Alumnos.

### ADRs

- **ADR-F4-01 (naming dir vs producto)**: el directorio y la ruta se quedan `invitaciones`/`/invitaciones` por estabilidad (evita churn de router/tests). La copia de usuario es "Solicitudes"/"SOLICITUDES" (término producto = mockup). Screen: `invitaciones_screen.dart` / `InvitacionesScreen` (consistencia con `alumnos_screen.dart`). Rechazado: renombrar dir/ruta a `solicitudes` (churn innecesario en `coach_hub_router.dart`, imports y tests).

- **ADR-F4-02 (tabs honestos)**: 3 chips `TreinoFilterChips` single-select con `badgeCounts` reales derivados del stream: **Pendientes** = `status==pending`; **Aceptadas** = `status==active||paused` (vínculo que nació de un accept); **Rechazadas** = `status==terminated`. Se colapsan las tabs del mockup "RESPONDIDAS"/"CONVERTIDAS" en "Aceptadas" y se **dropean** los sub-chips de plan (ONLINE/PREMIUM/PREMIUM TRIM: no hay plan-tier en el modelo). Default = Pendientes. La superposición de "Aceptadas" con el roster de Alumnos es **intencional** (lente de resultado de la solicitud, read-only), no duplicación de gestión. Rechazado: 4 tabs del mockup (sin data para "respondidas"/"convertidas").

- **ADR-F4-03 (sin detalle rico)**: `detalles.png` (cuestionario inicial, %match/conversión, plantilla de respuesta, fuente Instagram, checklist) es data inventada — **no existe** en `TrainerLink` ni en ningún provider (mismo principio ADR-D2-01 del dashboard). NO se construye pantalla de detalle. La tarjeta expone TODOS los campos reales (avatar, nombre, `requestedAt` relativo, status); las acciones (aceptar/rechazar) son inline con confirmación `TreinoDialog`. El detalle rico queda fuera de alcance hasta que exista un modelo de cuestionario. Rechazado: inventar el detalle (viola honestidad del rediseño).

- **ADR-F4-04 (badge + re-exposición en sidebar)**: existe provider real (`pending count` derivable) → se cablea el badge. Se crea `invitacionesPendingCountProvider` (`Provider<int?>`) y se setea en `invitacionesSidebarItems[0].badgeProvider`; se **re-agrega** `...invitacionesSidebarItems` a `sidebar_registry.dart`. Esto revierte parcialmente la reducción W2 SOLO para este item, justificado porque Fase 4 entrega la sección real. La infra `_Badge` (renderiza `badgeProvider` cuando `count>0`) ya existe en `coach_hub_sidebar.dart`. **Blast radius conocido**: `test/features/coach_hub/presentation/shell/sidebar_registry_test.dart` afirma `sidebarRegistry.length == 8` → pasa a 9 (el WU-06 actualiza el test y la lista esperada). Fallback si rompe demasiados tests cross-sección: dejar el screen + provider pero diferir la re-exposición (ADR revisado). Rechazado: badge falso/placeholder (hay data real).

- **ADR-F4-05 (l10n congelado)**: `lib/l10n/*` es PROHIBIDO (no se toca). Se **reutilizan** keys existentes para acciones/feedback: `coachHubActionAccept`, `coachHubActionReject`, `coachHubActionCancel`, `coachHubDashboardAcceptSuccess/Error`, `coachHubDashboardRejectSuccess/Error`, `coachHubSectionLoadError`, `coachRetryLabel`, `a11yAvatarLabel`, `commonProcessing`. Literales nuevos de UI (título "SOLICITUDES", labels de chips, empties) se hardcodean en es-AR con marca `// i18n: Fase W1`, igual que el resto del hub.

- **ADR-F4-06 (motion e interacción)**: header+chips entran con `TreinoFadeSlideIn`+`AppMotion.stagger` (eager, bounded); la **lista NO** usa stagger per-item (regla: nunca stagger en listas potencialmente largas). Selección de chip anima (built-in `TreinoFilterChips`). Cambio de estado/tab cross-fadea con `TreinoStateSwitcher` (childKey por estado+tab). Carga = `TreinoListRow(loading:true)` (shimmer del kit). Tarjeta usa `TreinoInteractiveState` del kit (hover/pressed/focus + Semantics + teclado) — **NO** `TreinoTappable` core (WARNING sistémico agendado aparte). Feedback de aceptar/rechazar: busy spinner en la tarjeta (patrón dashboard) + snackbar; la remoción de la tarjeta la anima el rebuild del stream.

## 4. Data-map (mockup → real)

| Mockup | Real | Acción |
|---|---|---|
| Header "SOLICITUDES · N pendientes" | `TreinoSectionHeader(count)` + count pending del stream | Construir |
| Tabs PENDIENTES/RESPONDIDAS/CONVERTIDAS/ARCHIVADAS | 3 chips Pendientes/Aceptadas/Rechazadas (ADR-F4-02) | Colapsar |
| Sub-chips TODAS/ONLINE/PREMIUM/PREMIUM TRIM | — (no plan-tier) | Dropear |
| Avatar + nombre | `userPublicProfileProvider` (avatarUrl/displayName) | Construir |
| Edad · Ciudad · badge tag | — (no en modelo) | Dropear |
| Mensaje libre + tags objetivo | — (no en modelo) | Dropear |
| "hace 2 horas" | `requestedAt` relativo | Construir |
| ACEPTAR / RESPONDER / ARCHIVAR | Aceptar (`accept`) / Rechazar (`decline`) | RESPONDER dropeado (no hay chat de solicitud); ARCHIVAR = Rechazar |
| Detalle (cuestionario/%match/plantilla) | — | Dropear (ADR-F4-03) |
| Badge sidebar | `invitacionesPendingCountProvider` | Cablear (ADR-F4-04) |

## 5. Archivos

Nuevos:
- `lib/features/coach_hub/presentation/sections/invitaciones/invitaciones_screen.dart`
- `lib/features/coach_hub/presentation/sections/invitaciones/solicitudes_providers.dart`
- `lib/features/coach_hub/presentation/sections/invitaciones/widgets/solicitud_card.dart`
- `test/evidence/coach_hub_solicitudes_evidence_test.dart`
- Tests unit/widget correspondientes bajo `test/features/coach_hub/presentation/sections/invitaciones/`

Modificados:
- `lib/features/coach_hub/presentation/sections/invitaciones/routes.dart` (real screen + badgeProvider + label)
- `lib/features/coach_hub/presentation/shell/sidebar_registry.dart` (re-agregar item)
- `test/features/coach_hub/presentation/shell/sidebar_registry_test.dart` (8→9)

PROHIBIDOS / fuera de scope (NO tocar): `lib/l10n/*`, cualquier `routine_editor/*`, `TreinoTappable` core, tests de usuario listados en el contrato. La sección no contiene archivos de usuario.

## 6. Evidencia visual

Harness espejo de `test/evidence/coach_hub_alumnos_evidence_test.dart`: monta `/invitaciones` dentro de `CoachHubScaffold` real con providers fake POBLADOS (links pending+active+terminated, perfiles), FontLoader `test/fonts/` + Phosphor, guard `EVIDENCE`, comparator a `docs/web-trainer/evidence/fase-4/<dir>/`. Matriz: (dark, light) × (1440x900, 420x900). Excluir `/invitaciones` del loop de `otherPaths` (como alumnos excluye `/alumnos`). El BEFORE captura el `ProximamenteScreen` (realidad actual); el AFTER captura el screen real.

## 7. Work Units (atómicos, secuenciales)

- **WU-01** — Harness de evidencia + goldens BEFORE.
- **WU-02** — `solicitudes_providers.dart` (tab enum + predicado puro + pending count) con TDD.
- **WU-03** — `SolicitudCard` (presentational) con TDD.
- **WU-04** — `InvitacionesScreen` + tab Pendientes (estados + aceptar/rechazar + diálogo). Reemplaza `ProximamenteScreen`.
- **WU-05** — Tabs Aceptadas + Rechazadas (historial read-only, empties honestos, counts, selección).
- **WU-06** — Badge del sidebar + re-exposición del item (+ fix `sidebar_registry_test`).
- **WU-07** — Goldens AFTER + gates full (FULL `flutter test` + `analyze` baseline 42) + commit del plan.

Detalle ejecutable de cada WU: ver el resultado estructurado (`work_units[].scope`).
