# Proposal: Coach Agenda (Fase 5 · Etapa 6)

## Intent

Enable scheduling between trainer and athlete using an **asymmetric coach-controlled availability** model: the coach publishes recurring weekly availability rules (plus date-specific overrides) and athletes book free slots immediately, atomically, no confirmation handshake. This replaces the roadmap's original symmetric `propose/confirm` design (`docs/roadmap.md:285`) per product feedback — fewer states, less ambiguity, closer to real PT operations. `status` collapses from 3 values (`proposed | confirmed | cancelled`) to 2 (`confirmed | cancelled`).

## Scope

### In Scope

- 3 new Firestore collections: `coach_availability_rules`, `coach_availability_overrides`, `appointments` (with deterministic doc ID `'{trainerId}_{startsAtMs}'`).
- 3 new freezed domain models: `AvailabilityRule`, `AvailabilityOverride`, `Appointment`.
- 2 new repositories: `AvailabilityRepository` (rules + overrides), `AppointmentRepository` (CRUD + atomic booking transaction + cancel with 24h cutoff).
- Riverpod providers under `lib/features/coach/application/agenda_providers.dart` (rules stream, overrides stream, computed-slots provider, appointments stream).
- Athlete entry point: button **"VER AGENDA DEL PF"** inside `_LinkStateCard` (`AthleteCoachView`), after `_ShareToggle`, before `_ActionRow`, conditional on `link.status == active`.
- Athlete calendar screen at route `/coach/agenda` (ShellRoute child) using `table_calendar: ^3.2.0`, with day-slots bottom sheet for booking.
- Athlete past-appointments list: last 10 below the calendar + current/future appointments highlighted.
- Trainer AGENDA sub-tab: replace `_SubTabPlaceholder` (index 2 in `TabBarView` of `TrainerCoachView`) with `TrainerAgendaTab` (list of bookings + entry to availability editor).
- Trainer availability editor screen: define weekly rules (multiple per day allowed) and overrides (`block` whole day, or `extra` ad-hoc slot with start/end + duration).
- Firestore rules for all 3 collections: member-only reads, athlete-only creates on appointments with deterministic-ID guard, 24h cancellation cutoff enforced server-side via `request.time` CEL.
- Booking horizon capped at **4 weeks** (client computes availability for up to 28 days from today).
- `pubspec.yaml`: add `table_calendar: ^3.2.0`.
- Deploy rules via existing `scripts/deploy_rules.js`.

### Locked design decisions (resolved open questions)

- **Q1 — Slot duration**: enum `[30, 60, 90, 120]` minutes. Avoids weird widths, simpler validation.
- **Q2 — Multiple rules per day**: YES (e.g., "Lunes 8-12 AND 16-20"). Data model already supports it (multiple docs with same `dayOfWeek`).
- **Q3 — Rule edit semantics**: existing `confirmed` appointments survive untouched. Rules only affect FUTURE booking availability.
- **Q4 — Athlete history**: last 10 past appointments + current/future, single list below calendar.
- **Q5 — Booking horizon**: 4 weeks ahead, hardcoded for v1.
- **Q6 — Empty state copy**: `"Tu PF todavía no configuró horarios."`
- **Q7 — Override types**: keep `block` (no hours needed, blocks whole day from rules) + `extra` (requires start/end + duration). Asymmetry is intentional — splitting into separate types would inflate the data model.
- **Q8 — Notification gap for new bookings**: ACCEPTABLE for v1. Coach sees bookings on next AGENDA tab open. Badge + push deferred to Fase 6.

### Out of Scope

- Google Calendar / external sync (separate sub-etapa, post-v1).
- Push notifications and unread-booking badge (Fase 6).
- Group sessions, multi-coach per athlete, multi-TZ awareness.
- Automatic pre-session reminders.
- "PF sees athlete training historial" (orphan feature gated by `sharedWithTrainer`, unrelated to agenda).
- Per-coach configurable cancellation cutoff (tech debt: `trainerPublicProfile.cancellationHours`).
- Per-coach customizable slot durations beyond enum (tech debt).
- Recurrence patterns other than weekly (tech debt).
- Symmetric athlete-proposes flow from original roadmap (explicitly replaced).

## Capabilities

### New Capabilities

- `coach-agenda`: availability rules + overrides + appointments. Asymmetric booking (coach defines, athlete books atomically). Includes slot computation, 24h cancellation cutoff, deterministic-doc-ID transactional booking.

### Modified Capabilities

- None. The change introduces new collections and UI surfaces; existing capabilities (`trainer-link`, `coach-discovery`, `coach-plans`, `coach-chat`) are not modified at the spec level. The athlete entry point inside `_LinkStateCard` is a UI insertion, not a spec change to `trainer-link`.

## Approach

**Approach C (Hybrid)** from exploration: store rules + overrides + appointments; client computes free slots per visible date by iterating weekly rules → applying overrides (block/extra) → subtracting confirmed appointments for that (trainerId, date). **No materialized slot docs, no Cloud Function.**

Atomic booking uses a **deterministic appointment doc ID** `'{trainerId}_{startsAtMs}'` so a Firestore `runTransaction` can `txn.get(docRef)` and create-if-not-exists in one safe step (query-based existence checks are NOT transactionally safe in Firestore). The Firestore rule provides defense in depth.

`startsAt` is stored as UTC Timestamp. Rules store clock-time integers (`startHour`, `startMinute`). Booking-time conversion uses `America/Argentina/Buenos_Aires` (UTC-3, no DST, hardcoded — single-TZ assumption for v1).

**24h cancellation cutoff** is enforced in two layers: client (`AppointmentRepository.cancel()` throws `CancellationTooLateException` if `startsAt - now < 24h`) and Firestore rule (`resource.data.startsAt.toMillis() - 86400000 > request.time.toMillis()`).

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `lib/features/coach/domain/` | New | 3 freezed models: `availability_rule.dart`, `availability_override.dart`, `appointment.dart` |
| `lib/features/coach/data/` | New | `availability_repository.dart`, `appointment_repository.dart` (incl. atomic booking transaction) |
| `lib/features/coach/application/agenda_providers.dart` | New | Riverpod providers (rules, overrides, computed slots, appointments) |
| `lib/features/coach/presentation/` | New | `trainer_agenda_tab.dart`, `athlete_agenda_screen.dart`, `availability_editor_screen.dart`, `widgets/day_slots_sheet.dart` |
| `lib/features/coach/trainer_coach_view.dart` | Modified | Replace `_SubTabPlaceholder` at TabBarView index 2 with `TrainerAgendaTab` |
| `lib/features/coach/athlete_coach_view.dart` | Modified | Insert "VER AGENDA DEL PF" button in `_LinkStateCard`, after `_ShareToggle`, before `_ActionRow`, conditional on active link |
| `lib/app/router.dart` | Modified | Add `/coach/agenda` route inside ShellRoute |
| `firestore.rules` | Modified | Add rules for 3 new collections (member-only reads, deterministic-ID booking guard, 24h cancel CEL) |
| `pubspec.yaml` | Modified | Add `table_calendar: ^3.2.0` |
| `scripts/deploy_rules.js` | Used | Deploy updated rules (no script changes) |
| `docs/roadmap.md` | Modified | Note divergence: Etapa 6 is asymmetric, not symmetric propose/confirm |

## PR Strategy

**Estimated total: ~1500 LOC, ~45 SCENARIOs → 3 chained PRs** targeting a feature branch.

| PR | Branch | Scope | Est. LOC |
|---|---|---|---|
| PR1 | `feat/coach-agenda-data` | 3 freezed models, 2 repos, providers, Firestore rules update + deploy, atomic booking transaction. No UI. | ~500-600 |
| PR2 | `feat/coach-agenda-ui-athlete` | Athlete calendar screen + day-slots bottom sheet + "VER AGENDA DEL PF" entry button + booking flow + past-appointments list. Depends on PR1. | ~400-500 |
| PR3 | `feat/coach-agenda-ui-trainer` | Trainer AGENDA tab (replaces placeholder) + availability editor screen + bookings view. Depends on PR1. PR2/PR3 order is interchangeable after PR1 lands. | ~500-600 |

Chained because PR2 + PR3 both depend on PR1's models + providers. Each PR stays within the 400-line review budget individually (PR1 may need a `size:exception` if rules + transaction code push it past 400; flag before apply). **`delivery_strategy: ask-on-risk` is active — `sdd-tasks` must surface this for confirmation.**

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Two athletes book same slot simultaneously (race) | Low | Deterministic doc ID + Firestore transaction `txn.get(docRef)` create-if-not-exists. Firestore rule as defense in depth. Client shows `"Ese horario fue reservado justo ahora"` if `AppointmentConflictException` is thrown. |
| Argentina TZ assumption (UTC-3 no DST since 2009) breaks if Argentina re-introduces DST | Very Low | Hardcode the offset in a single `const _kArgentinaOffsetHours = -3` so future fix is localized. Document the assumption in `availability_repository.dart`. |
| Dev C concurrent work on chat lives in `trainer_coach_view.dart` and `athlete_coach_view.dart` — merge conflict | Medium | Coordinate merge order: chat first OR coach-agenda-ui PRs first, not interleaved. Flag in PR descriptions. The data PR (PR1) is conflict-free and can land independently. |
| `table_calendar: ^3.2.0` is 16 months stale; may have unpinned transitive deps | Low | Verify exact resolved version before implementation; pin to `3.2.0` (not `^3.2.0`) if `pub upgrade` surfaces conflicts with `google_fonts` or `intl`. |
| Coach edits a rule while athlete is mid-booking (slot disappears between display and submit) | Low | Atomic transaction inside `AppointmentRepository.book()` re-reads the appointment doc ID; if the rule changed and the slot is no longer valid, the booking still succeeds (rule change doesn't invalidate the slot's absolute timestamp). Client SHOULD invalidate the slots provider on submit error so the next attempt reflects current rules. |
| Rule edit removes hours that have existing confirmed bookings (e.g., endHour 12→11 with a confirmed 11:30) | Low | Locked: existing appointments survive untouched. Document in editor screen empty/help text. No data migration. |
| Hardcoded 24h cancellation may not suit every coach | Medium | Documented tech debt. Per-coach `cancellationHours` deferred to Fase 6. |
| No notification when athlete books — coach may miss bookings | Medium | Documented gap. Coach sees bookings on next AGENDA tab open. Badge + push deferred to Fase 6. Add explicit copy in trainer empty/help text: `"Las nuevas reservas aparecen al volver a esta pestaña."` |

## Rollback Plan

- **Per PR**: standard `git revert` of the PR merge commit. PR1 is the only one with destructive impact (Firestore rules deploy + new collections); if rules need rollback, redeploy the previous `firestore.rules` via `scripts/deploy_rules.js`. Existing docs in the new collections become orphaned but cause no app crash since the UI is gated behind PR2/PR3.
- **Full feature rollback (post-merge)**: revert PR3 → PR2 → PR1 in that order. Athletes lose the "VER AGENDA DEL PF" button (gated UI, no crash). Trainer AGENDA tab reverts to `_SubTabPlaceholder`. Existing `appointments` docs remain but are inert.
- **Data**: no migrations, no data deletion required on rollback. New collection docs are inert without the UI.

## Dependencies

- Fase 5 Etapa 3 (link lifecycle) — MERGED. Required for `currentAthleteLinkProvider` and active-link gating.
- shared-with-trainer tech debt fix — MERGED today. Provides the rules infrastructure pattern for new collections (immutable field protection, member-only access).
- Fase 5 Etapa 5 (chat) — IN FLIGHT (Dev C). Not a hard dependency, but the coach tab files overlap. Coordinate merge order.
- `table_calendar: ^3.2.0` — to be added to `pubspec.yaml` in PR1.

## Success Criteria

- [ ] All ~45 SCENARIOs (defined in `sdd-spec`) pass `flutter test`.
- [ ] `flutter analyze` reports 0 issues.
- [ ] `dart format .` produces no diff.
- [ ] Firestore rules deployed via `scripts/deploy_rules.js` without errors.
- [ ] Manual smoke test on staging:
  - Coach defines a rule (e.g., Lunes 9-12, slot 60min). Rule appears in editor and is queryable.
  - Athlete opens `/coach/agenda`, sees Lunes with availability markers, taps a day, sees free slots, books one. Booking is atomic — second attempt on same slot fails with the conflict message.
  - Both coach and athlete see the booking in their respective views.
  - Athlete cancels >24h ahead → succeeds; slot returns to available.
  - Athlete cancels <24h ahead → fails (client error + rule rejection).
  - Coach edits the rule (endHour 12→11). The existing booking at 11:30 stays. New booking attempts at 11:30 fail (slot no longer offered).
- [ ] `docs/roadmap.md` updated to note Etapa 6 divergence from original propose/confirm design.

## Open Follow-ups for sdd-spec / sdd-design

These are not propose-blockers but need definitive treatment in the next phases:

- **Spec**: enumerate the ~45 SCENARIOs covering: rule create/edit/delete, override create/delete (block + extra), atomic booking happy path, double-booking race, 24h cancellation (both sides), rule-edit-during-booking, empty-state, past-appointments list, max-horizon clamp, deterministic doc ID validation.
- **Design**: pseudocode for `computeFreeSlots(date, rules, overrides, appointments)` — exact intersection algorithm and how it handles `extra` overrides that overlap with rule slots.
- **Design**: state diagram for `AppointmentRepository.book()` transaction (read deterministic doc → if exists+confirmed → conflict; if exists+cancelled → reuse or reject?). Recommend rejecting cancelled docs and using a different ID strategy if the same slot was cancelled and someone wants to re-book — OR allow `status: cancelled → confirmed` flip in transaction. Lock this in design.
- **Design**: Riverpod provider graph — which providers are `StreamProvider` vs `FutureProvider`, invalidation flows after booking/cancellation.
- **Design**: error UX copy in Rioplatense for: conflict, late cancellation, network failure, rule-no-longer-valid.
