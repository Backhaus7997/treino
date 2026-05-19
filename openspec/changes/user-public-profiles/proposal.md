# Proposal: user-public-profiles

**Owner**: Dev C
**Strategy**: Chained PRs (PR#A → PR#B), both target `main`
**Branch (PR#A)**: `feat/user-public-profiles`
**Branch (PR#B)**: `feat/user-public-profiles-search`
**Supersedes**: `wip/feed-search-users-deprecated` + deprecated `REQ-FSU-*` (from `feed-create-search`)

---

## Intent

Enable authenticated user discovery (search + public profile rendering) without exposing the owner-only `users/{uid}` collection. Replace the fragile Etapa 4 workaround (`firstPostByAuthorProvider` → "Anónimo" for users without posts) with a canonical identity source: a new `userPublicProfiles` collection. Resolve the permission-denied runtime bug from the deprecated branch at the architecture level, not by widening privacy on sensitive data.

## Scope

### In Scope (PR#A — Foundation + Etapa 4 refactor)
- `UserPublicProfile` Freezed model: `{uid, displayName, displayNameLowercase, avatarUrl, gymId}` (only `uid` non-null).
- `UserPublicProfileRepository` (`get`, `set`, `searchByDisplayName`) — targets `userPublicProfiles` top-level collection.
- `userPublicProfileRepositoryProvider` + `userPublicProfileProvider(uid)` (FutureProvider.family).
- `UserRepository` dual-write via `WriteBatch` in `getOrCreate`, `createIfAbsent`, `update`.
- `ProfileSetupNotifier.submit()` dual-write via `WriteBatch` (single atomic commit).
- `firestore.rules`: add `userPublicProfiles/{uid}` block (`read/list: auth != null`, `write: auth.uid == uid`).
- `publicProfileViewProvider` refactor: swap `firstPostByAuthorProvider` dependency for `userPublicProfileProvider(uid)`. Keep `firstPostByAuthorProvider` file + SCENARIO-200..202 unchanged.
- SCENARIO-203..205 rewritten (seed `userPublicProfiles` instead of `posts`).
- `scripts/backfill_user_public_profiles.js` — Node.js Admin SDK script, documented header, NOT executed.

### In Scope (PR#B — Search UI)
- `SearchUsersScreen` (cherry-pick + adapt from deprecated branch; type swap `UserProfile` → `UserPublicProfile`).
- `UserSearchResultTile` (cherry-pick + adapt).
- `searchUsersProvider` — `FutureProvider.family<List<UserPublicProfile>, String>`, 20-result limit, 2-char minimum, debounce.
- `feed_screen.dart`: wire search icon → `context.push('/feed/search')`.
- `router.dart`: add `GoRoute(path: 'search', ...)` under `/feed`.

### Out of Scope (deferred / explicit)
- Cloud Functions (sync is client-side WriteBatch only).
- Backfill script EXECUTION (ops decision, post-merge).
- `PublicProfileView` field rename (`authorDisplayName` → `displayName`) — deferred to cleanup PR.
- `PostRepository.create()` reading `gymId` from `userPublicProfiles` instead of `users/{uid}` — owner-read, no permission issue, optimization deferred.
- MI GYM index bug — separate follow-up.
- Real-time profile updates (StreamProvider upgrade) — future improvement.
- Any modification to the `UserProfile` model — STAYS UNTOUCHED.

---

## Capabilities

### New Capabilities
- `user-public-profiles`: public-facing identity collection (`uid/displayName/avatarUrl/gymId`) for cross-user discovery and public profile rendering. Includes dual-write contract from `UserRepository` and `ProfileSetupNotifier`, plus rules block.
- `user-search`: authenticated prefix-search over `userPublicProfiles.displayNameLowercase`, surfaced via `SearchUsersScreen` from the feed header.

### Modified Capabilities
- `feed-public-profile`: `publicProfileViewProvider` swaps its data source from `firstPostByAuthorProvider` (post denormalization) to `userPublicProfileProvider(uid)` (canonical identity). Behavior preserved (still returns `PublicProfileView`); fallback string `'Anónimo'` retained for migration gap window.

---

## Decisions Locked (resolves 10 open questions from explore)

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| Q1 | WriteBatch vs sequential write | **WriteBatch** | Atomic dual-write eliminates partial-state risk; trivial overhead. |
| Q2 | `PublicProfileView` field rename | **Defer to cleanup PR** | Mapping at provider boundary keeps PR#A focused; cascade is out of scope. |
| Q3 | `firstPostByAuthorProvider` fate | **Keep file + SCENARIO-200..202** | May have other consumers / debug uses; only the `publicProfileViewProvider` dependency swaps. |
| Q4 | `displayNameLowercase` null policy | **No explicit `!= null` filter** | Prefix range `>= q` naturally excludes nulls. Add SCENARIO covering it for safety. |
| Q5 | Top-level vs sub-collection | **Top-level `userPublicProfiles`** | Required for prefix-range list queries across users; sub-collection paths can't be cross-searched. |
| Q6 | Backfill script scope | **Document-only in PR#A** | `scripts/backfill_user_public_profiles.js` with header comments; execution is an ops decision. |
| Q7 | `ProfileSetupNotifier.submit()` timing | **Single `WriteBatch.commit()`** | Atomicity > sequencing; both writes succeed or neither. |
| Q8 | Stream vs Future for `userPublicProfileProvider` | **`FutureProvider.family`** | Matches existing `publicProfileViewProvider` shape; no cascading refactor. Stream upgrade is future work. |
| Q9 | Search result limit | **20** | Carries over from deprecated spec; no reason to change. |
| Q10 | Gym divergence post-update | **Accept stale-on-update** | `Post.authorGymId` is denormalized at post creation time (author context AT THE TIME); `UserPublicProfile.gymId` always reflects current. Documented as ADR in design. |

---

## Approach

### Architecture
1. **Two-collection identity model**: `users/{uid}` (private, owner-only) + `userPublicProfiles/{uid}` (public-soft, any-auth read). The public collection is a strict subset (5 fields). Privacy classification per field is documented (see explore §"Field Selection").
2. **Atomic dual-write at the repository seam**: every method on `UserRepository` that mutates `users/{uid}` (`getOrCreate`, `createIfAbsent`, `update`) composes a `WriteBatch` that writes both docs. Same pattern in `ProfileSetupNotifier.submit()`.
3. **Lazy migration on next sign-in**: dual-write covers all new mutations; existing users self-heal on their next login. Backfill script provided but not executed.
4. **Etapa 4 source-swap**: `publicProfileViewProvider` swaps from "newest post" to "userPublicProfile doc"; provider does the field mapping so `PublicProfileView` shape is unchanged.
5. **Chained PR delivery**: PR#A lands foundation + refactor (~490 LOC); PR#B lands search UI (~605 LOC) using the foundation. Both target `main` (stacked, not feature-branch chain).

### Why this approach
- **Privacy by architecture**, not by rules-widening: sensitive fields (`email`, `bodyWeightKg`, `gender`, etc.) literally do not exist in the public collection — cannot leak.
- **WriteBatch atomicity** trumps Cloud Functions for this volume: no extra infra, no eventual-consistency window, no opaque CF failures.
- **Lazy migration** keeps PR scope sane; backfill is a documented escape hatch, not blocking.
- **Chained PRs** keep each review under the 400-line cognitive budget (with size:exception forecast — see Review Workload below).

---

## PR Chain Plan

```
main
 └─ feat/user-public-profiles                (PR#A — foundation + Etapa 4 refactor)
     └─ feat/user-public-profiles-search     (PR#B — search UI; rebases onto main after PR#A merges)
```

### PR#A — Foundation
| Aspect | Detail |
|--------|--------|
| Branch | `feat/user-public-profiles` → `main` |
| Delivers | Model + repo + provider + dual-write + rules + Etapa 4 refactor + backfill script (doc) |
| Estimated LOC | ~220 prod + ~270 test = **~490 total** |
| Reviewability | Borderline — see Review Workload Forecast below |
| Verification | `flutter analyze` clean; `flutter test` green (incl. rewritten SCENARIO-203..205); manual smoke on simulator (sign-in creates `userPublicProfiles` doc); manual `firestore.rules` test (T35-style: non-owner read OK, non-owner write blocked). |
| Rollback | Revert merge commit. New collection becomes orphaned but harmless (any-auth read, write-blocked for non-owners). No data in `users/{uid}` was modified. `publicProfileViewProvider` reverts to `firstPostByAuthorProvider`. No migration to undo. |

### PR#B — Search UI
| Aspect | Detail |
|--------|--------|
| Branch | `feat/user-public-profiles-search` → `main` (after PR#A merges + main rebase) |
| Delivers | `SearchUsersScreen` + `UserSearchResultTile` + `searchUsersProvider` + router + feed-icon wire |
| Estimated LOC | ~245 prod + ~360 test = **~605 total** |
| Reviewability | Exceeds 400-line budget — chained delivery + `size:exception` likely needed |
| Verification | `flutter analyze` clean; `flutter test` green (SCENARIO-234..251 adapted); manual smoke (search "mart" returns user records, not posts). |
| Rollback | Revert merge commit. `/feed/search` route disappears, search icon click no-ops or hides. Foundation (PR#A) remains intact and usable by `publicProfileViewProvider`. |

### Dependency
PR#B HARD-depends on PR#A's `UserPublicProfileRepository.searchByDisplayName` + `userPublicProfiles` rule block. Do not open PR#B until PR#A is merged to `main`.

---

## Affected Areas

| Area | Impact | PR | Description |
|------|--------|----|-------------|
| `lib/features/profile/domain/user_public_profile.dart` | New | A | Freezed model |
| `lib/features/profile/data/user_public_profile_repository.dart` | New | A | `get`, `set`, `searchByDisplayName` |
| `lib/features/profile/application/user_public_profile_providers.dart` | New | A | Repo + per-uid providers |
| `lib/features/profile/data/user_repository.dart` | Modified | A | Dual-write via WriteBatch |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | Modified | A | `submit()` atomic dual-write |
| `lib/features/feed/application/public_profile_providers.dart` | Modified | A | Source-swap to `userPublicProfileProvider` |
| `firestore.rules` | Modified | A | New `userPublicProfiles/{uid}` block |
| `scripts/backfill_user_public_profiles.js` | New | A | Documented ops script (NOT executed) |
| `test/features/profile/data/user_repository_test.dart` | Modified | A | Add dual-write SCENARIOs |
| `test/features/profile/data/user_public_profile_repository_test.dart` | New | A | Repo tests incl. null-skip prefix query |
| `test/features/profile/application/user_public_profile_providers_test.dart` | New | A | Provider tests |
| `test/features/feed/application/public_profile_providers_test.dart` | Modified | A | Rewrite SCENARIO-203..205 fixtures |
| `lib/features/feed/presentation/search_users_screen.dart` | New | B | Cherry-pick + adapt |
| `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | New | B | Cherry-pick + adapt |
| `lib/features/feed/application/search_users_provider.dart` | New | B | `FutureProvider.family` |
| `lib/features/feed/feed_screen.dart` | Modified | B | Wire search icon route push |
| `lib/app/router.dart` | Modified | B | Add `/feed/search` route |
| `test/features/feed/presentation/search_users_screen_test.dart` | New | B | SCENARIO-234..251 adapted |
| `test/features/feed/application/search_users_provider_test.dart` | New | B | Provider tests |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Rules block missed in PR#A → search returns `permission-denied` (the bug we are fixing repeats) | Medium | High | **Mandatory "Rules Audit" section in design.md** listing every Firestore query + rule that grants it. Manual rules test (T35-style) is required pre-merge for PR#A. |
| Partial dual-write state (legacy users invisible in search until next sign-in) | Medium | Medium | Lazy migration documented + backfill script ready to run as ops follow-up. Search results explicitly NOT a "complete user list" — communicated in screen UX (empty-state copy). |
| Cherry-pick from deprecated branch carries stale `UserProfile` imports into PR#B | Medium | Medium | Design.md includes adaptation checklist (type swap, field-access audit). PR review gate: rg for `UserProfile` in `lib/features/feed/presentation/`. |
| `PublicProfileView` mapping in provider becomes a long-lived smell | Low | Low | Tracked as explicit follow-up cleanup PR. Documented in proposal Out-of-Scope. |
| Firestore composite index needed but missed | Low | Medium | Single-field prefix range is auto-indexed; verify in PR#A smoke test. Document explicitly in design. |
| PR#B exceeds 400-line review budget | High | Medium | Documented Review Workload Forecast below; delivery strategy resolves to chained + `size:exception` for PR#B. |
| Etapa 4 behavioral regression (e.g., spinner timing, error rendering changes) | Medium | High | SCENARIO-203..205 must be rewritten and green BEFORE provider source-swap (strict TDD gate). |

---

## Review Workload Forecast

| PR | Est. LOC | 400-line budget risk | Chained PRs recommended | Decision needed before apply |
|----|----------|----------------------|--------------------------|-------------------------------|
| PR#A | ~490 (220 prod + 270 test) | **Medium** | Yes (PR#A already split from PR#B) | Yes — confirm `size:exception` for ~90 LOC over budget OR split further (foundation vs Etapa 4 refactor) |
| PR#B | ~605 (245 prod + 360 test) | **High** | Yes (cannot reasonably shrink without losing autonomous slice) | Yes — confirm `size:exception` OR stack PR#B-1 (screen + tile) → PR#B-2 (provider + wire) |

`sdd-tasks` MUST emit explicit guard lines per phase common §E. Default delivery strategy (`ask-on-risk`) means the orchestrator will stop and ask before `sdd-apply` proceeds for both PRs.

---

## Rollback Plan

**PR#A**:
1. `git revert <merge-commit>` on `main`.
2. `firestore.rules` revert deploys via existing rules pipeline.
3. Orphaned `userPublicProfiles` docs remain — harmless (read-only to authed users, no PII).
4. `publicProfileViewProvider` returns to `firstPostByAuthorProvider` source. Etapa 4 returns to pre-refactor behavior ("Anónimo" for postless users).
5. No data migration to reverse.

**PR#B**:
1. `git revert <merge-commit>` on `main`.
2. `/feed/search` route disappears.
3. Search icon click → defensive no-op (already-deployed handler) OR icon hidden (depending on PR#B implementation — design.md to specify).
4. PR#A foundation remains intact and continues serving `publicProfileViewProvider`.

---

## Dependencies

- **PR#A → PR#B**: hard dependency (model + repo method + rule block).
- **Pre-PR#A**: nothing blocking (deprecated branch is dead; cherry-picks are non-blocking).
- **External**: none. No new packages, no Cloud Functions, no Firestore composite indexes anticipated.

---

## Success Criteria

- [ ] **PR#A merged**: `userPublicProfiles` collection exists in rules + data; dual-write verified on real device sign-in; SCENARIO-200..205 all green; Etapa 4 displays correct displayName for users with zero posts (no more "Anónimo" for postless-but-onboarded users).
- [ ] **PR#B merged**: `/feed/search?q=mart` returns matching `UserPublicProfile` records on a real device (smoke test); search icon visible in feed header; SCENARIO-234..251 all green.
- [ ] **Privacy verified**: manual rules test confirms non-owner cannot read `users/{uid}`, non-owner CAN read `userPublicProfiles/{uid}`, non-owner CANNOT write `userPublicProfiles/{uid}`.
- [ ] **No `UserProfile` model changes** in either PR (lesson learned from deprecated branch).
- [ ] **Backfill script** committed, documented, NOT executed.
- [ ] **Deprecated `REQ-FSU-*` spec** superseded in archive.

---

## Lessons Learned (process improvements — to fold into SDD standards)

1. **Firestore rules audit gap is a recurring failure mode.** The deprecated branch shipped 16 commits and 639 green tests before a real-device smoke test caught the `permission-denied`. Root cause: `fake_cloud_firestore` does NOT enforce rules. **Recommendation**: add a **MANDATORY "Rules Audit" section** to every `sdd-design` artifact for changes that touch Firestore. Each query in the design must be listed alongside the rule that grants it, with explicit confirmation: "this rule permits this query for this auth context."
2. **T35 manual rules test (pending from Fase 3 Etapa 1) would have caught this earlier.** **Recommendation**: promote T35-style manual rules testing to a **required pre-PR step** for any change that adds Firestore collections or modifies rules. The cost is ~10 minutes per PR; the cost of skipping it is a complete branch (16 commits) thrown away.
3. **Privacy classification missing at schema-design time.** The deprecated branch added `displayNameLowercase` to `UserProfile` without auditing the field-by-field privacy implications. **Recommendation**: when defining model fields in any SDD that touches user data, **explicitly classify each field as `private | public-soft | public`** in a table (as done in this exploration's "Field Selection"). Catches privacy leaks at proposal/design time, before code.

These three recommendations should be folded into the SDD skill registry — specifically into `sdd-design` compact rules — so they trigger automatically on Firestore-touching changes for any future change.
