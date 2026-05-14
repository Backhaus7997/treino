# Spec — home-wire-routines

**Change**: `home-wire-routines`
**Fase / Etapa**: Fase 2 · Etapa 5 (cierre)
**Branch**: `feat/home-wire-routines`
**Artifact store**: openspec
**Source**: propose.md (locked decisions A–F)

---

## Scope

Delta spec: what MUST be true after this change is applied. Design-phase skipped per proposal (scope is trivial — one callback wire, three docstring cleanups, one test replacement).

Files in scope: `empezar_entrenamiento_card.dart`, `home_cta_button.dart`, `esta_semana_card.dart`, `empezar_entrenamiento_card_test.dart`.

Files explicitly NOT in scope: `router.dart`, `home_screen.dart`, `workout_screen.dart`, any provider.

---

## Requirements

### REQ-HOME-WIRE-001 — CTA wires to /workout

`EmpezarEntrenamientoCard` MUST pass a non-null `onPressed` callback to `HomeCTAButton` that calls `context.go('/workout')` when invoked.

**Scenario 1.1 — tap navigates to /workout**

```
GIVEN EmpezarEntrenamientoCard pumped inside MaterialApp.router
  with GoRouter(initialLocation: '/home', routes: [
    GoRoute('/home', builder: (_,__) => Scaffold(body: EmpezarEntrenamientoCard())),
    GoRoute('/workout', builder: (_,__) => const Scaffold(body: Text('WORKOUT'))),
  ])
WHEN HomeCTAButton is tapped AND pumpAndSettle completes
THEN find.text('WORKOUT') findsOneWidget
```

**Scenario 1.2 — tap throws no exception**

```
GIVEN same router setup as 1.1
WHEN HomeCTAButton is tapped AND pumpAndSettle completes
THEN no exception is thrown
```

**Constraints:**
- Navigation idiom MUST be `context.go` (cross-tab replace, NOT `context.push`).
- Target route MUST be `/workout` (PlantillasSection root).
- Logic MUST be inline in `EmpezarEntrenamientoCard.build` as a lambda — not lifted to `HomeScreen`.

---

### REQ-HOME-WIRE-002 — Remove REQ-HOME-EMPEZAR-004 (tap no-op)

The test block `REQ-HOME-EMPEZAR-004: tap no-op — no exception, no navigation` in `test/features/home/widgets/empezar_entrenamiento_card_test.dart` MUST be removed.

Its replacement is the widget test that asserts REQ-HOME-WIRE-001 (scenario 1.1 and 1.2 above), added in the SAME commit as the `onPressed` wire.

**Constraint (atomicity):** The removal of `REQ-HOME-EMPEZAR-004` and the addition of the REQ-HOME-WIRE-001 navigation test MUST land in a single commit. Splitting them causes the old test to crash because `context.go` without a `GoRouter` in the tree throws.

No new scenario is defined here — this REQ documents the deletion obligation.

---

### REQ-HOME-WIRE-003 — EstaSemanaCard rendered content unchanged

`EstaSemanaCard` MUST render identically to its current state after this change. Only its docstring comment ("deferred to Etapa 5") may be edited; no functional or visual change is permitted.

**Scenario 3.1 — static content present**

```
GIVEN EstaSemanaCard pumped inside MaterialApp with AppTheme.dark()
WHEN the widget tree is inspected
THEN find.text('ESTA SEMANA') findsOneWidget
 AND find.textContaining('Todavía no entrenaste') findsOneWidget
```

This scenario is a non-regression contract. Existing tests that cover `EstaSemanaCard` MUST continue to pass unmodified.

---

### REQ-HOME-WIRE-004 — HomeCTAButton public API unchanged

`HomeCTAButton`'s public constructor parameters (`label: String`, `onPressed: VoidCallback?`, `leadingIcon: IconData?`) MUST NOT change signature, type, or default values.

**Scenario 4.1 — existing HomeCTAButton tests pass unmodified**

```
GIVEN the existing home_cta_button_test.dart test suite
WHEN run after this change
THEN all tests pass without any modification to the test file
```

---

### REQ-HOME-WIRE-005 — No regression in home_screen_test.dart

All tests in `test/features/home/home_screen_test.dart` MUST continue to pass after this change without modification.

**Scenario 5.1 — full suite passes**

```
GIVEN test/features/home/home_screen_test.dart run after this change
WHEN flutter test executes
THEN all 7 tests pass (0 failures, 0 errors)
```

**Note:** `home_screen_test.dart` uses plain `MaterialApp` (no GoRouter). It does NOT tap `HomeCTAButton`, so wiring `onPressed` does not affect it. This assumption MUST remain valid — the test file MUST NOT be modified to add GoRouter.

---

## Docstring cleanup obligations (non-functional)

These are not testable requirements but MUST be satisfied before the PR is merged:

- `empezar_entrenamiento_card.dart` line ~96: remove comment `// CTA — onPressed is null until Etapa 5 wires navigation`.
- `home_cta_button.dart`: remove doc note referencing "add isLoading in Etapa 5 wire".
- `esta_semana_card.dart`: remove doc note referencing "deferred to Etapa 5".

After the change, no file in scope may contain references to "Etapa 5" as a pending TODO.

---

## Test shape (canonical)

The new test for REQ-HOME-WIRE-001 MUST mirror `routine_card_test.dart:94-128`:

```dart
testWidgets('REQ-HOME-WIRE-001: tap navigates to /workout', (tester) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: EmpezarEntrenamientoCard()),
      ),
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(body: Text('WORKOUT')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
  );
  await tester.pump();

  await tester.tap(find.byType(HomeCTAButton));
  await tester.pumpAndSettle();

  expect(find.text('WORKOUT'), findsOneWidget);
});
```

No `ProviderScope` needed — `EmpezarEntrenamientoCard` is a `StatelessWidget` with no Riverpod dependency.

---

## Out-of-scope (explicit exclusions)

- `EstaSemanaCard` data-driven content (streak, muscle map, stats) — Fase 4.
- `home_header.dart` string replacements — Fase 4.
- `HomeCTAButton.isLoading` — YAGNI (navigation is synchronous).
- Changes to `router.dart` — `/workout` already exists.
- Integration test of full `HomeScreen` — disproportionate cost for this scope.

---

## Success criteria (observable, post-merge)

1. Tap on "EMPEZAR ENTRENAMIENTO" from `HomeScreen` navigates to `/workout`.
2. `TreinoBottomBar` reflects Workout tab active after the tap.
3. New widget test (REQ-HOME-WIRE-001) passes with GoRouter mock.
4. `flutter analyze` → 0 issues.
5. `dart format .` → no pending changes.
6. `home_screen_test.dart` and all other pre-existing tests pass unmodified.
7. No file in scope references "Etapa 5" as a pending action.
