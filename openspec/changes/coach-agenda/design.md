# Design: Coach Agenda (Fase 5 · Etapa 6)

## Context

Asymmetric scheduling layer. Trainer publishes recurring `coach_availability_rules` + date `coach_availability_overrides`; athlete books free slots immediately via deterministic-ID atomic Firestore transactions. 24h cancel cutoff enforced client + rules. 3 chained PRs (~1500 LOC). See proposal `#116`, spec `#117`.

The spec surfaces two normative tensions design must resolve: (1) re-bookability of cancelled deterministic-ID slots (SCENARIO-491 currently locks "exhausted"), and (2) free-slot computation when an existing appointment falls outside an edited rule (REQ-026). Both are addressed below.

## Architecture Overview

```
        ┌──────────────────────── presentation ────────────────────────┐
        │                                                              │
   AthleteAgendaScreen          TrainerAgendaTab + AvailabilityEditor  │
   └─ _DaySlotsSheet            └─ slot tiles (free / booked)          │
        │                                  │                           │
        ▼                                  ▼                           │
   ┌──────────────── application (Riverpod) ─────────────────────────┐ │
   │ availabilityRulesProvider     appointmentsForAthleteProvider    │ │
   │ availabilityOverridesProvider appointmentsForTrainerProvider    │ │
   │            freeSlotsProvider (derived, pure compute)            │ │
   └─────────────────────────────────────────────────────────────────┘ │
        │                                  │                           │
        ▼                                  ▼                           │
   AvailabilityRepository          AppointmentRepository               │
   (CRUD rules+overrides,          (atomic book, cancel, watch         │
    StreamProvider sources)         for-athlete / for-trainer)         │
        │                                  │                           │
        ▼                                  ▼                           │
   ┌──────────────────────── Firestore ──────────────────────────────┐ │
   │ coach_availability_rules/{id}                                   │ │
   │ coach_availability_overrides/{id}                               │ │
   │ appointments/{trainerId}_{startsAtMs}    (deterministic id)     │ │
   │ + firestore.rules: member read, link-gated create, 24h CEL      │ │
   └─────────────────────────────────────────────────────────────────┘ │
        └──────────────────────────────────────────────────────────────┘
```

Data flow on book: `_DaySlotsSheet → confirm dialog → AppointmentRepository.book → runTransaction(txn.get + txn.set) → on success ref.invalidate(appointmentsForAthleteProvider) → freeSlotsProvider rebuilds (derives from new appointments stream emission) → sheet closes + snackbar`.

---

## ADR-1 — Cancelled-slot doc ID strategy

**Choice**: Option B — **flip `status: cancelled → confirmed` in the same transaction** when a new athlete books a deterministic ID whose existing doc is `cancelled`. Audit lives on the doc itself via `cancellationLog: List<{at, byUid, reason}>` (additive, not overwrite). SCENARIO-491 in the spec is reclassified as a design follow-up — it MUST be replaced with a `cancelled → confirmed flip` scenario.

**Rationale**: real UX win. Trainer reschedules → cancelled athlete drops → new athlete books same time = should work. Hybrid (Option C, suffix `_v2`) breaks doc ID predictability across the rule layer (CEL guard uses `request.resource.id` parsing); permanent burn (Option A) gives ugly false negatives. Keeping the audit on the doc (a `cancellationLog` array) preserves history without inventing a sub-collection now.

**Alternatives**:
| Option | Pro | Con |
|---|---|---|
| A — permanent burn | simplest | rare bad UX, false "slot taken" |
| B — flip + log (CHOSEN) | re-bookable, audit kept | transaction body has 2 branches |
| C — `_v2` suffix doc | full history | breaks rule CEL + query simplicity |

**Consequences**: transaction body checks `data.status`: if absent or `cancelled` → set/overwrite to `confirmed` (preserving `cancellationLog` from previous body); if `confirmed` → throw `SlotAlreadyTakenException`. Spec SCENARIO-491 must be rewritten in tasks phase to: "GIVEN cancelled doc exists, WHEN book is called, THEN status flips to confirmed, athleteId updates, and cancellationLog retains prior cancel entry."

**Risks**: tests in PR1 must explicitly cover the flip path; firestore.rules `allow update` must permit `status: cancelled → confirmed` when caller has active link (ADD a 4th CEL clause).

---

## ADR-2 — `computeFreeSlots` algorithm

**Choice**: pure Dart function in `lib/features/coach/application/compute_free_slots.dart` taking `(DateTime date, List<AvailabilityRule>, List<AvailabilityOverride>, List<Appointment>)` → `List<DateTime>` (UTC). Reused by athlete `_DaySlotsSheet`, trainer slot visualization, and unit tests.

**Algorithm** (per day, given `trainerId` + `date`):

```
1. blockOverride = overrides.firstWhere(o.date==date && o.type==block, orNull)
   if blockOverride exists → return []   // whole day cancelled
2. slotSet = SplayTreeSet<DateTime>()  // sorted, dedupe-by-equality
3. for rule in rules where rule.dayOfWeek == date.weekday:
       cursor = date @ rule.startHour:rule.startMinute (UTC, sec=0, ms=0)
       endCursor = date @ rule.endHour:rule.endMinute
       while cursor + rule.slotDurationMin <= endCursor:
           slotSet.add(cursor)
           cursor += rule.slotDurationMin
4. for extraOverride in overrides where date==date && type==extra:
       same loop, slotSet.add(...)        // SplayTreeSet dedupes overlapping rule+extra
5. for appt in appointments where appt.startsAt.date == date && status == confirmed:
       slotSet.remove(appt.startsAt)      // surviving-confirmed slot disappears from free list
6. return slotSet.toList()
```

**Complexity**: O(R × S + O + A) per day where R=rules-for-weekday (≤4 realistic), S=slots-per-rule (≤16), O=overrides-for-date, A=appointments-for-date. Trivial.

**Edge cases handled**:
- Overlapping rules (Mon 8-12 + Mon 10-14): SplayTreeSet dedupes
- `extra` overlapping `rule` slot: dedupes
- `block` for date with no rule: no-op (step 1 returns `[]` either way)
- Confirmed appt outside any current rule (REQ-026): NOT added to free list (step 5 only `remove`s, never adds). The booking still appears in `appointmentsForTrainerProvider` view — it just doesn't show as free.
- Past dates: caller (UI) clamps; function itself returns slots strictly; `_DaySlotsSheet` filters `slot > DateTime.now()`.
- DST: hardcoded `_kArgentinaOffsetHours = -3`. v1 assumption documented in proposal.

---

## ADR-3 — Riverpod provider graph + invalidation

**Choice**: all 4 sources are `StreamProvider`. `freeSlotsProvider` is a derived `Provider` (not Stream — synchronous compute) family-keyed by `(trainerId, date)` that `ref.watch`es the 3 upstream streams and runs `computeFreeSlots`.

```dart
// lib/features/coach/application/agenda_providers.dart
final availabilityRulesProvider =
    StreamProvider.autoDispose.family<List<AvailabilityRule>, String>(...);
final availabilityOverridesProvider =
    StreamProvider.autoDispose.family<List<AvailabilityOverride>, _OverrideKey>(...);
final appointmentsForAthleteProvider =
    StreamProvider.autoDispose.family<List<Appointment>, String>(...);
final appointmentsForTrainerProvider =
    StreamProvider.autoDispose.family<List<Appointment>, _TrainerRangeKey>(...);

final freeSlotsProvider =
    Provider.autoDispose.family<AsyncValue<List<DateTime>>, _SlotKey>((ref, key) {
  final rules = ref.watch(availabilityRulesProvider(key.trainerId));
  final overrides = ref.watch(availabilityOverridesProvider(...));
  final appts = ref.watch(appointmentsForTrainerProvider(...));
  // combine 3 AsyncValues → compute → AsyncData / AsyncLoading
});
```

**Family key wrapper classes** (e.g. `_OverrideKey`, `_SlotKey`) MUST be `@freezed` to get value equality — critical for Riverpod family cache hits.

**Invalidation on mutation**:
| Mutation | Manual `ref.invalidate(...)` |
|---|---|
| `book` success | none — stream auto-emits |
| `cancel` success | none — stream auto-emits |
| `addRule / updateRule / deleteRule` | none — `watchRules` stream auto-emits |
| `addOverride / deleteOverride` | none — stream auto-emits |
| `book` race conflict | `availabilityOverridesProvider` + `appointmentsForTrainerProvider` ← explicit invalidate to force resync (cheap safety net) |

**Rationale**: streams give real-time PF feedback (REQ-026 expects "trainer sees bookings without manual refresh"). Cost is acceptable — 1 athlete views 1 PF's data, scale is small. `FutureProvider` was rejected for appointments because it would require manual invalidation after every mutation and miss the race-conflict signal.

---

## ADR-4 — Error copy library

**Choice**: new file `lib/features/coach/presentation/agenda_strings.dart` mirroring `coach_strings.dart`. ALL agenda visible strings live here. No inline literals in widgets per project convention (AGENTS.md).

```dart
abstract final class AgendaStrings {
  // Errors
  static const slotTakenRace = 'Ese horario fue reservado justo ahora. Probá con otro.';
  static const cancelTooLate = 'No podés cancelar con menos de 24h de anticipación.';
  static const bookingTooFar = 'No podés reservar con más de 4 semanas de anticipación.';
  static const genericError = 'Hubo un problema. Intentá de nuevo.';

  // Empty states
  static const athleteEmptyNoRules = 'Tu PF todavía no configuró horarios.';
  static const trainerEmptyNoRules =
      "Todavía no configuraste horarios. Tocá 'Configurar horarios' para empezar.";

  // Dialogs
  static String confirmBooking(String date, String time) =>
      '¿Confirmar reserva el $date a las $time?';
  static const confirmCancel = '¿Cancelar esta reserva?';

  // Success
  static const bookingSuccess = 'Reserva confirmada.';
  static const cancelSuccess = 'Reserva cancelada.';

  // Editor
  static const editorTitle = 'Configurar horarios';
  static const editorAddRule = 'Agregar horario';
  static const editorAddOverride = 'Agregar excepción';
  static const editorRuleSurvivesEditHelp =
      'Editar o eliminar un horario NO cancela reservas ya confirmadas.';

  // Entry button
  static const verAgendaButton = 'VER AGENDA DEL PF';

  // Calendar markers
  static const slotFreeLabel = 'Libre';
  static const slotBookedPrefix = ''; // e.g. "09:00 — Juan P." (no prefix)
}
```

**Rationale**: matches established `coach_strings.dart` pattern (Etapa 4). All Rioplatense, voseo. Locked at design time so spec scenarios reference exact strings.

---

## ADR-5 — Atomic booking transaction implementation

**Choice**: implement exactly as proposal sketch, with the ADR-1 flip branch:

```dart
Future<Appointment> book(BookingRequest req) async {
  final now = DateTime.now().toUtc();
  if (req.startsAt.difference(now) > const Duration(days: 28)) {
    throw BookingTooFarAheadException();
  }
  final idMs = req.startsAt.millisecondsSinceEpoch;
  final docRef = _firestore
      .collection('appointments')
      .doc('${req.trainerId}_$idMs');

  return _firestore.runTransaction<Appointment>((txn) async {
    final snap = await txn.get(docRef);
    if (snap.exists) {
      final data = snap.data()!;
      if (data['status'] == 'confirmed') {
        throw SlotAlreadyTakenException();
      }
      // ADR-1: flip cancelled → confirmed, preserve cancellationLog
    }
    final appt = Appointment(
      id: docRef.id,
      trainerId: req.trainerId,
      athleteId: req.athleteId,
      athleteDisplayName: req.athleteDisplayName,
      startsAt: req.startsAt,
      durationMin: req.durationMin,
      status: AppointmentStatus.confirmed,
    );
    final payload = appt.toJson();
    if (snap.exists) {
      payload['cancellationLog'] = snap.data()!['cancellationLog'] ?? [];
    }
    txn.set(docRef, payload);
    return appt;
  });
}
```

**Firestore SDK gotchas confirmed**:
- `runTransaction<T>` retries up to 5 times on contention; idempotent because `txn.get` is re-read each retry.
- All reads MUST happen before any writes inside the lambda — our 1 read / 1 write order is compliant.
- Throwing from inside the lambda aborts the transaction without commit and rethrows to caller.

**`startsAt` precision** (ADR-7 below): caller MUST normalize to minute precision before passing to `book`. Repository asserts `req.startsAt.second == 0 && req.startsAt.millisecond == 0`.

---

## ADR-6 — Override schema: single collection with optional fields

**Choice**: Option A — single `coach_availability_overrides` collection, fields nullable based on `type` discriminator. Freezed model uses sealed-union style via `@freezed` factory variants (`AvailabilityOverride.block({...})` and `AvailabilityOverride.extra({...})`) producing a single discriminated JSON shape with `type` field.

**Rationale**:
- Single collection = single watch query for `_DaySlotsSheet` and trainer editor (vs 2 streams to combine).
- Freezed union gives compile-time safety client-side (impossible to construct a `block` with hours, impossible to construct `extra` without hours) — addresses the "nullable fields validation tricky" con of Option A.
- Firestore rule validates: `type == 'block'` → time fields absent; `type == 'extra'` → time fields present and valid ranges.

**Alternatives**: two collections (`coach_availability_blocks`, `coach_availability_extras`). Rejected because the editor and `computeFreeSlots` always need BOTH together — splitting collections only adds query cost without simplification.

**Schema shape (Firestore)**:
```json
// block
{ "id":"…","trainerId":"…","date":<Timestamp>,"type":"block" }
// extra
{ "id":"…","trainerId":"…","date":<Timestamp>,"type":"extra",
  "startHour":10,"startMinute":0,"endHour":12,"endMinute":0,"slotDurationMin":60 }
```

---

## ADR-7 — Time precision contract for `startsAtMs`

**Choice**: ALL `startsAt` values constructed within the agenda module MUST have `second == 0 && millisecond == 0 && microsecond == 0`. Enforced by:
1. `computeFreeSlots` only emits minute-precision UTC DateTimes (loop step is `Duration(minutes: slotDurationMin)`, base is `DateTime.utc(y,m,d,h,m,0,0)`).
2. `BookingRequest` constructor asserts the precision invariant.
3. `Appointment.fromJson` does NOT enforce precision (legacy / Admin SDK writes might violate) but `book` and `cancel` operate by document ID — no risk of mismatch.

**Rationale**: avoids two slots that are "the same" generating different deterministic IDs (e.g. `1748000000123` vs `1748000000456`). Documented in code as a contract; violations would break the atomic booking guarantee.

---

## File Changes

| File | Action | Description |
|---|---|---|
| `lib/features/coach/domain/availability_rule.dart` (+`.freezed.dart`+`.g.dart`) | Create | freezed model, JSON round-trip, `slotDurationMin` enum validator |
| `lib/features/coach/domain/availability_override.dart` (+gen) | Create | freezed union (`.block`/`.extra`), discriminated JSON |
| `lib/features/coach/domain/appointment.dart` (+gen) | Create | freezed model, deterministic id factory, `status` enum, `cancellationLog` list |
| `lib/features/coach/domain/agenda_exceptions.dart` | Create | `SlotAlreadyTakenException`, `CancellationTooLateException`, `BookingTooFarAheadException` |
| `lib/features/coach/data/availability_repository.dart` | Create | rule + override CRUD, watch streams |
| `lib/features/coach/data/appointment_repository.dart` | Create | `book` (transaction), `cancel` (with cutoff), `watchForAthlete`, `watchForTrainer` |
| `lib/features/coach/application/agenda_providers.dart` | Create | 4 StreamProviders + freezed family keys + repository providers |
| `lib/features/coach/application/compute_free_slots.dart` | Create | pure function, unit-testable |
| `lib/features/coach/presentation/agenda_strings.dart` | Create | locked Rioplatense copy (ADR-4) |
| `lib/features/coach/presentation/athlete_agenda_screen.dart` | Create | route `/coach/agenda`, TableCalendar + past list |
| `lib/features/coach/presentation/widgets/day_slots_sheet.dart` | Create | bottom sheet, chips, booking confirm flow |
| `lib/features/coach/presentation/trainer_agenda_tab.dart` | Create | replaces `_SubTabPlaceholder` at TabBarView idx 2 |
| `lib/features/coach/presentation/availability_editor_screen.dart` | Create | rules + overrides editor |
| `lib/features/coach/athlete_coach_view.dart` | Modify | inject "VER AGENDA DEL PF" button in `_LinkStateCard` between `_ShareToggle` and `_ActionRow`, gated on `link.status == active` |
| `lib/features/coach/trainer_coach_view.dart` | Modify | TabBarView idx 2 → `TrainerAgendaTab()` |
| `lib/app/router.dart` | Modify | add `GoRoute(path: 'agenda', ...)` as child of `/coach` ShellRoute branch |
| `firestore.rules` | Modify | 3 new collection blocks (member read, deterministic-id booking guard, 24h CEL, link-gated create, status flip allowed) |
| `pubspec.yaml` | Modify | `table_calendar: ^3.2.0` |
| `docs/roadmap.md` | Modify | note asymmetric divergence from original symmetric design |

No deletes.

---

## Interfaces / Contracts

```dart
// Booking request — minute-precision invariant enforced
class BookingRequest {
  BookingRequest({
    required this.trainerId,
    required this.athleteId,
    required this.athleteDisplayName,
    required this.startsAt,
    required this.durationMin,
  }) : assert(startsAt.second == 0 && startsAt.millisecond == 0
                  && startsAt.microsecond == 0,
                'startsAt MUST be minute-precision UTC');
  final String trainerId;
  final String athleteId;
  final String athleteDisplayName;
  final DateTime startsAt;
  final int durationMin;
}
```

```dart
// Repository contracts (informal — see SCENARIOs 485-495)
abstract class AvailabilityRepository {
  Future<void> addRule(AvailabilityRule rule);
  Future<void> updateRule(AvailabilityRule rule);
  Future<void> deleteRule(String trainerId, String ruleId);
  Stream<List<AvailabilityRule>> watchRules(String trainerId);
  Future<void> addOverride(AvailabilityOverride override);
  Future<void> deleteOverride(String trainerId, String overrideId);
  Stream<List<AvailabilityOverride>> watchOverrides(
      String trainerId, DateTime from, DateTime to);
}

abstract class AppointmentRepository {
  Future<Appointment> book(BookingRequest req);
  Future<void> cancel(String appointmentId, DateTime now,
      {required String byUid});
  Stream<List<Appointment>> watchForAthlete(String athleteId);
  Stream<List<Appointment>> watchForTrainer(
      String trainerId, DateTime from, DateTime to);
}
```

---

## Testing Strategy

| Layer | What | Approach | Spec coverage |
|---|---|---|---|
| Unit — domain | JSON round-trip, enum encoding, deterministic id format | pure Dart `test/` | SCENARIOs 478-484 |
| Unit — `computeFreeSlots` | overlap dedupe, block, extra, rule-edit-survivor | pure Dart `test/` | derived from REQ-026, 517-519 |
| Repository | rule/override CRUD, book happy + race + flip, cancel ±24h, horizon | `fake_cloud_firestore` | SCENARIOs 485-496 |
| Provider | family-key equality, stream emit + invalidate flow | `ProviderContainer` + fake repos | REQ-010 (covered via integration) |
| Widget | calendar dots, sheet chips, snackbars, button visibility | `testWidgets` + override providers | SCENARIOs 497-523 |
| Rules | member read, link-gated create, 24h CEL, status flip allowed | `scripts/rules_test/rules.test.js` emulator (deferred per Decision #25) | SCENARIOs 525-527 |

Strict TDD ACTIVE: every SCENARIO gets a RED test before implementation. Test runner: `flutter test`.

---

## Migration / Rollout

No data migration — 3 new collections, no existing docs. Rollout per proposal: PR1 (data, may need `size:exception`), PR2 (athlete UI), PR3 (trainer UI). PR3 depends on PR1 only. Firestore rules deploy alongside PR1 merge via `scripts/deploy_rules.js`. Rollback: `git revert` per PR + redeploy previous rules for PR1.

---

## Open Questions / Follow-ups for sdd-tasks

- [ ] Spec SCENARIO-491 must be REWRITTEN in tasks phase (or noted as a spec amendment) to reflect ADR-1 flip semantics — current spec text contradicts ADR-1 and will fail test as written.
- [ ] Firestore rule for `appointments` `allow update` must permit the `cancelled → confirmed` flip when caller has an active link — add to PR1 rules block.
- [ ] `_OverrideKey`, `_SlotKey`, `_TrainerRangeKey` freezed classes need explicit naming convention (private to providers file; underscore prefix accepted by freezed gen).
- [ ] Confirm `table_calendar 3.2.0` resolves cleanly against current Flutter SDK before PR2 starts — `flutter pub get` check in PR1.

---

## Ready-for-tasks Checklist

- [x] All 6+1 ADRs documented with rationale + alternatives + risks
- [x] Architecture diagram + data flow
- [x] All file changes enumerated with paths matching existing conventions
- [x] Repository + provider contracts specified
- [x] Testing strategy maps to spec SCENARIOs
- [x] Normative tensions from spec (cancelled re-booking, rule-edit survivor) resolved
- [x] No new external dependencies beyond `table_calendar` (already in proposal)
- [x] Rollback plan inherited from proposal
- [ ] Spec SCENARIO-491 amendment captured as follow-up for sdd-tasks
