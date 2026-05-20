# Proposal: coach-link-lifecycle

**Change**: Fase 5 · Etapa 3 — Link lifecycle UI (athlete view + trainer dashboard)
**Branch**: `feat/coach-link-lifecycle`
**Owner**: Dev B
**Date**: 2026-05-20
**Depends on**: Etapa 1 (✅ #54). NO depende de Etapa 2 (Discovery) — el CTA "PEDIR VÍNCULO" vive en TrainerPublicProfile que Dev A está construyendo y se conecta al repo cuando ambos PRs estén en main.

---

## 1. Why

La capa de datos (TrainerLink + repo + providers) ya está en main desde Etapa 1. Falta la UI para que:

- El **atleta** vea su PF actual (si tiene uno) en la tab Coach. Ahora mismo la `AthleteCoachView` es un placeholder hardcoded.
- El **PF** vea sus **solicitudes pendientes** + **alumnos activos** en la tab Coach. La `TrainerCoachView` actual tiene 4 sub-tabs todas placeholder.

Sin esta UI, no hay forma de aceptar/rechazar requests ni de ver el vínculo, aunque el repo lo soporte.

---

## 2. What

### Production deliverables

**`AthleteCoachView` rewrite** (`lib/features/coach/athlete_coach_view.dart`):
- Si `currentAthleteLinkProvider` devuelve null → renderiza `TrainersListScreen` directamente (entry natural al flow de Discovery; el athlete elige PF desde acá)
- Si devuelve un TrainerLink con `status == active` → card con info del PF (nombre + avatar) leído via `userPublicProfileProvider(trainerId)` + botón "Terminar vínculo" (con confirm dialog)
- Si devuelve un TrainerLink con `status == pending` → card "Solicitud enviada. Esperando confirmación." con botón "Cancelar solicitud" (→ termina)
- Si está en error → mensaje "No pudimos cargar tu vínculo."

**`TrainerContactCtaStub` wire-up** (`lib/features/coach/presentation/widgets/trainer_contact_cta_stub.dart`):
- Etapa 2 (Dev A, #59) mergeó dejando el stub diferido a Etapa 3 ("Real implementation deferred to Etapa 3 per spec").
- Acá lo conectamos a `trainerLinkRepositoryProvider.request(trainerId, athleteId)`.
- Disabled-state cuando el athlete ya tiene link en `pending` o `active` con cualquier PF (regla MVP: un athlete → un PF a la vez). Label contextual: "SOLICITUD PENDIENTE" / "TU PERSONAL TRAINER" / "YA TENÉS UN PF".

**`TrainerCoachView` rewrite** (`lib/features/coach/trainer_coach_view.dart`):
- Mantener la `TabBar` con 4 sub-tabs.
- **DASHBOARD**: lista de solicitudes pendientes (cards con avatar + nombre del atleta + botones aceptar/rechazar) + resumen "Tenés N alumnos activos"
- **ALUMNOS**: lista de active links — cada card con avatar + nombre + botón "terminar vínculo"
- **AGENDA**, **COMUNIDADES**: siguen como placeholder (Agenda llega en Etapa 6; Comunidades = out of scope de Fase 5)

**Widgets privados** (decisión durante implementación: separar por estado en vez de un widget configurable; menos branching, más claridad):
- `_LinkStateCard` (athlete) — card del PF con info + acción según `status`.
- `_PendingRequestCard` (trainer) — card de request entrante con botones ACEPTAR / RECHAZAR.
- `_ActiveAlumnoCard` (trainer) — card de alumno activo con botón TERMINAR VÍNCULO.
- Confirm dialog (terminar / cancelar) → inline en `athlete_coach_view.dart` (helper `_confirm`) y en `trainer_coach_view.dart`. No se extrajo a widget reusable — dos call-sites no justifican la abstracción.

**No new providers necesarios** — todos los necesarios ya están en main (`currentAthleteLinkProvider`, `trainerLinksStreamProvider`, `userPublicProfileProvider`, `trainerLinkRepositoryProvider`).

### Test deliverables

- `test/features/coach/athlete_coach_view_test.dart` — refactor del que ya existe + casos para 3 estados (no link → discovery / pending / active).
- `test/features/coach/trainer_coach_view_test.dart` — refactor + casos para Dashboard (con/sin requests pendientes, contador) + Alumnos (con/sin activos).
- Tests de cards específicas viven inline en los tests de la vista padre (no se extrajo widget reusable — ver §3).

---

## 3. How

### Athlete view layout

```dart
ConsumerWidget {
  build:
    final linkAsync = ref.watch(currentAthleteLinkProvider);
    return linkAsync.when(
      loading: () => spinner,
      error: (_, __) => errorState,
      data: (link) {
        if (link == null) return _NoLinkState();
        // Look up trainer's public profile
        final pubAsync = ref.watch(userPublicProfileProvider(link.trainerId));
        return pubAsync.when(
          data: (pub) => _LinkActiveCard(link: link, trainer: pub),
          ...
        );
      },
    );
}
```

`_NoLinkState`: placeholder con call-to-action sugerido (sin acción todavía — el "Buscar PF" será un push a la pantalla de Discovery cuando Dev A la merge).

### Trainer view structure

DASHBOARD tab usa `trainerLinksStreamProvider` para tener real-time updates:
- Filtrar status=pending → top section "Solicitudes pendientes (N)"
- Filtrar status=active → bottom "Tenés N alumnos activos" + tap "Ver todos" cambia a tab ALUMNOS

ALUMNOS tab usa el mismo stream filtrado a status=active.

### Action handlers

- `accept(linkId)`: read repo, call accept, invalidate `trainerLinksStreamProvider` (la stream se actualiza solo via snapshot — quizá no hace falta invalidate)
- `decline(linkId)`: idem
- `terminate(linkId)`: con confirm dialog primero
- En athlete view, "Cancelar solicitud" → terminate (status pending pasa a terminated con reason='cancelled-by-athlete')

Espera — el repo actual no acepta `terminate` sobre status=pending. Hay que extender: ¿agregamos un método `cancel(linkId)` específico para que athlete cancele su propio request?

Decisión: SÍ — agregar `cancel(linkId)` al repo. Tres líneas, valida status=pending y athleteId. Lo agregamos en este PR (extensión menor del repo) en vez de bloquear o usar workaround.

---

## 4. Trade-offs aceptados (3 decisiones)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Agregar `TrainerLinkRepository.cancel(linkId)`** en este PR | El use case (athlete cancela su propio request) es válido y el repo de Etapa 1 no lo cubrió. Lo agregamos acá en vez de hacer un repo extension PR aparte. Tres líneas extra. |
| 2 | **Wire-up del CTA "PEDIR VÍNCULO" SÍ va en este PR** | Etapa 2 (Dev A, #59) mergeó dejando el stub diferido a Etapa 3 per el comentario en el archivo original. Acá lo conectamos a `trainerLinkRepositoryProvider.request(...)` con disabled-state cuando el athlete ya tiene link pending/active. |
| 3 | **Real-time stream para PF, FutureProvider para athlete** | El PF necesita ver requests entrantes al instante (productividad). El athlete tiene un único link — `FutureProvider.autoDispose` recalcula al abrir la tab Coach y es suficiente. Stream para single doc sería overkill. |

---

## 5. Out of scope

| Item | Lands en |
|---|---|
| In-app notifications cuando el PF acepta/rechaza | Fase 6 (push notifications) |
| Mensaje opcional al pedir vínculo | Iteración futura |
| Resume del vínculo (paused → active) | Iteración futura — el status `paused` existe pero no se expone |
| AGENDA tab | Etapa 6 |
| COMUNIDADES tab | Out of scope de Fase 5 entera |

---

## 6. Success criteria

- [ ] AthleteCoachView muestra empty state cuando no hay link
- [ ] AthleteCoachView muestra info del PF + botón terminar cuando link activo
- [ ] AthleteCoachView muestra "esperando confirmación" + botón cancelar cuando link pending
- [ ] TrainerCoachView DASHBOARD lista requests pendientes con accept/decline
- [ ] TrainerCoachView DASHBOARD muestra contador de alumnos activos
- [ ] TrainerCoachView ALUMNOS lista active links con botón terminar
- [ ] Tap accept transiciona pending → active visualmente (stream se actualiza solo)
- [ ] Tap decline transiciona pending → terminated y se quita de la lista
- [ ] Tap terminate (con confirm) transiciona active → terminated
- [ ] Tap cancelar (athlete sobre pending) transiciona pending → terminated con reason
- [ ] `flutter analyze` 0 issues
- [ ] Tests pasan + suite full
- [ ] Theme correcto: `AppPalette.of(context)`, `TreinoIcon.X`, spacing `{8,12,14,18,20}`

---

## 7. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | `trainerLinksStreamProvider` puede emitir mucho durante testing (cada cambio en cualquier link del PF) | autoDispose lo limpia. En prod, un PF típico tiene <50 links. Acceptable. |
| 2 | Sin onboarding del PF (Etapa 2), no podemos smoke-test cuando un athlete crea un request | Testing manual requiere crear el request via Firebase Console o dejar un debug-only botón en AthleteCoachView con un trainerId hardcoded. Pre-merge lo sacamos. |
| 3 | El nuevo método `cancel(linkId)` puede romper si Firestore rules no lo permiten | Rules actuales permiten update por members con immutables sanos. `cancel` setea status='terminated' + terminationReason — rules pasan. |

---

## 8. LOC estimate

| Bucket | LOC aprox |
|---|---|
| AthleteCoachView refactor | ~120 |
| TrainerCoachView refactor (Dashboard + Alumnos) | ~200 |
| `_TrainerLinkCard` widget | ~80 |
| `_ConfirmTerminateDialog` | ~30 |
| Repo extension (`cancel`) | ~25 |
| Tests | ~400 |
| **Total** | **~855** |

Single PR razonable con `size:exception` si es necesario.
