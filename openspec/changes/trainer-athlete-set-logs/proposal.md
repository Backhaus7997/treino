# Proposal: trainer-athlete-set-logs

## Problem / Why now

PT research recommendation 8.6 ("Máxima") calls for a **bidirectional data channel** between
athlete and trainer (PF). The athlete already logs real loads — weight, reps, RPE per
exercise/set — into `users/{athleteUid}/sessions/{sessionId}/setLogs/{...}` every time they
train. Today the PF can see the athlete's session *headers* (date, name, duration, volume) but
**cannot see a single logged set**. The PF is coaching blind: they prescribe routines but never
see what the athlete actually lifted.

This is the read-side counterpart to the share the athlete already grants ("Compartir historial
con mi PF" → `session_shares/{athleteId}.trainerId`). The athlete opted in; the rule just never
extended that grant down to `setLogs`. It pairs naturally with the trainer↔athlete chat work as
the second leg of the bidirectional channel: chat = words, set-logs = numbers.

Now is the moment because the data, the share mechanism, and the cross-user repository method all
already exist. The only true blocker is a 3-line Firestore rule. Everything else is wiring and a
widget extraction.

## Intent

Let the PF who is **named in the athlete's `session_shares` doc** open any of that athlete's
finished sessions and read its real logged sets, grouped by exercise — **read-only**, on **both
surfaces**:

- **Web** (`coach_hub` → Alumno detail → Entrenamientos tab): expand a session row to reveal its sets.
- **Mobile** (`coach` → Athlete detail): wire the missing session history, then per-session set detail.

Success = a linked+sharing PF taps a session and sees the same exercise/set breakdown the athlete
sees in their own session detail; a non-linked trainer is denied at the rule layer; an athlete who
hasn't shared shows a friendly "no compartió" placeholder instead of an error.

## In scope

**Shared foundation**
- Extend `firestore.rules` `setLogs` read to mirror the parent session-share rule (write stays owner-only).
- New `coachSessionSetLogsProvider` (FutureProvider.autoDispose.family keyed on `{athleteUid, sessionId}`) over the already-cross-user `SessionRepository.listSetLogs`.
- Extract the private `_ExerciseBlock` + `_SetRow` from `session_detail_screen.dart` into a shared public widget `lib/features/workout/presentation/widgets/session_exercise_block.dart`.
- New i18n keys (es-AR / es / en) for the expansion labels, the empty-session state, and the "athlete hasn't shared" placeholder.

**Web** (`alumno_detail_screen.dart`, `_EntrenamientoTab` → `_HistorialTable`)
- Make finished-session rows tap-to-expand; on expand, load setLogs via the new provider and render them grouped by exercise using the shared widget. Replace the "Próximamente: evolución por ejercicio" placeholder for this slice.

**Mobile** (`athlete_detail_screen.dart`)
- Wire the athlete's finished-session history (it has **none** today — no `sessionsByUidProvider` reference exists in this file) and add per-session setLog detail using the shared widget.

## Out of scope (explicit)

- Per-exercise progression chart / PR tracking over time. `lastWeightByExerciseProvider` scans
  up to 15 sessions; reusing/exposing it for the PF is a separate, heavier phase. Not here.
- The per-exercise "evolución" analytics (PR, volumen, frecuencia) hinted at in the existing
  web placeholder — only the raw set breakdown is in scope.
- The PF **editing** the athlete's logs. This is strictly read-only; `setLogs` write stays owner-only.
- Multi-trainer sharing. `session_shares/{athleteId}` holds a single `trainerId` by design.
- Re-using `SessionDetailScreen` as-is for the PF (it hardcodes `currentUidProvider`, which would
  resolve to the PF's own uid → rule denial). That is precisely why we extract widgets instead.

## Proposed approach

1. **Rule (security core).** In `firestore.rules` (currently line 508-510), change the `setLogs`
   read predicate to mirror the session rule at lines 502-505:
   ```
   match /setLogs/{setLogId} {
     allow read: if request.auth != null
                 && (request.auth.uid == uid
                     || (exists(/databases/$(database)/documents/session_shares/$(uid))
                         && get(/databases/$(database)/documents/session_shares/$(uid)).data.trainerId == request.auth.uid));
     allow write: if request.auth != null && request.auth.uid == uid;
   }
   ```
   Write stays owner-only. This is intentionally identical to the proven session-share read pattern —
   lowest risk, no migration, no denormalization (Option B rejected in exploration).

2. **Provider.** Add `coachSessionSetLogsProvider` to `session_providers.dart`, a thin
   `FutureProvider.autoDispose.family<List<SetLog>, ({String athleteUid, String sessionId})>`
   delegating to `ref.read(sessionRepositoryProvider).listSetLogs(...)`. Distinct from the
   self-uid `sessionSummaryProvider`/`activeSessionForUidProvider` so the PF path is explicit and
   greppable. No change to `lastWeightByExerciseProvider`.

3. **Widget extraction.** Move `_ExerciseBlock` + `_SetRow` to a public
   `SessionExerciseBlock` widget in `lib/features/workout/presentation/widgets/`. It is already
   pure (props: `exerciseName`, `List<SetLog> sets`; uses `AppPalette.of(context)`, no provider
   reads). `session_detail_screen.dart` then consumes the shared widget — behavior-preserving
   refactor, verified by the existing session-detail tests.

4. **Web wiring.** Convert `_HistorialTable` rows to expansion tiles. On expand, watch
   `coachSessionSetLogsProvider((athleteUid: athleteId, sessionId: s.id))`; render loading /
   data (shared widget) / empty / permission-denied states inline.

5. **Mobile wiring.** Add a session-history section to `athlete_detail_screen.dart` backed by
   `sessionsByUidProvider(athleteId)` (filtered to finished), each tappable into setLog detail
   via the same provider + shared widget. This is the heavier slice — it introduces the session
   list that does not exist on mobile today.

6. **i18n.** Add keys to `intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb` for: expand/collapse
   affordance label, empty-session ("no registró sets"), and the not-shared placeholder. Copy via
   `AppL10n` only — no hardcoded strings.

## Affected surface (grouped by PR)

**PR-A — Shared foundation + Web (cheaper; session history already exists on web)**
- `firestore.rules` — setLogs read extension (~3 lines)
- `lib/features/workout/application/session_providers.dart` — add `coachSessionSetLogsProvider`
- `lib/features/workout/presentation/widgets/session_exercise_block.dart` — NEW shared widget
- `lib/features/workout/presentation/session_detail_screen.dart` — consume shared widget (remove privates)
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` — tap-to-expand in `_EntrenamientoTab`/`_HistorialTable`
- `lib/l10n/intl_es_AR.arb` + `intl_es.arb` + `intl_en.arb` — new keys
- Tests: `session_repository_test.dart` (cross-uid read), new provider test, session-detail widget refactor test, web `_EntrenamientoTab` expansion test

**PR-B — Mobile athlete_detail (stacked on PR-A)**
- `lib/features/coach/presentation/athlete_detail_screen.dart` — wire finished-session history + per-session setLog detail (reuses PR-A's provider + shared widget)
- Tests: mobile athlete-detail history/detail widget tests

## Risks & mitigations

- **Security (critical).** A wrong/non-linked trainer must receive permission-denied. The rule
  reuses the already-verified session-share predicate, but rule correctness is only provable via
  the Firebase emulator and there is **no automated rules harness** — covered by emulator-deferred
  scenarios at verify (athlete reads own; linked+sharing PF reads; linked-but-revoked PF denied;
  unrelated trainer denied; any write by PF denied).
- **One-trainer share limit.** `session_shares` stores a single `trainerId`. By design; surfaced
  as a "no compartió" placeholder when the doc is absent.
- **No-share / revoked → permission-denied.** UI must treat permission-denied as the friendly
  "athlete hasn't shared" state, not a generic error. Explicit error-mapping in both surfaces.
- **Mobile scope.** `athlete_detail_screen.dart` has no session provider wired today (confirmed:
  no `sessionsByUidProvider` reference) — PR-B adds it, hence the heavier estimate.
- **No accidental reuse of `SessionDetailScreen`** — it hardcodes `currentUidProvider`; widget
  extraction is the deliberate avoidance.

## Success criteria / acceptance

1. A linked+sharing PF expands an athlete's finished session and sees its sets grouped by exercise, on **both** web and mobile.
2. A non-linked trainer attempting the same read is denied at the rule layer.
3. An athlete who hasn't shared (no `session_shares` doc) shows the friendly placeholder, not an error.
4. `setLogs` writes by anyone other than the owner remain denied.
5. `session_detail_screen.dart` renders identically after the widget extraction (no visual regression).
6. Quality gate green: `flutter analyze` 0 issues, `dart format .` clean, `flutter test` passing.

## Test strategy (Strict TDD ACTIVE)

- **Data layer:** extend `session_repository_test.dart` to assert `listSetLogs` works for an
  athleteUid ≠ caller (cross-uid path) against the fake/mock Firestore.
- **Application layer:** new test for `coachSessionSetLogsProvider` (delegates to repo with the
  family key; autoDispose).
- **Presentation layer:** widget test for the refactored `SessionExerciseBlock`; web
  `_EntrenamientoTab` expansion test (tap → loading → data / empty / permission-denied);
  mobile athlete-detail history + detail tests (PR-B).
- **Rules (emulator-deferred):** the 5 security scenarios above are documented for manual
  emulator verification at the verify phase — no harness exists, so they are NOT automated here.

## Delivery / size note (chained PRs, ask-on-risk)

Recommended **chained-PR split**:
- **PR-A** (foundation + web): ~180-240 changed lines. Cheaper because web session history already
  exists — only adds the expansion. Independently shippable and reviewable.
- **PR-B** (mobile): ~140-200 changed lines, stacked on PR-A. Heavier per-feature because it must
  introduce the session-history list that mobile lacks today.

Combined this lands around ~320-440 lines, brushing the 400-line review budget; the split keeps
each PR comfortably reviewable and lets the higher-risk rule + web slice land and bake before the
mobile slice. If the team prefers, PR-A alone delivers user value (PFs on web see real loads) and
PR-B can follow independently. Single PR is viable only if the team accepts a `size:exception`.
