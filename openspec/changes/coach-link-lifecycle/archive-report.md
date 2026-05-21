# Archive Report — coach-link-lifecycle

**Change**: `coach-link-lifecycle`
**Fase / Etapa**: Fase 5 · Etapa 3 — Link lifecycle UI (athlete view + trainer dashboard)
**Status**: ARCHIVED
**Date**: 2026-05-21
**Artifact Store**: openspec
**PR**: #61 (feat(coach): athlete/trainer link lifecycle UI + repo cancel — Fase 5 Etapa 3)
**Merge commit**: `2d419f4` — Merged to main (2026-05-20)
**Owner**: Dev B

---

## Executive Summary

`coach-link-lifecycle` shipped as PR #61 (single PR, ~1.4k LOC including tests). Consumes the foundation laid by Etapa 1 (TrainerLink repo + providers) and the Discovery surface from Etapa 2 (TrainerPublicProfile + CTA stub). Connects athlete and trainer sides of the vínculo lifecycle end-to-end through the UI:

- **Athlete side**: AthleteCoachView reads `currentAthleteLinkProvider` and routes to one of three states — Discovery list (no link) / pending card with "Cancelar solicitud" / active card with PF info + "Terminar vínculo". The CTA "PEDIR VÍNCULO" on TrainerPublicProfile is now wired to `trainerLinkRepositoryProvider.request(...)` with contextual disabled-state labeling.
- **Trainer side**: TrainerCoachView DASHBOARD lists pending requests with ACEPTAR/RECHAZAR and a counter of active alumnos; ALUMNOS tab lists active links with TERMINAR VÍNCULO. Real-time updates via `trainerLinksStreamProvider` (snapshot-based).
- **Repo extension**: New `TrainerLinkRepository.cancel(linkId)` method — pending → terminated with `reason='cancelled-by-athlete'`. Required because the original repo (Etapa 1) only supported terminate on active/paused.

Firestore composite indexes for `trainer_links` deployed post-merge to `treino-dev` (2 indexes — by athleteId+requestedAt and by trainerId+requestedAt). `firebase.json` patched in the same PR to actually include `firestore.indexes.json` in deploys (was silently missing). All Coach link flows now exercise the full Etapa 1 repo surface from the UI.

---

## Delivery: Single PR Strategy

### PR #61 — Coach Link Lifecycle UI
- **Branch**: `feat/coach-link-lifecycle` (deleted post-merge)
- **Status**: Squash-merged to main as `2d419f4`
- **Merge date**: 2026-05-20

**Deliverables**:

- **lib/features/coach/athlete_coach_view.dart** — Full rewrite from placeholder to stateful link-aware view:
  - Watches `currentAthleteLinkProvider` (FutureProvider, autoDispose).
  - `null` → renders `TrainersListScreen` (entry into Discovery — no separate empty state widget; Discovery list IS the empty state).
  - `status == pending` → `_LinkStateCard` (pending variant): copy "Solicitud enviada. Esperando confirmación." + outlined "Cancelar solicitud" button with confirm dialog → `repo.cancel(linkId)`.
  - `status == active` → `_LinkStateCard` (active variant): trainer name + avatar (read via `userPublicProfileProvider(trainerId)`) + filled "Terminar vínculo" button with confirm dialog → `repo.terminate(linkId)`.
  - Inline `_confirm` helper for the two confirm dialogs (no extraction — two call-sites don't justify the abstraction).

- **lib/features/coach/trainer_coach_view.dart** — Full rewrite of DASHBOARD + ALUMNOS tabs:
  - DASHBOARD: real-time list of pending requests via `trainerLinksStreamProvider` filtered to `status=pending` — each row is a `_PendingRequestCard` (athlete avatar + name from `userPublicProfileProvider` + ACEPTAR / RECHAZAR buttons). Below, a counter "Tenés N alumnos activos" with tap-to-switch to ALUMNOS tab.
  - ALUMNOS: same stream filtered to `status=active` — each row is an `_ActiveAlumnoCard` (athlete avatar + name + TERMINAR VÍNCULO button with confirm dialog).
  - AGENDA + COMUNIDADES: untouched, remain placeholder (Agenda lands in Etapa 6; Comunidades = out of scope of Fase 5).

- **lib/features/coach/presentation/widgets/trainer_contact_cta_stub.dart** — Rewrite from StatelessWidget showing a "próximamente" SnackBar to `ConsumerStatefulWidget`:
  - Takes `trainerId` from `TrainerPublicProfileScreen`.
  - On tap → `trainerLinkRepositoryProvider.request(trainerId, athleteId)` + invalidates `currentAthleteLinkProvider`.
  - Disabled-state when athlete already has link in `pending` or `active` — MVP rule: one athlete → one PF at a time.
  - Contextual label: "PEDIR VÍNCULO" (default) / "SOLICITUD PENDIENTE" (own pending) / "TU PERSONAL TRAINER" (own active) / "YA TENÉS UN PF" (link with different trainer).
  - Filename kept as `_stub` to avoid disrupting Etapa 2 imports — rename deferred as cleanup.

- **lib/features/coach/presentation/trainer_public_profile_screen.dart** — One-line change: `const TrainerContactCtaStub()` → `TrainerContactCtaStub(trainerId: uid)`.

- **lib/features/coach/data/trainer_link_repository.dart** — New method:
  - `cancel({required String linkId})` → reads doc, asserts `status==pending`, writes `status:terminated, terminatedAt:now, terminationReason:'cancelled-by-athlete'`. Throws `StateError` if not pending.

- **firestore.indexes.json** — 2 new composite indexes for `trainer_links`:
  - `(athleteId ASC, requestedAt DESC)` — for `listForAthlete` queries
  - `(trainerId ASC, requestedAt DESC)` — for `listForTrainer` / `watchForTrainer`

- **firebase.json** — Bug fix: added `"indexes": "firestore.indexes.json"` to the `firestore` block. The key was missing, which caused `firebase deploy --only firestore:indexes` to silently deploy zero indexes despite the file existing. Discovered during smoke testing when athlete-side queries hit `failed-precondition: query requires an index`.

- **tests/**:
  - `test/features/coach/athlete_coach_view_test.dart` — 4 tests covering no-link / pending / active / loading states.
  - `test/features/coach/trainer_coach_view_test.dart` — 7 tests covering tab structure + DASHBOARD scenarios (with/without pending requests, counter accuracy) + ALUMNOS list rendering.
  - `test/features/coach/presentation/widgets/trainer_profile_widgets_test.dart` — 8 tests updated for the new `TrainerContactCtaStub` API (ProviderScope overrides + trainerId required).
  - `test/features/coach/coach_screen_test.dart` — 4 tests, added provider overrides (`currentAthleteLinkProvider` + `trainerLinksStreamProvider`) so the rewritten views resolve in widget tests without hanging.
  - **Total**: 23 tests updated/added in this PR. Full suite: 953 passing.

---

## Locked Decisions (3)

| # | Decision | Rationale | Impact |
|---|---|---|---|
| 1 | **Add `TrainerLinkRepository.cancel(linkId)`** in this PR instead of a separate repo-extension PR | The use case (athlete cancels own pending request) is valid and Etapa 1 didn't cover it. Method is ~25 LOC + tests. Splitting into its own PR would have added coordination overhead with zero review benefit. | Repo surface grew by one method. Signature parallels `accept`/`decline`. |
| 2 | **Wire the CTA "PEDIR VÍNCULO" in this PR** rather than deferring further | Etapa 2 (PR #59) merged with the stub explicitly deferred to Etapa 3 per the comment in the original file. Connecting it here completes the athlete→pending→trainer-dashboard loop end-to-end in a single deliverable. | The widget kept its filename (`trainer_contact_cta_stub.dart`) to avoid rippling imports across the Etapa 2 surface. Rename queued as future cleanup. |
| 3 | **Real-time `StreamProvider` for trainer, `FutureProvider.autoDispose` for athlete** | The trainer needs to see new incoming requests instantly (productivity surface; the dashboard might be the first thing opened in the morning). The athlete has a single link — `FutureProvider.autoDispose` recalculates on tab entry and is sufficient; a stream for one doc would be overkill in cost (per-write read cost) without UX gain. | DASHBOARD updates without manual invalidation. Athlete tab requires `ref.invalidate(currentAthleteLinkProvider)` after `request`/`cancel`/`terminate` from the athlete side — done at all call-sites. |

---

## Discoveries / Gotchas

1. **`firebase.json` silently missing `"indexes"` key**: The file had `"rules": "firestore.rules"` but no `"indexes"` entry. As a result, `firebase deploy --only firestore:indexes --project treino-dev` printed `Deploy complete!` without ever reading `firestore.indexes.json`. The give-away was the absence of the `reading indexes from firestore.indexes.json...` line in the deploy output. Once the key was added, the deploy worked first try. Worth checking on other Firebase projects in the org.

2. **Smoke testing trainer-side requires real PF accounts**: With Dev A's PF onboarding still pending (Etapa not yet started at merge time), the seed script `scripts/seed_trainer_profiles.js` was used to drop 5 fake trainer documents into `users/` + `trainerPublicProfiles/`. Athlete-side flows (request → pending → cancel) are smoke-testable today; trainer-side (accept/decline a real request, terminate from PF) waits until a real PF account exists.

3. **Stream filter math**: A trainer's `trainerLinksStreamProvider` emits the FULL list, then the view filters in Dart. This is fine for typical scale (<50 links per PF) but worth keeping in mind if a PF ever crosses ~500 links — at that point we'd want server-side `where status in [...]` queries.

4. **`fake_cloud_firestore` does not enforce composite indexes**: Repo tests passed locally before indexes were deployed, hiding the production failure mode. Indexes manifest only against a real Firestore instance. Lesson: any new query in repo code must be paired with an explicit indexes-deploy step in the PR, even if local tests are green.

---

## Test Coverage

- **23 tests** updated or added across 4 widget-test files in `test/features/coach/`.
- **Full suite**: 953 tests passing post-merge (was 930 pre-Etapa-3).
- **Quality gates**:
  - `flutter analyze` — 0 issues
  - `dart format .` — clean
  - All gates green pre-merge.

---

## NOT Delivered (intentional)

| Item | Lands in |
|---|---|
| In-app notifications when the PF accepts/rejects | Fase 6 (push notifications) |
| Optional message at request time ("¿Por qué querés trabajar conmigo?") | Future iteration |
| Resume from paused (`paused → active`) | Future iteration. The `paused` status exists in the enum but is not surfaced anywhere — no UI path can create it today. |
| AGENDA tab | Etapa 6 |
| COMUNIDADES tab | Out of scope of all of Fase 5 |
| Rename `trainer_contact_cta_stub.dart` → `trainer_contact_cta.dart` | Cleanup PR, low priority |

---

## Handoff to Subsequent Etapas

| Etapa | Owner | What it uses from Etapa 3 |
|---|---|---|
| **Etapa 4 — Plans mobile (Dev B)** | Dev B | Independent of link UI but assumes link lifecycle works. Plans will be assigned only when `status==active`. |
| **Etapa 5 — Chat (Dev C)** | Dev C | Chat is gated on `status==active` of a TrainerLink. The current `currentAthleteLinkProvider` + `trainerLinksStreamProvider` are the same surfaces chat will consume. |
| **Etapa 6 — Agenda (Dev C)** | Dev C | AGENDA tab lives in `TrainerCoachView`. Will replace the current placeholder section — no refactor needed beyond filling that branch. |
| **Etapa 7 — Coach Hub (Dev A)** | Dev A | Coach Hub may surface link counts; will read `trainerLinksStreamProvider`. |
| **Etapa 8 — Excel + Cloud Function (Dev A)** | Dev A | Independent. |

**No blockers** for Etapas 4–8 from this PR.

---

## Cleanup Performed

- Local branch `feat/coach-link-lifecycle` deleted (2026-05-21).
- Remote branch `feat/coach-link-lifecycle` deleted via `git push origin --delete` (2026-05-21).
- Stale rebase stash dropped.
- Temp `.pr-body.tmp.md` removed.

---

## References

- **Proposal**: [openspec/changes/coach-link-lifecycle/propose.md](./propose.md)
- **PR**: https://github.com/Backhaus7997/treino/pull/61
- **Merge commit**: `2d419f4`
- **Prior etapa**: Etapa 2 (Discovery UI, PR #59), Etapa 1 (Foundations, PR #54)
