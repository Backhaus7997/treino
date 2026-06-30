# Design: trainer-athlete-set-logs

## Technical Approach
Read-only set-log visibility for the linked PF, gated at the rule layer (mirroring the proven session-share predicate) and surfaced on both coach surfaces through ONE shared widget and ONE new cross-user provider. No model, repo, or migration change. Stacked PRs: PR-A (rule + provider + widget extraction + i18n + web), PR-B (mobile, depends on A).

## Architecture Decisions

| Decision | Choice | Alternatives rejected | Rationale |
|---|---|---|---|
| Security | Extend `setLogs` read to mirror parent session rule; write stays owner-only | (B) denormalize setLogs into session doc | B needs migration + breaks existing pattern; the parent rule is already proven |
| Provider | NEW `coachSessionSetLogsProvider` (`autoDispose.family` on `({athleteUid, sessionId})`) → `listSetLogs` | Reuse `sessionSummaryProvider` | summaryProvider also fetches the Session doc (already in the web row) and its key field is `uid`, not `athleteUid` — a coach-named alias reads clearer and avoids over-fetching |
| Widget reuse | Extract `_ExerciseBlock`+`_SetRow`+`_PrBadgeStub` → public `SessionExerciseBlock` | Reuse `SessionDetailScreen` | SessionDetailScreen hardcodes `currentUidProvider` → PF uid → rule denial. Widgets are already pure (no provider reads) |
| Grouping | Keep the `LinkedHashMap` grouping in each call site (web/mobile), pass pre-grouped `(exerciseName, sets)` to the widget | Group inside the widget | Widget already takes one exercise's sets — preserves session_detail behavior exactly |

`listSetLogs({uid, sessionId})` is confirmed cross-user (plain `uid` param, no caller-uid coupling) — no data-layer change.

## Data Flow
```
session_shares/{athleteUid}.trainerId == PF.uid   (rule gate)
        │
PF taps finished row ──→ coachSessionSetLogsProvider((athleteUid, sessionId))
        │                         │
        │                  SessionRepository.listSetLogs ──→ users/{athleteUid}/.../setLogs
        ▼                         ▼
  group by exerciseName ──→ SessionExerciseBlock(exerciseName, sets)   [web + mobile]
  rule denial (no/revoked share) → FirebaseException code permission-denied → "no compartió" placeholder
```

## File Changes
| File | Action | Description |
|---|---|---|
| `firestore.rules` (~508-510) | Modify | `setLogs` read mirrors session predicate; write owner-only |
| `lib/features/workout/application/session_providers.dart` | Modify | + `coachSessionSetLogsProvider` |
| `lib/features/workout/presentation/widgets/session_exercise_block.dart` | Create | Public `SessionExerciseBlock` (+ private `_SetRow`, `_PrBadgeStub`) |
| `lib/features/workout/presentation/session_detail_screen.dart` | Modify | Import shared widget; delete the 3 local classes (behavior-preserving) |
| `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` | Modify | `_HistorialTable` rows → tap-to-expand setLogs (web) |
| `lib/features/coach/presentation/athlete_detail_screen.dart` | Modify | New session-history section + per-session detail (mobile, PR-B) |
| `lib/l10n/intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb` | Modify | New keys |

## Interfaces / Contracts

**Rule** (mirrors the existing session predicate at lines 502-505 — `allow read: if request.auth != null && (request.auth.uid == uid || (exists(.../session_shares/$(uid)) && get(.../session_shares/$(uid)).data.trainerId == request.auth.uid))`):
```
match /setLogs/{setLogId} {
  allow read: if request.auth != null
              && (request.auth.uid == uid
                  || (exists(/databases/$(database)/documents/session_shares/$(uid))
                      && get(/databases/$(database)/documents/session_shares/$(uid)).data.trainerId == request.auth.uid));
  allow write: if request.auth != null && request.auth.uid == uid;
}
```

**Provider:**
```dart
final coachSessionSetLogsProvider = FutureProvider.autoDispose
    .family<List<SetLog>, ({String athleteUid, String sessionId})>((ref, key) {
  if (key.athleteUid.isEmpty) return Future.value(const <SetLog>[]);
  return ref.read(sessionRepositoryProvider)
      .listSetLogs(uid: key.athleteUid, sessionId: key.sessionId);
});
```

**Widget** (public API unchanged from `_ExerciseBlock`):
```dart
class SessionExerciseBlock extends StatelessWidget {
  const SessionExerciseBlock({super.key, required this.exerciseName, required this.sets});
  final String exerciseName;
  final List<SetLog> sets;
}
```

**Web wiring**: convert each `_HistorialTable` row into an `ExpansionTile` (no business `setState` — expansion is local UI). On expand, a small `Consumer` watches `coachSessionSetLogsProvider((athleteUid: athleteId, sessionId: s.id))` → `.when(loading, data → group + SessionExerciseBlock list / empty key, error → permission-denied detect → "no compartió" else generic)`.

**Mobile wiring**: in `_AthleteDetailBody`'s `ListView`, add a "HISTORIAL" section that watches `sessionsByUidProvider(athleteId)` (import it — only `currentUidProvider` is imported today), filter via `isCompletedSession`, render tappable rows. Tap → detail view watching `coachSessionSetLogsProvider` → `SessionExerciseBlock`s. Same permission-denied mapping.

**Error mapping**: `e is FirebaseException && e.code == 'permission-denied'` → `coachAthleteSetLogsNotShared`; else generic load error (existing pattern: `account_deletion_notifier.dart:181`).

## Testing Strategy (Strict TDD)
| Layer | File | Assertions |
|---|---|---|
| Data | `test/features/workout/data/session_repository_test.dart` | `listSetLogs(uid: otherUid, ...)` returns that uid's sets ordered by setNumber (cross-user, fake_cloud_firestore) |
| Application | `test/features/workout/application/coach_session_set_logs_provider_test.dart` (new) | delegates to repo with key fields; empty `athleteUid` → `[]`; autoDispose |
| Presentation | `test/features/workout/presentation/session_exercise_block_test.dart` (new) | renders name + one `_SetRow` per set + PR badge |
| Web | `alumno_detail_screen` test ext | tap row → loading → data renders blocks / empty / permission-denied placeholder |
| Mobile (PR-B) | `athlete_detail_screen` test ext | history section renders finished sessions; tap → blocks; permission-denied → placeholder |
| Rules | emulator-deferred | 5 scenarios: owner reads; linked+sharing PF reads; revoked PF denied; unrelated trainer denied; PF write denied (no harness — manual at verify) |

## i18n keys (intl_es_AR.arb + intl_es.arb + intl_en.arb)
- `coachSessionHistorySection` ("HISTORIAL DE SESIONES" / "WORKOUT HISTORY") — mobile section label
- `coachSessionExpandHint` ("Ver sets" / "View sets") — web expand affordance
- `coachAthleteSetLogsEmpty` ("Sin sets en esta sesión." ) — finished session, no logged sets
- `coachAthleteSetLogsNotShared` ("Este alumno no compartió su historial." ) — permission-denied state

## PR seam / sizes
- **PR-A** (rule + provider + `session_exercise_block.dart` + `session_detail_screen.dart` consume + web tap-expand + i18n + tests): ~180-240 lines. Independently shippable — web PFs see real loads.
- **PR-B** (mobile section + detail, stacked on A; reuses A's provider+widget): ~140-200 lines.
- Combined ~320-440 brushes the 400 budget → split keeps each reviewable; higher-risk rule+web bakes first.

## Migration / Rollout
No data migration. Rule deploy ships with PR-A. Revert = restore owner-only `setLogs` read.

## Open Questions
- None blocking. Rule correctness is provable only via emulator (deferred to verify, no automated harness).
