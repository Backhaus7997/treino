# Exploration: coach-agenda

**Change**: `coach-agenda`
**Fase / Etapa**: Fase 5 · Etapa 6
**Project**: treino
**Artifact store**: hybrid (engram + openspec)
**Engram key**: `sdd/coach-agenda/explore`

---

## Design Divergence from Roadmap

The roadmap at `docs/roadmap.md:285` defines Etapa 6 as a **symmetric propose/confirm** flow:
> "Cualquier member del link activo puede proponer; el otro debe confirmar."
> `status: 'proposed' | 'confirmed' | 'cancelled'` — 3-value enum.

**Deliberately replaced** with an asymmetric **coach-controlled availability** model per product feedback:
- Coach publishes availability rules (recurring weekly slots). Athletes book immediately — atomic, no confirmation step.
- `status` enum shrinks to **2 values**: `confirmed | cancelled`. No `proposed` state.
- Removes confirmation round-trip; matches real PT scheduling behavior.

## Current State

**`TrainerCoachView`** (`lib/features/coach/trainer_coach_view.dart`):
- 4 sub-tabs: DASHBOARD, ALUMNOS, AGENDA, COMUNIDADES
- AGENDA sub-tab is `_SubTabPlaceholder(label: 'AGENDA')` — shows "PRÓXIMAMENTE"
- Plug point: replace placeholder at index 2 of `TabBarView.children` with `TrainerAgendaTab()`

**`AthleteCoachView`** (`lib/features/coach/athlete_coach_view.dart`):
- Active link renders `_LinkStateCard` which contains `_ShareToggle` (Etapa 5 privacy gate)
- Athlete agenda entry point ("VER AGENDA DEL PF") slots AFTER `_ShareToggle`, BEFORE `_ActionRow`, conditional on `link.status == TrainerLinkStatus.active`

**`TrainerLink` model**: no changes needed.

**`TrainerLinkRepository`**: existing providers reusable (`currentAthleteLinkProvider`).

**Firestore rules patterns**: existing `trainer_links` member-gate + immutable-field pattern, `routines` create with anti-spoofing `assignedBy == request.auth.uid` — replicate.

**Router** (`lib/app/router.dart`): add `/coach/agenda` sub-route inside ShellRoute under `/coach`.

**`table_calendar` package**: NOT in `pubspec.yaml`. Add `table_calendar: ^3.2.0`. Compatible with Flutter 3.41 / Dart ^3.5.0.

## New Firestore Collections

**`coach_availability_rules/{ruleId}`**
```
trainerId: String, dayOfWeek: int (1=Mon…7=Sun ISO),
startHour: int, startMinute: int, endHour: int, endMinute: int,
slotDurationMinutes: int, createdAt: Timestamp, updatedAt: Timestamp
```

**`coach_availability_overrides/{overrideId}`**
```
trainerId: String, date: String ('YYYY-MM-DD' local AR),
type: 'block' | 'extra',
startHour: int?, startMinute: int?, endHour: int?, endMinute: int?,
slotDurationMinutes: int?, createdAt: Timestamp
```

**`appointments/{appointmentId}`** (deterministic ID: `'${trainerId}_${startsAtMs}'`)
```
trainerId: String, athleteId: String, linkId: String,
startsAt: Timestamp (UTC), durationMinutes: int,
status: 'confirmed' | 'cancelled',
cancelledAt: Timestamp?, cancelledBy: String?, createdAt: Timestamp
```

## Approaches: Slot Generation

| | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | Computed-at-read (client) | Zero storage; instant rule updates | More client logic | Medium |
| B | Materialized slots (Cloud Function) | Simple queries | Requires CF (out of scope); stale on rule change | High |
| **C** | **Hybrid: rules + appointments, compute free slots client-side** | **No CF; atomic booking via deterministic doc ID + txn; rule changes leave existing bookings untouched** | Client computes per date view | **Medium** |

**Recommendation: C (Hybrid).** Deterministic appointment doc ID converts "no duplicate slot" into a standard `create-if-not-exists` Firestore transaction — safe, atomic, no Cloud Function needed.

## Atomicity of Booking

**CRITICAL**: Firestore `collection().where()` is NOT transactionally safe. Correct pattern uses **deterministic document ID**: `'${trainerId}_${startsAtMs}'`. `transaction.get(docRef)` on that ID is atomic. If doc exists → conflict. If not → create. Eliminates double-booking race without Cloud Function.

Firestore rule defense-in-depth: `appointments` create rule checks `status == 'confirmed'` and `athleteId == request.auth.uid`.

## Time Zone / Timestamp

- Rules store clock-time integers (`startHour`, `startMinute`).
- At booking: client computes `DateTime(year, month, day, h, m)` in AR local time → `.toUtc()` → Firestore Timestamp.
- v1: single TZ `America/Argentina/Buenos_Aires` (UTC-3, no DST). No `timezone` package needed.
- Display: `.toLocal()`.

## Cancellation Enforcement

- **N = 24h** (recommended; hardcoded for v1).
- Client-side: throws `CancellationTooLateException` if `startsAt.difference(now) < 24h`.
- Firestore rule guard: `appointments` update rule checks `resource.data.startsAt.toMillis() - 86400000 > request.time.toMillis()`.
- Future: `trainerPublicProfile.cancellationHours` per-coach (deferred).

## Affected Areas

| File | Why |
|---|---|
| `lib/features/coach/trainer_coach_view.dart` | Replace AGENDA placeholder |
| `lib/features/coach/athlete_coach_view.dart` | "VER AGENDA DEL PF" button in `_LinkStateCard` |
| `lib/app/router.dart` | Add `/coach/agenda` sub-route |
| `pubspec.yaml` | Add `table_calendar: ^3.2.0` |
| `firestore.rules` | 3 new collections |
| NEW `lib/features/coach/domain/appointment.dart` | freezed |
| NEW `lib/features/coach/domain/availability_rule.dart` | freezed |
| NEW `lib/features/coach/domain/availability_override.dart` | freezed |
| NEW `lib/features/coach/data/appointment_repository.dart` | CRUD + atomic booking via txn |
| NEW `lib/features/coach/data/availability_repository.dart` | rules + overrides CRUD |
| NEW `lib/features/coach/application/agenda_providers.dart` | Riverpod providers |
| NEW `lib/features/coach/presentation/trainer_agenda_tab.dart` | trainer AGENDA sub-tab |
| NEW `lib/features/coach/presentation/athlete_agenda_screen.dart` | athlete calendar view |
| NEW `lib/features/coach/presentation/availability_editor_screen.dart` | coach sets rules |
| NEW `lib/features/coach/presentation/widgets/day_slots_sheet.dart` | day tap bottom sheet |

## Open Questions for Propose

1. Cancellation cutoff: **24h recommended** — confirm.
2. Slot duration: enum `[30, 60, 90, 120]` min (recommend enum to avoid edge cases).
3. Multiple rules per day ("Lunes 8-12 AND 16-20")? **YES** recommended.
4. Rule edit vs existing bookings: existing `confirmed` survive untouched; new bookings use updated rule — confirm acceptable.
5. Athlete agenda as full-screen route `/coach/agenda` vs bottom sheet — **full-screen route** recommended.
6. "No availability" state: empty-state illustration + "Tu PF todavía no configuró horarios."
7. Past appointments visible to athlete? **YES** recommended (simple list below calendar).
8. Max booking horizon: **4 weeks** computed at load — confirm.

## Out of Scope

Google Calendar sync · Push notifications · Group sessions · Multi-coach per athlete · Multi-TZ · Automatic pre-session reminders · PF-sees-athlete-historial.

## Risks

- `table_calendar ^3.2.0` published ~16 months ago — verify no breaking change before implementation.
- Deterministic doc ID requires millisecond precision; safe given min 30-min slot spacing.
- Firestore `where()` inside transaction is NOT atomic (common mistake) — must use deterministic doc ID.
- Argentina UTC-3 no DST (confirm).
- `currentAthleteLinkProvider` is FutureProvider — booking won't auto-refresh calendar without explicit `ref.invalidate`. May upgrade to StreamProvider for appointments.

## Ready for Proposal

YES. All architecture answered. 8 open product questions for propose to lock.
