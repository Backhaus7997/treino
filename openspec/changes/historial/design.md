# Design: Historial (Fase 4 · Etapa 4)

**Change**: `historial` · **Branch (target)**: `feat/historial`
**SCENARIOs**: 355..~378 · **REQs**: `REQ-HIST-NNN`
**Owner**: Dev A (Martín) · **Project**: treino
**Artifact store**: hybrid · **Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: chained PRs (PR-A list, PR-B detail)

## Technical Approach

Dos superficies UI sobre el data layer **ya existente** — sin tocar dominio, repos, providers, `firestore.rules`, ni `pubspec.yaml`:

1. **Lista** (`HistorialSection`, `ConsumerWidget`) embebida dentro de `WorkoutScreen`. Consume `sessionsByUidProvider(uid)` (FutureProvider.family de Etapa 1, retorna `List<Session>` newest-first), filtra client-side `status == SessionStatus.finished`, y renderiza un card por sesión. Reemplaza la clase privada `_HistorialSection` actual del placeholder. Sin set count en el card → cero N+1.
2. **Detalle** (`SessionDetailScreen`, `ConsumerWidget`) en ruta top-level `/workout/historial/:sessionId` (fuera del `ShellRoute`, sin bottom bar) — patrón idéntico al session player y al post-workout summary. Consume `sessionSummaryProvider({uid, sessionId})` (FutureProvider.autoDispose.family ya existente, retorna `({Session? session, List<SetLog> setLogs})` con un único loading state via `Future.wait`). Agrupa los SetLogs client-side por `exerciseName` preservando orden.

Strings centralizados en `WorkoutStrings` (ya existente). Date formatting via Map lookup inline en un helper compartido **scoped al feature** (`presentation/utils/date_helpers.dart`) — sin agregar `intl` al pubspec, sin contaminar `lib/core/`. PR badge del detalle = stub visual privado del archivo, sin parámetros, sin lógica de comparación con sesiones previas (queda como dependencia explícita a Insights / Etapa 5).

Entrega en **dos PRs encadenados** (PR-A lista + router stub, PR-B detalle real) — el budget de 400 LOC por PR no entra en una sola unidad.

## Data Flow — Lista

    WorkoutScreen
        │
        └── HistorialSection (ConsumerWidget)
                │
                ├──(watch)── currentUidProvider ──► String? uid
                │                   │
                │                   ▼
                ├──(watch)── sessionsByUidProvider(uid ?? '')
                │                   │
                │                   ├── AsyncLoading  ─► _ListLoadingState
                │                   ├── AsyncError    ─► _ListErrorState (retry: ref.invalidate)
                │                   └── AsyncData(List<Session> all)
                │                                  │
                │                                  ▼
                │                       finished = all.where(s => s.status == finished)
                │                                  │
                │                          ┌───────┴───────┐
                │                       empty           non-empty
                │                          │               │
                │                          ▼               ▼
                │                   _ListEmptyState   ListView.builder(
                │                   (CTA → /workout       _HistorialCard(session) × N
                │                    routines tab)    )
                │
                └── tap card ──► context.push('/workout/historial/${session.id}')

## Data Flow — Detalle

    /workout/historial/:sessionId
        │
        ▼
    SessionDetailScreen(sessionId)  [ConsumerWidget, top-level fuera de ShellRoute]
        │
        ├──(watch)── currentUidProvider ──► uid (no-uid case → NotFound)
        │
        ├──(watch)── sessionSummaryProvider((uid, sessionId))
        │                   │
        │                   ├── AsyncLoading                ─► _DetailLoadingState
        │                   ├── AsyncError                  ─► _DetailErrorState (retry)
        │                   └── AsyncData({session, setLogs})
        │                                  │
        │                          session == null
        │                          ┌───────┴───────┐
        │                         yes              no
        │                          ▼               ▼
        │                   _DetailNotFound   _DetailLoaded(session, setLogs)
        │                                          │
        │                                          ├── _DetailHeader (back + fecha + hora + routineName)
        │                                          ├── _StatRow (4 StatTiles: MIN, SETS, KG, PRS=0)
        │                                          └── groupBy exerciseName (LinkedHashMap)
        │                                                  │
        │                                                  ▼
        │                                          ListView.builder(
        │                                             _ExerciseBlock(name, sets, prBadge=stub) × N
        │                                          )
        │
        └── back arrow ──► context.canPop() ? context.pop() : context.go('/workout')

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| 1 | Provider de lista | Reutilizar `sessionsByUidProvider(uid)` + filtro client-side `status == finished` | (a) Nuevo método `listFinishedByUid` en repo; (b) Nuevo provider derivado en `session_providers.dart` | Out-of-scope tocar repo o providers. El proposal lo prohíbe explícito. Volúmenes alfa chicos: filter en memoria es O(n) sobre decenas de items. |
| 2 | Provider de detalle | Reutilizar `sessionSummaryProvider({uid, sessionId})` ya existente | Provider nuevo dedicado a detalle | Ya retorna `({Session? session, List<SetLog> setLogs})` con `Future.wait` — exactamente el contrato que necesita el detalle. Misma key shape (record) que el resto del módulo. |
| 3 | Not-found contract en detalle | `data.session == null → _DetailNotFound` (no se mira `setLogs`) | Mirar también `setLogs.isEmpty` | Mismo patrón que `PostWorkoutSummaryScreen`. Una sesión existente puede tener `setLogs` vacíos si fue abandonada sin sets → eso NO es "not found", es "loaded con cero sets". |
| 4 | `formatSessionDate` location | `lib/features/workout/presentation/utils/date_helpers.dart` (feature-scoped) | (a) Inline duplicado en lista y detalle; (b) `lib/core/utils/date_format_helpers.dart` (global) | Lo usan dos consumers del mismo feature → extracción evita duplicación. NO global: no hay otro feature que lo consuma, y `lib/core/` debe permanecer limpio de policies feature-específicas. Función pura, sin Riverpod, sin `BuildContext`. |
| 5 | `formatSessionDate` signature | `String formatSessionDate(DateTime date, {DateTime? now})` con default `DateTime.now()` | Sin parámetro `now` | Inyección de `now` hace el helper unit-testeable con casos determinísticos. `now` queda sin uso real en esta etapa porque NO hay lógica "Hoy"/"Ayer", pero deja el hook listo para Insights sin breaking change. |
| 6 | Formato de fecha | `"Mié 27 nov"` (DOW abrev + día + mes abrev en español, lookup por Map) | (a) "Hoy / Ayer / X días atrás"; (b) Agregar `intl` al pubspec | El mockup muestra exactamente `"Mié 27 nov"`. "Hoy/Ayer" es nice-to-have NO presente en el mockup → fuera de scope. Agregar `intl` por una sola string es overkill. |
| 7 | Agrupación de SetLogs por ejercicio | `LinkedHashMap<String, List<SetLog>>` poblada en orden de aparición | (a) `Map<String, List<SetLog>>` + sort manual; (b) `groupBy` de package:collection | `listSetLogs` ya retorna ordered by `setNumber` ASC. Agrupar en una `LinkedHashMap` preserva ese orden sin sort adicional. No agregar dependencias. `package:collection` ya está transitivamente disponible pero no se requiere. |
| 8 | Estado widget para ambas screens | `ConsumerWidget` (stateless reactive) | `StatefulWidget` / `ConsumerStatefulWidget` | No hay estado mutable local — el único estado son los providers Riverpod. No hay animaciones controladas, no hay scroll controllers compartidos, no hay timers. |
| 9 | PR badge stub | Widget privado `_PrBadgeStub` sin parámetros, render colored chip con texto "PR" | (a) `_PrBadge(bool isPr)`; (b) `_PrBadge(int prCount)` | Es visual constant para esta etapa. Sin lógica → sin parámetros. El nombre `_PrBadgeStub` documenta que es placeholder y facilita el grep para el wire-up de Insights (Etapa 5). |
| 10 | Back navigation en detalle | `context.canPop() ? context.pop() : context.go('/workout')` | (a) `context.pop()` siempre; (b) `context.go('/workout')` siempre | Hace la screen deep-linkable (entrada directa por URL en web → sin back stack → fallback a `/workout`) sin romper el caso normal (entrada desde la lista → `pop()` mantiene la stack). Mismo patrón que `RoutineDetailScreen`. |
| 11 | Router placement | GoRoute top-level entre `/workout/session-summary/:sessionId` (línea 160) y la apertura del `ShellRoute` (línea 167) | (a) Dentro del ShellRoute como sub-route de /workout; (b) Después de las rutas /feed dentro del shell | Out of ShellRoute → sin bottom bar (immersive, match con mockup). Físicamente junto a session player + summary → agrupa todas las immersive routes del feature workout en un mismo bloque visual del archivo. Patrón ya validado. |
| 12 | PR-A router body | Stub `Center(Text('Detalle — próximamente'))` con copy explícito | (a) `SizedBox.shrink()`; (b) Throw / placeholder vacío | Si PR-A queda mergeado y PR-B se demora, un usuario que tape un card y aterrice en el detalle ve copy intencional, no un error ni una pantalla vacía. Mitigación del risk listado en el proposal. |
| 13 | Loading state — lista | `Padding + Center(CircularProgressIndicator(color: palette.accent))` dentro del slot de la sección | Full-screen spinner / Skeleton de cards | La lista vive embedded en WorkoutScreen, no es full-screen. El spinner local respeta el resto del scaffold (heading "HISTORIAL" sigue visible). Skeleton sería más pulido pero no aporta info real — la carga es una query Firestore, latencia chica. |
| 14 | Loading state — detalle | Full-screen `Center(CircularProgressIndicator(color: palette.accent))` | Skeleton matching layout | Mismo criterio que `PostWorkoutSummaryScreen` (Decision 10 de ese design): el detalle es full-screen, no hay contenido parcial que mostrar, spinner es honesto. |
| 15 | Error state retry | `ref.invalidate(sessionsByUidProvider(uid))` y `ref.invalidate(sessionSummaryProvider((uid: uid, sessionId: sessionId)))` respectivamente | Local RetryNotifier / variable de estado | Riverpod-native, zero extra state surface. Mismo patrón que post-workout-summary. |
| 16 | wasFullyCompleted indicator | `TreinoIcon.checkCircle` (color positivo / accent) si `true`, `TreinoIcon.warningCircle` (color muted) si `false` | Solo mostrar cuando `true` | Mockup muestra dos icons distintos → la presencia del icon "abandoned" informa al usuario que esa sesión existe pero no se completó. Hide-on-false sería información perdida. Iconos concretos a verificar contra el mockup en apply (puede usarse `TreinoIcon.check` / `TreinoIcon.x` si el catálogo no tiene los anteriores). |
| 17 | Filtro `status == finished` lugar | Aplicado en el `.when(data: ...)` de `HistorialSection`, ANTES de evaluar empty | En el provider / en el repo | Out of scope tocar provider o repo (Decision 1). Aplicar el filtro antes del check de empty evita renderizar "1 sesión" cuando hay 1 sesión pero está en `inProgress` o `abandoned`. |
| 18 | Empty state CTA target | `context.go('/workout')` (queda en el mismo tab, scrollea a sección "Tus rutinas") | Navegar a una ruta específica de routines | No hay ruta dedicada de "empezar entrenamiento" — el flow es: ver rutinas → tap rutina → tap día → empieza session. El CTA solo necesita que el usuario quede en el contexto correcto. En la práctica el CTA ya estás en /workout, así que el tap es casi un no-op cosmético — opción: scroll-to-top o no-op. Decisión final: no-op visual (botón sigue siendo el affordance), el usuario ve las rutinas arriba de la sección. |

## File Layout

### New files

**`lib/features/workout/presentation/widgets/historial_section.dart`** — PR-A
- Public class `HistorialSection extends ConsumerWidget`.
- Renders: heading `WorkoutStrings.historialHeading` + body switch on `AsyncValue<List<Session>>`.
- Private states: `_ListLoadingState`, `_ListErrorState(onRetry)`, `_ListEmptyState`, `_HistorialCard(session)`.
- No public API beyond the constructor — internals are package-private.

**`lib/features/workout/presentation/session_detail_screen.dart`** — PR-B
- Public class `SessionDetailScreen extends ConsumerWidget` with required `String sessionId`.
- Renders: `Scaffold + AppBackground + SafeArea` + body switch on `AsyncValue<({Session?, List<SetLog>})>`.
- Private widgets: `_DetailHeader(session, onBack)`, `_StatRow(session, setLogs)`, `_ExerciseBlock(name, sets)`, `_PrBadgeStub` (no params), `_DetailLoadingState`, `_DetailErrorState(onRetry)`, `_DetailNotFoundState`.
- Public API: `SessionDetailScreen({required this.sessionId, super.key})`.

**`lib/features/workout/presentation/utils/date_helpers.dart`** — PR-A
- Public function `String formatSessionDate(DateTime date, {DateTime? now})`.
- Internal `const Map<int, String> _kDow` (DateTime.weekday 1..7 → "Lun".."Dom") and `_kMonth` (1..12 → "ene".."dic").
- No Riverpod, no BuildContext, no IO. Pure function.

**`test/features/workout/presentation/utils/date_helpers_test.dart`** — PR-A
- Unit tests (`test` group, NOT `testWidgets`).
- Covers: weekday mapping (7 cases) + month mapping (12 cases) + zero-padding-not-applied (single digit day stays as digit, e.g. "Mié 7 mar") + the documented spec example `"Mié 27 nov"` from DateTime(2024, 11, 27).

**`test/features/workout/presentation/widgets/historial_section_test.dart`** — PR-A
- Widget tests (SCENARIO-355..~366).
- ProviderScope overrides: `currentUidProvider`, `sessionsByUidProvider`.

**`test/features/workout/presentation/session_detail_screen_test.dart`** — PR-B
- Widget tests (SCENARIO-367..~378).
- ProviderScope overrides: `currentUidProvider`, `sessionSummaryProvider`.

### Modified files

**`lib/features/workout/workout_screen.dart`** — PR-A
- Remove private class `_HistorialSection` (lines 55-77 per explore).
- Import `package:treino/features/workout/presentation/widgets/historial_section.dart`.
- Replace the `_HistorialSection()` call site with `const HistorialSection()`.

**`lib/features/workout/presentation/workout_strings.dart`** — PR-A (parte lista) + PR-B (parte detalle)
- PR-A adds: `historialHeading`, `historialEmptyTitle`, `historialEmptyCta`, `historialErrorMessage`, `historialErrorRetry`.
- PR-A also adds: card-level labels (`historialCardKgSuffix`, `historialCardMinSuffix`) if needed — current StatTile convention may already cover this.
- PR-B adds: `detailNotFoundTitle`, `detailNotFoundCta`, `detailErrorMessage`, `detailStatMin`, `detailStatSets`, `detailStatKg`, `detailStatPrs`, `detailExerciseSetHeader` (= "SET"), `detailExerciseRepsHeader` (= "REPS"), `detailExerciseKgHeader` (= "KG"), `detailPrBadge` (= "PR" or icon-based label).

**`lib/app/router.dart`** — PR-A (stub) + PR-B (real screen)
- Insert a new top-level `GoRoute` **between line 160 (closing `)` of the session-summary route) and line 162 (the comment opening the ShellRoute section)**.
- PR-A body:
  ```dart
  GoRoute(
    path: '/workout/historial/:sessionId',
    pageBuilder: (context, state) => _noAnim(
      const Center(child: Text('Detalle — próximamente')),
    ),
  ),
  ```
- PR-B body replaces the stub with `SessionDetailScreen(sessionId: state.pathParameters['sessionId']!)`.
- PR-B also adds the import `import '../features/workout/presentation/session_detail_screen.dart';` near the existing workout presentation imports (alphabetical insertion among lines 14-17).

**`test/features/workout/presentation/workout_screen_test.dart`** — PR-A
- Update assertion that currently expects the placeholder text `'Tus entrenamientos completados aparecerán acá.'` (per explore line 88) to expect the new behavior: heading `HISTORIAL` + either empty state copy or rendered cards based on the test's provider override. Override `sessionsByUidProvider` to a deterministic value.

**`test/app/router_workout_routes_test.dart`** — PR-A (route exists + stub renders) + PR-B (route renders detail screen)
- PR-A adds a SCENARIO: navigation to `/workout/historial/abc123` resolves a route that renders `Center` containing `Text('Detalle — próximamente')`, and asserts NO `TreinoBottomBar` is in the tree.
- PR-B updates the same SCENARIO to assert `find.byType(SessionDetailScreen)` instead of the stub text.

## Widget Tree Composition

### HistorialSection (PR-A)

    HistorialSection (ConsumerWidget)
    └── Column (crossAxisAlignment: start)
        ├── Padding → _SectionHeading (Text "HISTORIAL", title style of WorkoutScreen)
        └── Consumer / switch on uid:
            │
            uid == null OR uid.isEmpty
                └── _ListEmptyState (defensive — should not happen post-auth-gate)
            │
            uid valid → ref.watch(sessionsByUidProvider(uid))
                ├── loading  → _ListLoadingState
                │              └── Padding + Center + CircularProgressIndicator
                │
                ├── error    → _ListErrorState(onRetry: () => ref.invalidate(sessionsByUidProvider(uid)))
                │              └── Column: Text(errorMessage) + TextButton(retry)
                │
                └── data(all)
                        finished = all.where(s.status == finished).toList()
                        │
                        finished.isEmpty
                            └── _ListEmptyState
                                └── Column: Text(emptyTitle) + ElevatedButton(emptyCta, onPressed: context.go('/workout'))
                        │
                        finished.isNotEmpty
                            └── ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),  // parent already scrolls
                                  itemCount: finished.length,
                                  itemBuilder: (_, i) => _HistorialCard(session: finished[i]),
                                )

    _HistorialCard (private StatelessWidget)
    └── InkWell(onTap: () => context.push('/workout/historial/${session.id}'))
        └── Container(decoration: card style of AppPalette)
            └── Row
                ├── _CompletedIcon(wasFullyCompleted)
                ├── Expanded(Column: routineName + formatSessionDate(session.startedAt))
                └── Column: Text("${totalVolumeKg.toStringAsFixed(0)} kg") + Text("$durationMin min")

### SessionDetailScreen (PR-B)

    SessionDetailScreen (ConsumerWidget)
    └── Scaffold
        └── AppBackground
            └── SafeArea
                └── switch on AsyncValue:
                    │
                    loading → _DetailLoadingState (Center + CircularProgressIndicator)
                    │
                    error   → _DetailErrorState
                              └── Column: Text(errorMessage) + ElevatedButton(retry → ref.invalidate)
                    │
                    data    → session == null
                                └── _DetailNotFoundState
                                    └── Column: Text(notFoundTitle) + ElevatedButton(notFoundCta → context.go('/workout'))
                              │
                              session != null
                                └── _DetailLoaded
                                    └── CustomScrollView / ListView
                                        ├── _DetailHeader
                                        │   └── Row: IconButton(back, onPressed: _onBack) +
                                        │           Column(crossAxis: start):
                                        │               Text(formatSessionDate(startedAt) + " · " + "HH:mm")
                                        │               Text(routineName, style headline)
                                        ├── _StatRow
                                        │   └── Row: 4× StatTile(label, value)
                                        │       (MIN=durationMin, SETS=setLogs.length, KG=totalVolumeKg, PRS=0)
                                        └── ListView.builder over groupedExercises.entries:
                                            _ExerciseBlock(name, sets)
                                            └── Column
                                                ├── Row: Text(name) + _PrBadgeStub()
                                                ├── Row: headers SET / REPS / KG
                                                └── for each set: Row(setNumber, reps, weightKg)

    _PrBadgeStub (private StatelessWidget, no params)
    └── Container(padding + decoration: chip style of AppPalette.accent)
        └── Text('PR', style: caption)

## Provider Override Strategy in Widget Tests

### Family-aware overrides for `sessionsByUidProvider`

`sessionsByUidProvider` is a `FutureProvider.family<List<Session>, String>`. In `ProviderScope.overrides`, override using:

```dart
sessionsByUidProvider.overrideWith((ref, uid) async => testSessions)
```

This intercepts ALL family keys with the same factory. Tests that need different responses per uid can branch inside the override closure.

### Family-aware overrides for `sessionSummaryProvider`

`sessionSummaryProvider` is a `FutureProvider.autoDispose.family<({Session? session, List<SetLog> setLogs}), ({String uid, String sessionId})>`. Override using:

```dart
sessionSummaryProvider.overrideWith((ref, key) async => (
  session: testSession,
  setLogs: testSetLogs,
))
```

For loading/error/not-found scenarios, return `Future.delayed(...)`, `throw`, or `(session: null, setLogs: const [])` respectively.

### `currentUidProvider`

Simple `Provider<String?>`. Override as:

```dart
currentUidProvider.overrideWithValue('test-uid-123')
```

For "no-uid" defensive scenarios, override with `null` or `''`.

### Test helper recommendation

Define a `_pumpHistorialSection({required List<Session> sessions, String? uid = 'test-uid'})` helper at the top of `historial_section_test.dart` to avoid `ProviderScope` boilerplate across every SCENARIO. Same pattern for the detail screen with `_pumpDetailScreen({Session? session, List<SetLog>? setLogs, ...})`.

## Date Helper — Signature + Test Plan

### Signature

```dart
/// Formats [date] as "DOW DD MMM" using Spanish abbreviated day-of-week
/// and month names (e.g. "Mié 27 nov").
///
/// [now] is accepted for testability; not used in current logic but kept
/// as an optional parameter so future "Hoy" / "Ayer" formatting (Insights
/// Etapa 5) can be added without changing the signature.
String formatSessionDate(DateTime date, {DateTime? now});
```

### Implementation sketch (non-binding — final code lives in apply)

```dart
const Map<int, String> _kDow = {
  1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue',
  5: 'Vie', 6: 'Sáb', 7: 'Dom',
};

const Map<int, String> _kMonth = {
  1: 'ene', 2: 'feb', 3: 'mar', 4: 'abr',
  5: 'may', 6: 'jun', 7: 'jul', 8: 'ago',
  9: 'sep', 10: 'oct', 11: 'nov', 12: 'dic',
};

String formatSessionDate(DateTime date, {DateTime? now}) {
  final dow = _kDow[date.weekday]!;
  final month = _kMonth[date.month]!;
  return '$dow ${date.day} $month';
}
```

### Test plan (unit, NOT widget)

| # | Case | Input | Expected |
|---|---|---|---|
| t1 | Mockup canonical example | `DateTime(2024, 11, 27)` (Wed) | `"Mié 27 nov"` |
| t2 | All weekdays | iterate `DateTime(2024, 1, 1)..DateTime(2024, 1, 7)` | each DOW mapped |
| t3 | All months | 12 dates one per month | each month mapped |
| t4 | Single-digit day | `DateTime(2024, 3, 7)` | `"Jue 7 mar"` (no zero-padding) |
| t5 | Edge — Sunday | `DateTime(2024, 11, 24)` | `"Dom 24 nov"` |
| t6 | `now` parameter unused | call with `now: DateTime(2024, 11, 27)` and without — same date | identical output |

## Empty / Loading / Error / NotFound State Implementations

### Lista (PR-A)

| State | Trigger | Composition |
|---|---|---|
| Loading | `sessionsByUidProvider` returns `AsyncLoading` | `Padding(vertical: 32) → Center → CircularProgressIndicator(color: palette.accent)` — keeps "HISTORIAL" heading above visible. |
| Error | `sessionsByUidProvider` returns `AsyncError` | `Column(center): Text(WorkoutStrings.historialErrorMessage, style: bodyMedium muted) + SizedBox(8) + TextButton.icon(label: historialErrorRetry, onPressed: () => ref.invalidate(sessionsByUidProvider(uid)))`. |
| Empty | `AsyncData([])` OR `AsyncData(all).where(finished).isEmpty` | `Column(center): Text(WorkoutStrings.historialEmptyTitle, style: titleMedium) + SizedBox(12) + ElevatedButton(label: historialEmptyCta, onPressed: () => context.go('/workout'))`. |
| Loaded | `AsyncData` non-empty after filter | `ListView.builder` of `_HistorialCard`s. |

### Detalle (PR-B)

| State | Trigger | Composition |
|---|---|---|
| Loading | `sessionSummaryProvider` returns `AsyncLoading` | Full-screen `Center(CircularProgressIndicator(color: palette.accent))`. |
| Error | `sessionSummaryProvider` returns `AsyncError` | `Column(centered, padding: 24): Text(WorkoutStrings.detailErrorMessage, style: headlineSmall) + SizedBox(16) + ElevatedButton(retry → ref.invalidate(sessionSummaryProvider((uid: uid, sessionId: sessionId))))`. |
| NotFound | `AsyncData((session: null, ...))` | `Column(centered, padding: 24): Text(WorkoutStrings.detailNotFoundTitle, style: headlineSmall) + SizedBox(16) + ElevatedButton(label: detailNotFoundCta, onPressed: () => context.go('/workout'))`. Mirrors `PostWorkoutSummaryScreen` not-found UX. |
| Loaded | `AsyncData((session: !null, setLogs: ...))` | `_DetailLoaded` composition described above. |

## PR-A vs PR-B Boundary

### PR-A `feat/historial-list` (~250 LOC, SCENARIO-355..~366)

**Adds:**
- `lib/features/workout/presentation/widgets/historial_section.dart` (full implementation).
- `lib/features/workout/presentation/utils/date_helpers.dart` (full implementation).
- `lib/app/router.dart` modification: new GoRoute `/workout/historial/:sessionId` with **stub body** `Center(Text('Detalle — próximamente'))`.
- `lib/features/workout/presentation/workout_strings.dart`: lista constants (heading, empty, CTA, error).
- `test/features/workout/presentation/utils/date_helpers_test.dart`: unit tests.
- `test/features/workout/presentation/widgets/historial_section_test.dart`: widget tests SCENARIO-355..~366.

**Modifies:**
- `lib/features/workout/workout_screen.dart`: remove `_HistorialSection`, import `HistorialSection`.
- `test/features/workout/presentation/workout_screen_test.dart`: update placeholder assertion.
- `test/app/router_workout_routes_test.dart`: SCENARIO for the new route (asserts stub renders + no bottom bar).

**Temporarily stubbed (replaced by PR-B):**
- The router body returning `Center(Text('Detalle — próximamente'))` — replaced with `SessionDetailScreen(sessionId: ...)` in PR-B.
- The single router test SCENARIO asserting the stub copy — updated in PR-B to assert `find.byType(SessionDetailScreen)`.

**Mergeability:** PR-A is fully mergeable on its own. The app remains in a coherent state: the list works, taps navigate to a screen with explicit "próximamente" copy. The user sees nothing broken.

### PR-B `feat/historial-detail` (~255 LOC, SCENARIO-367..~378)

**Adds:**
- `lib/features/workout/presentation/session_detail_screen.dart` (full implementation: header, stat row, exercise blocks, PR badge stub, all four states).
- `test/features/workout/presentation/session_detail_screen_test.dart`: widget tests SCENARIO-367..~378.

**Modifies:**
- `lib/features/workout/presentation/workout_strings.dart`: detail constants (header labels, stat labels, exercise headers, PR badge, not-found, error).
- `lib/app/router.dart`: replace the PR-A stub body with `SessionDetailScreen(sessionId: state.pathParameters['sessionId']!)`. Add import.
- `test/app/router_workout_routes_test.dart`: update the existing SCENARIO from asserting stub text to asserting `find.byType(SessionDetailScreen)`.

**Dependencies:** mechanical rebase on PR-A's branch. No logical coupling beyond the router stub swap.

## Router Insertion Point

Concrete byte-level placement based on the current `lib/app/router.dart`:

- **Line 160** is the closing `)` of the `GoRoute(/workout/session-summary/:sessionId)` block.
- **Line 162** is the comment `// ShellRoute with the existing 5 tabs.`.
- **Line 167** is the opening `ShellRoute(` token.

Insert the new GoRoute on a new block **right after line 160 and before line 162** — i.e. as the last immersive top-level workout route in the immersive block:

```dart
      GoRoute(
        path: '/workout/session-summary/:sessionId',
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _noAnim(PostWorkoutSummaryScreen(sessionId: sessionId));
        },
      ),

      // ─── Historial — TOP-LEVEL ROUTE (outside ShellRoute) ─────────────────
      // Immersive: oculta la bottom bar mientras se ve el detalle de una sesión
      // pasada. Patrón idéntico al session player y al session-summary.
      GoRoute(
        path: '/workout/historial/:sessionId',
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          // PR-A: stub. PR-B: SessionDetailScreen(sessionId: sessionId).
          return _noAnim(const Center(child: Text('Detalle — próximamente')));
        },
      ),

      // ShellRoute with the existing 5 tabs.
```

In PR-B the body becomes `_noAnim(SessionDetailScreen(sessionId: sessionId))` and the comment loses the "PR-A: stub" line.

## Testing Strategy

| Layer | What | Approach | PR |
|---|---|---|---|
| Unit | `formatSessionDate` (6 cases) | `test` group, no widget tree | PR-A |
| Widget | `HistorialSection`: heading rendered (1) | `pumpWidget` with `ProviderScope(overrides)` | PR-A |
| Widget | `HistorialSection`: loading state | override `sessionsByUidProvider` with `Future.delayed`, pump without settle | PR-A |
| Widget | `HistorialSection`: error state + retry | override that throws; tap retry; verify `ref.invalidate` was called (state transitions back to loading) | PR-A |
| Widget | `HistorialSection`: empty state (no sessions at all) | override returns `[]` | PR-A |
| Widget | `HistorialSection`: empty state (sessions exist but all `inProgress`) | override returns list of in-progress sessions; verify empty state still renders | PR-A |
| Widget | `HistorialSection`: filter `status == finished` | mixed list (1 finished, 1 in-progress, 1 abandoned); verify exactly 1 card rendered | PR-A |
| Widget | `HistorialSection`: card fields | inject a known session; verify routineName + formatted date + kg + min text | PR-A |
| Widget | `HistorialSection`: wasFullyCompleted indicator (true & false) | two scenarios with different icons asserted | PR-A |
| Widget | `HistorialSection`: tap navigates | wrap in `MaterialApp.router` with `buildRouter`; tap card; assert `find.text('Detalle — próximamente')` (PR-A stub) | PR-A |
| Widget | `HistorialSection`: empty state CTA tap | tap CTA; assert no navigation error (idempotent context.go) | PR-A |
| Router | `/workout/historial/:sessionId` resolves to stub (PR-A) → to `SessionDetailScreen` (PR-B); no bottom bar in tree | full router build with overrides | PR-A/B |
| Widget | `SessionDetailScreen`: loading state | override `sessionSummaryProvider` with `Future.delayed` | PR-B |
| Widget | `SessionDetailScreen`: error state + retry | override that throws | PR-B |
| Widget | `SessionDetailScreen`: not-found state | override returns `(session: null, setLogs: [])` | PR-B |
| Widget | `SessionDetailScreen`: header content | inject session; verify formatted date + hour + routineName text | PR-B |
| Widget | `SessionDetailScreen`: 4 StatTiles values | inject session + setLogs; verify MIN, SETS=count, KG=totalVolumeKg, PRS=0 | PR-B |
| Widget | `SessionDetailScreen`: exercise grouping | inject 2 exercises × 3 sets each (in any order in input list); verify 2 blocks, each with 3 rows | PR-B |
| Widget | `SessionDetailScreen`: PR badge stub renders | verify `find.byType(_PrBadgeStub)` (or `find.text('PR')`) appears once per exercise | PR-B |
| Widget | `SessionDetailScreen`: back nav from stack | enter via router push; tap back; assert pop occurred (still in stack) | PR-B |
| Widget | `SessionDetailScreen`: back nav from deep link | enter via initial location `/workout/historial/abc`; tap back; assert navigated to `/workout` | PR-B |
| Modified | `WorkoutScreen` test: HISTORIAL heading + section renders | override provider; verify section present | PR-A |

Total expected: ~24 SCENARIOs split ~12/~12 across PR-A and PR-B (consistent with proposal estimate 355..~378).

## Strict TDD Plan

Tests are written RED FIRST, then implementation makes them GREEN. Order matters because some tests have dependencies on shared helpers.

### PR-A — RED → GREEN order

1. **RED**: `date_helpers_test.dart` — write 6 unit tests against `formatSessionDate` (file does not exist yet).
2. **GREEN**: create `date_helpers.dart` with the Map lookups → all 6 unit tests pass.
3. **RED**: `historial_section_test.dart` — write the loading + empty + error + filter + card-fields + indicator + tap-navigates SCENARIOs against `HistorialSection` (class does not exist yet).
4. **GREEN**: create `historial_section.dart` with the Consumer widget, private state widgets, and `_HistorialCard` → widget tests pass.
5. **RED**: update `workout_screen_test.dart` assertion to the new behavior (test fails because placeholder still rendered).
6. **GREEN**: modify `workout_screen.dart` — remove `_HistorialSection`, import + use `HistorialSection` → test passes.
7. **RED**: add SCENARIO in `router_workout_routes_test.dart` asserting `/workout/historial/abc` renders stub text + no bottom bar.
8. **GREEN**: add the new GoRoute (stub body) in `router.dart` → router test passes.
9. Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test` green.

### PR-B — RED → GREEN order (assumes PR-A merged & rebased)

10. **RED**: write SCENARIOs in `session_detail_screen_test.dart` for loading + error + not-found + header + stat-tiles + grouping + PR-badge + back-from-stack + back-from-deeplink against `SessionDetailScreen` (class does not exist yet).
11. **GREEN**: create `session_detail_screen.dart` with all internal widgets → widget tests pass.
12. **RED**: update the existing router SCENARIO to assert `find.byType(SessionDetailScreen)` instead of the stub text → test fails.
13. **GREEN**: replace the stub body in `router.dart` with `SessionDetailScreen(sessionId: ...)` and add import → router test passes.
14. Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test` green.

Strict TDD means no production code is written before its corresponding test is red. The order above guarantees that property.

## Risks (Including New Ones Found While Designing)

| Risk | Likelihood | Mitigation |
|---|---|---|
| (from explore) Loading UX no especificado en mockup | Med | Resuelto en Decision 13 & 14: spinner local en lista, full-screen en detalle. |
| (from explore) `workout_screen_test.dart` rompe por placeholder text | High | Resuelto en Decision step PR-A 5-6. |
| (from explore) Agrupación por `exerciseName` falla si el nombre cambia | Low | Cubierto por test de grouping con 2 exercises. |
| (from explore) PR-A queda mergeada y PR-B se demora | Low | Resuelto en Decision 12: copy explícito. |
| (from explore) Date formatting duplicado | Low | Resuelto en Decision 4: helper extraído feature-scoped. |
| (from explore) PR-A excede 400 LOC | Low | Monitorear en apply; el split actual estima 250 LOC. |
| **NEW**: `currentUidProvider` returns `null` durante la transición de logout | Low | Defensive branch en `HistorialSection`: si uid es null/empty, render empty state (no rompe). |
| **NEW**: Iconos exactos para `wasFullyCompleted` true/false en `TreinoIcon` | Low | Decision 16 enumera candidatos; resolución final en apply chequeando el catálogo `TreinoIcon` con `grep`. NO HEX, NO `PhosphorIcons.X` directo. |
| **NEW**: La hora del header del detalle ("HH:mm") requiere formateo no cubierto por `formatSessionDate` | Low | Implementar como string-literal `'${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}'` inline en el `_DetailHeader` (no es público). Si se usa más de una vez, extraer a `formatSessionTime` en `date_helpers.dart`. |
| **NEW**: `LinkedHashMap` insertion order preservation depende de que `listSetLogs` ya devuelva sets agrupados por ejercicio | Med | Verificar en apply: si los sets vienen interleaved entre ejercicios, el LinkedHashMap igual agrupa pero "preserva orden de primera aparición" → resultado correcto. Test de grouping cubre este caso al inyectar input intencionalmente desordenado. |
| **NEW**: `ListView.builder` dentro de un `ListView` padre (WorkoutScreen) requiere `shrinkWrap: true` + `NeverScrollableScrollPhysics` | Med | Documentado en Widget Tree composition. Si WorkoutScreen ya tiene un `SingleChildScrollView` padre, el patrón anida correctamente. Verificar en apply cuando se lea `workout_screen.dart` completo. |
| **NEW**: `context.canPop()` antes de `pop()` requiere que el contexto sea de un GoRouter delegate y no de un Navigator nested | Low | `SessionDetailScreen` es top-level del GoRouter — `canPop` consulta el stack del router. Validado por el test "back nav from deep link". |

## Open Questions

None — todas las decisiones del spec (sessionSummaryProvider not-found contract, ubicación de formatSessionDate, PR badge stub shape, back nav strategy) están explícitamente resueltas arriba en Architecture Decisions #3, #4, #9, #10.

## Review Workload Forecast

- **400-line budget risk**: High en una sola unidad — RESUELTO con chained PRs.
- **Chained PRs recommended**: Yes (PR-A list + PR-B detail).
- **Decision needed before apply**: No — el split y los boundaries quedan locked en este design.
- **Estimated changed lines**: PR-A ~250 / PR-B ~255 / total ~505.
- **Delivery strategy**: chained PRs (already cached at orchestrator level).
