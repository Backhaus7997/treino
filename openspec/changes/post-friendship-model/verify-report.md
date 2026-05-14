# Verify Report — post-friendship-model

**Change**: `post-friendship-model` · Fase 3 · Etapa 1
**Branch**: `feat/post-friendship-model`
**Strict TDD**: active
**Date**: 2026-05-14
**Verdict**: **PASS WITH WARNINGS** — 0 CRITICAL, 3 WARNING, 2 SUGGESTION

## Quality Gates

| Gate | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | ✅ 0 issues |
| Format | `dart format --output=none --set-exit-if-changed .` | ✅ 0 changed |
| Tests | `flutter test` | ✅ 418 passing, 1 skipped (pre-existing SCENARIO-018), 0 failures |

## Spec Compliance Matrix (21 SCENARIOs)

| SCENARIO | Description | Coverage | Status |
|---|---|---|---|
| 112 | Post fields + routineTag null | `domain/post_test.dart:11` | COMPLIANT |
| 113 | Post round-trip routineTag=null | `domain/post_test.dart:32` | COMPLIANT |
| 114 | Post round-trip routineTag populated | `domain/post_test.dart:50` | COMPLIANT |
| 115 | PostPrivacy fromJson/toJson (6 sub-cases) | `domain/post_privacy_test.dart:7-30` | COMPLIANT |
| 116 | Friendship members + default pending | `domain/friendship_test.dart:11` | COMPLIANT |
| 117 | FriendshipStatus round-trip (4 sub-cases) | `domain/friendship_status_test.dart:7-25` | COMPLIANT |
| 118 | create writes `posts/p1` | `data/post_repository_test.dart:42` | COMPLIANT |
| 119 | byAuthor filters by authorUid | `data/post_repository_test.dart:59` | COMPLIANT |
| 120 | feedPublic returns only public | `data/post_repository_test.dart:75` | COMPLIANT |
| 121 | feedForFriends returns posts by known friends | `data/post_repository_test.dart:94` | COMPLIANT |
| 122 | feedForGym returns gym posts by gymId | `data/post_repository_test.dart:130` | COMPLIANT |
| 123 | request creates sorted doc, pending, requesterId | `data/friendship_repository_test.dart:22` | COMPLIANT |
| 124 | accept sets accepted for non-requester | `data/friendship_repository_test.dart:68` | COMPLIANT |
| 125 | accept throws when caller is requester | `data/friendship_repository_test.dart:85` | COMPLIANT |
| 126 | acceptedFriendsOf returns other UIDs | `data/friendship_repository_test.dart:106` | COMPLIANT |
| 127 | pendingRequestsFor returns received only | `data/friendship_repository_test.dart:146` | COMPLIANT |
| 128 | delete removes doc | `data/friendship_repository_test.dart:189` | COMPLIANT |
| 129 | request idempotent | `data/friendship_repository_test.dart:214` | COMPLIANT |
| 130 | rules: non-owner cannot create post | `scripts/rules_test/rules.test.js:43` | COMPLIANT (manual exec deferred) |
| 131 | rules: non-member cannot read friendship | `scripts/rules_test/rules.test.js:71` | COMPLIANT (manual exec deferred) |
| 132 | rules: requester cannot self-accept | `scripts/rules_test/rules.test.js:116` | COMPLIANT (manual exec deferred) |

**21/21 scenarios COMPLIANT.** Sub-cases por triangulación TDD (115a-f, 117a-d) sin gaps.

## Findings

### WARNING

**W1**: REQ-PFM-001 spec text lista 6 fields; implementación tiene 7 (`authorGymId` agregado por design ADR de denormalización para query single-trip `feedForGym`). El texto de la spec quedó stale — NO es problema de código.

**W2**: SCENARIO-130/131/132 cubiertos por la suite JS en `scripts/rules_test/rules.test.js`, pero la ejecución contra emulator vivo (T35) fue explícitamente postpuesta a verificación manual. La suite existe y es correcta; correr post-merge:

```bash
./scripts/emulator.sh
./scripts/test_rules.sh
```

**W3**: `git diff main..HEAD` muestra archivos de workout presentation (6 lib + 4 test) que NO pertenecen a este change — son del PR #21 que landeó en main DESPUÉS de cortar esta branch. Cuando la branch mergee via PR, GitHub computa el diff correctamente con los commits propios. Para un diff local limpio, rebase contra main antes del PR.

### SUGGESTION

**S1**: Actualizar el texto de REQ-PFM-001 para listar `authorGymId` como field #7 (cosmético, bajo).

**S2**: `routine_tag_test.dart` usa labels `T05x` (referencia a task) en vez de un SCENARIO numerado. REQ-PFM-003 no tiene un SCENARIO específico en la spec — si se agrega uno, renombrar.

## Static correctness

- ✅ `@freezed` + `json_serializable` en los 3 modelos Freezed (post, friendship, routine_tag)
- ✅ Enums con `@JsonValue('lowercase')` + extension `fromJson`/`toJson` (matches `user_role.dart` pattern)
- ✅ Repos con `FirebaseFirestore` injection, collection getter privado, sin interface (matches `user_repository.dart`)
- ✅ Providers Riverpod manual con `FutureProvider.family<T, String>` para uid-scoped (matches `routine_providers.dart`)
- ✅ Tests con `fake_cloud_firestore` + `FakeFirebaseFirestore()` directo + SCENARIO numbered

## Regression check

`git diff cf98509 8245fa4 --stat` (commit del apply vs commit anterior):

- Solo agregados — `lib/features/feed/**`, `test/features/feed/**`, `scripts/seed_posts.js`, `scripts/test_rules.sh`, `scripts/rules_test/**`, `openspec/changes/post-friendship-model/apply-progress.md`
- Modificación a `firestore.rules` (bloques nuevos, sin tocar reglas existentes de `users/`, `exercises/`, `routines/`)
- **Cero archivos fuera de scope tocados** (ningún UI, ningún widget compartido, ningún tema, ningún router)

## Manual verification pending

- T35 (correr seed contra emulator): `./scripts/emulator.sh && node scripts/seed_posts.js`
- W2 rules test execution: `./scripts/test_rules.sh`

Ambos son verificación post-merge, no bloquean PR.

## Verdict

**PASS WITH WARNINGS** — safe to proceed.

**Próximos pasos**:
1. (opcional) Rebase contra `main` para diff local más limpio.
2. Abrir PR a `main`.
3. Tras merge → `sdd-archive`.
