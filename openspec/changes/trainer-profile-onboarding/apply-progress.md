# Apply Progress: trainer-profile-onboarding

**Change**: trainer-profile-onboarding
**Batch**: PR#1 — Data Layer Fix + Onboarding Gate
**Mode**: Strict TDD
**Date**: 2026-06-02
**Branch**: `feat/trainer-profile-onboarding-pr1-data-gate`
**Status**: PR#1 COMPLETE — all quality gates pass

---

## TDD Cycle Evidence

| Task | RED commit | GREEN commit | Result |
|---|---|---|---|
| T-TPO-002/003 | `31a3490` test: RED SCENARIO-688 | `f9500b0` fix: ADR-TPO-001 uid fix | PASS |
| T-TPO-004/005 | `cfb28fa` test: RED SCENARIO-689..693 | (no prod change needed — T-TPO-003 covers) | PASS |
| T-TPO-006/007 | `57e5309` test: RED SCENARIO-694..700 | `2330e6b` feat: trainerProfileComplete extension | PASS |
| T-TPO-008/009 | `48451b6` test: RED provider tests | `148d71d` feat: trainerProfileCompleteProvider | PASS |
| T-TPO-011/012 | `e834577` test: RED SCENARIO-701..708 | `b662e68` feat: authRedirect trainer gate | PASS |

---

## Completed Tasks (PR#1)

- [x] T-TPO-001 — Branch setup verified
- [x] T-TPO-002 — RED: SCENARIO-688 failing test created
- [x] T-TPO-003 — GREEN: `_trainerPublicSubsetFromPartial` uid fix applied
- [x] T-TPO-004 — RED: SCENARIO-689..693 tests added
- [x] T-TPO-005 — GREEN: all 6 repo scenarios pass (no extra prod code needed)
- [x] T-TPO-006 — RED: SCENARIO-694..700 domain getter tests created
- [x] T-TPO-007 — GREEN: `user_profile_trainer_completeness.dart` extension created
- [x] T-TPO-008 — RED: provider tests for trainerProfileCompleteProvider added
- [x] T-TPO-009 — GREEN: `trainerProfileCompleteProvider` added to user_providers.dart
- [x] T-TPO-010 — SETUP: router import state verified, insertion point confirmed
- [x] T-TPO-011 — RED: `router_auth_redirect_test.dart` created with 9 branch tests
- [x] T-TPO-012 — GREEN: trainer-incomplete gate added to authRedirect
- [x] T-TPO-013 — GATE: flutter analyze 1 pre-existing issue (unrelated file), 0 on touched files; dart format clean on all touched paths
- [x] T-TPO-014 — GATE: 25 new tests pass (6 repo + 10 domain/provider + 9 router; ≥21 required)
- [x] T-TPO-015 — VERIFY: averageRating/reviewCount whitelist preserved; no pubspec/rules/CF changes; no Co-Authored-By

---

## Files Changed (PR#1)

### Production code

| File | Action | ADR |
|---|---|---|
| `lib/features/profile/data/user_repository.dart` | EDIT — `_trainerPublicSubsetFromPartial(partial, {required String uid})` + `result['uid'] = uid` + callsite update + comment update | ADR-TPO-001, ADR-TPO-002 |
| `lib/features/profile/domain/user_profile_trainer_completeness.dart` | CREATE — extension getter `bool get trainerProfileComplete` | ADR-TPO-004 |
| `lib/features/profile/application/user_providers.dart` | EDIT — import extension + add `trainerProfileCompleteProvider` | ADR-TPO-004 |
| `lib/app/router.dart` | EDIT — import extension + import user_role + trainer-incomplete branch with `!isPublic` guard | ADR-TPO-003 |

### Tests

| File | Action | Scenarios |
|---|---|---|
| `test/features/profile/data/user_repository_trainer_uid_test.dart` | CREATE | 688, 689, 690, 691, 692, 693 |
| `test/features/profile/domain/trainer_profile_complete_test.dart` | CREATE | 694, 695, 696, 697, 698, 699, 700 + 3 provider tests |
| `test/app/router_auth_redirect_test.dart` | CREATE | 701, 702, 703 (×2), 704, 705, 706, 707, 708 |

### Existing test updated

| File | Change |
|---|---|
| `test/app/router_redirect_test.dart` | `trainerProfile()` fixture updated to set trainer fields so `trainerProfileComplete == true` (prevents regression from new gate) |

---

## Deviations from Design

1. **ADR-TPO-003 loop guard enhanced**: The design says to add the branch "INSIDE the `if (loggedIn && !isProfileSetup)` block". An additional `!isPublic` guard was added to the condition. Without it, SCENARIO-708 (public routes remain accessible) would fail — a logged-in incomplete trainer on `/login` would be sent to onboarding instead of `/home`. The `!isPublic` guard is consistent with ADR-TPO-003's intent ("gate does not fire for public routes") and all 8 spec scenarios pass.

2. **T-TPO-004 RED state**: Tests 689-693 were committed as a RED batch but all passed immediately after T-TPO-003 (the uid fix already covers all these scenarios). Per tasks.md: "If any fail, identify the gap and patch only the minimal production code to make them pass." None failed, so no extra production code was needed.

3. **Test count**: 25 new tests (vs 21 minimum). The extra 4 come from: (a) splitting SCENARIO-703 into two tests (bare route + query-param route), (b) 3 Riverpod provider tests added in the domain test file. All serve the spec.

---

## Quality Gate Results

| Gate | Result |
|---|---|
| `flutter analyze` | 1 pre-existing warning in unrelated file (athlete_agenda_screen_test.dart); 0 issues on touched files |
| `dart format` | Clean on all touched files |
| `flutter test` (3 new files) | 25/25 pass |
| `averageRating` in `_trainerPublicFields` | ABSENT (ADR-RV-005 preserved) |
| `reviewCount` in `_trainerPublicFields` | ABSENT (ADR-RV-005 preserved) |
| `pubspec.yaml` changes | NONE |
| `firestore.rules` changes | NONE |
| `storage.rules` changes | NONE |
| Cloud Function changes | NONE |
| `Co-Authored-By` in commits | NONE |

---

## Remaining Tasks (PR#2 — NOT this batch)

- [ ] T-TPO-016..T-TPO-034 — All PR#2 tasks (UI mode enum, router param mapping, promote script, README, delete legacy script)

---

## Artifact References

- File: `openspec/changes/trainer-profile-onboarding/apply-progress.md`
- Engram: `sdd/trainer-profile-onboarding/apply-progress`
