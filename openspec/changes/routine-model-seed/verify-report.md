# Verify Report - routine-model-seed (PR 1)

**Branch**: feat/routine-model-seed
**Verified**: 2026-05-13
**Scope**: PR 1 - Exercise collection (TASK-001..009, REQ-EX-*)

---

## Summary

- PR 1 REQ groups total: 8 (REQ-EX-MODEL-001..002, REQ-EX-REPO-001..002, REQ-EX-RULES-001, REQ-EX-PROVIDERS-001, REQ-EX-SEED-001, REQ-EX-BOOT-001)
- Pass (automated): 6 groups fully covered by passing tests
- Manual-Pending: 2 groups (REQ-EX-RULES-001 emulator scenarios; REQ-EX-SEED-001 + REQ-EX-BOOT-001 manual evidence in apply-progress)
- Fail: 0
- PR 1 tasks: 9, Done: 9 (all done), Pending: 0
- In-suite scenarios: 16 (SCENARIO-020..031 + 035..038), all passing
- Findings: CRITICAL=0, WARNING=3, SUGGESTION=2
- Ready to ship PR 1: YES - one mandatory pre-merge action (firebase deploy rules)

---

## Findings

### CRITICAL

None.

---

### WARNING

#### WARN-001 - REQ-EX-RULES-001 deploy pending (SCENARIO-032..034 unverified by automation)

firestore.rules has the correct match /exercises/{exerciseId} block committed and verified by code inspection. The three emulator-only scenarios (032: authenticated read allowed, 033: client write denied, 034: unauthenticated read denied) cannot be validated by flutter test. The firebase CLI was not in PATH in the apply environment.

Exact committed block matches REQ-EX-RULES-001 and design.md section 5 exactly:
    match /exercises/{exerciseId} {
      allow read: if request.auth != null;
      allow write: if false;
    }

Action required before merge: run firebase deploy --only firestore:rules or validate via Firebase Emulator.

---

#### WARN-002 - .gitignore uses exact filename instead of wildcard pattern

Spec REQ-EX-BOOT-001 requires: scripts/treino-dev-service-account*.json (wildcard)
Actual .gitignore line 52: scripts/treino-dev-service-account.json (exact match only)

Verification: git check-ignore -v scripts/treino-dev-service-account-backup.json returned empty (not matched). The actual credential file IS correctly gitignored and was NEVER committed (git log --all --full-history returns empty). The gap is a future risk if alternate credential filenames are downloaded.

Recommended fix: change line 52 to: scripts/treino-dev-service-account*.json

---

#### WARN-003 - exercisesProvider uses ref.read instead of ref.watch for repository call

Design section 4 specifies: return ref.watch(exerciseRepositoryProvider).listAll();
Actual implementation (exercise_providers.dart line 25): return ref.read(exerciseRepositoryProvider).listAll();

Using ref.read inside a FutureProvider does not subscribe to changes on exerciseRepositoryProvider. For a singleton Provider<ExerciseRepository> this is functionally equivalent because the repository never changes identity. All 4 provider scenarios pass. Deviates from project convention and was not documented in apply-progress.

---

### SUGGESTION

#### SUGG-001 - scripts/package-lock.json committed (not in spec scope)

scripts/package-lock.json (1945 lines) is committed on this branch. Spec and tasks only require scripts/package.json. Consider either adding to .gitignore or documenting the decision.

#### SUGG-002 - scripts/.env exclusion pattern is exact, not glob

.gitignore uses scripts/.env (exact). Does not exclude scripts/.env.local, scripts/.env.production, etc.

---

## Re-run results

| Gate | Result |
|---|---|
| flutter analyze | PASS - No issues found (0 issues) |
| flutter test test/features/workout/ | PASS - 16/16 passed |
| flutter test (full suite) | PASS - 279 passed, 1 skipped pre-existing, 0 failures |
| dart format --output=none --set-exit-if-changed . | PASS - 0 changed files |

---

## Service account leak check (P0)

| Check | Result |
|---|---|
| scripts/treino-dev-service-account.json gitignored | PASS |
| scripts/node_modules/ gitignored | PASS |
| scripts/.env gitignored | PASS |
| Never committed (full history) | PASS |
| Not in git index | PASS |

No credentials were ever committed. Key rotation NOT required.

---

## Scope discipline

| Check | Result |
|---|---|
| routine.dart absent | PASS |
| routine_day.dart absent | PASS |
| routine_slot.dart absent | PASS |
| routine_repository.dart absent | PASS |
| routine_providers.dart absent | PASS |
| firestore.rules has no /routines block | PASS |
| lib/app/router.dart unmodified | PASS |
| lib/features/profile/ unmodified | PASS |
| lib/features/home/ unmodified | PASS |
| lib/features/auth/ unmodified | PASS |
| pubspec.yaml unmodified | PASS |

---

## REQ-EX-* compliance matrix

| REQ | Scenarios | Coverage | Status |
|---|---|---|---|
| REQ-EX-MODEL-001 | 020, 021, 022, 023 | exercise_test.dart | PASS |
| REQ-EX-MODEL-002 | 024 | exercise_test.dart | PASS |
| REQ-EX-REPO-001 | 025, 026, 027, 028, 029, 030 | exercise_repository_test.dart | PASS |
| REQ-EX-REPO-002 | 031 | exercise_repository_test.dart | PASS |
| REQ-EX-RULES-001 | 032, 033, 034 | Manual - emulator required | WARNING WARN-001 |
| REQ-EX-PROVIDERS-001 | 035, 036, 037, 038 | exercise_providers_test.dart | PASS |
| REQ-EX-SEED-001 | 039, 040 | Manual - apply-progress: PASS count 25 | PASS manual evidence |
| REQ-EX-BOOT-001 | 041, 042 | Code inspection + gitignore check | PASS WARN-002 noted |

---

## Task completion

| Task | Status | Notes |
|---|---|---|
| TASK-001 .gitignore | DONE | WARN-002 exact vs wildcard |
| TASK-002 scripts bootstrap | DONE | package.json and .env.example confirmed correct |
| TASK-003a RED | DONE | 5 named scenarios present |
| TASK-003b GREEN | DONE | 5/5 pass |
| TASK-004a RED | DONE | 7 named scenarios present |
| TASK-004b GREEN | DONE | 7/7 pass |
| TASK-005a RED | DONE | 4 named scenarios present |
| TASK-005b GREEN | DONE | 4/4 pass |
| TASK-006 firestore.rules | DONE deploy pending | Rules correct; deploy = WARN-001 |
| TASK-007 seed script | DONE | 25 exercises 10 muscle groups |
| TASK-008 manual seed | DONE | apply-progress: PASS count 25 idempotency confirmed |
| TASK-009 quality gates | DONE | All 4 gates pass |

---

## Conclusion

PR 1 is ready to merge. No CRITICAL issues found.

Mandatory before merge:
1. firebase deploy --only firestore:rules (deploy the committed exercises security rule)

Recommended before merge:
2. Fix .gitignore line 52 to wildcard: scripts/treino-dev-service-account*.json

Deferred (can be PR 2 setup commit):
3. Change ref.read(exerciseRepositoryProvider) to ref.watch(exerciseRepositoryProvider) in exercise_providers.dart

All 16 automated scenarios pass. Full suite 279 passed 0 failures. flutter analyze 0 issues. dart format clean. No scope leaks. No credentials committed.
