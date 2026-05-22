# Spec: shared-with-trainer (Fase 5 · Tech Debt)

**Change**: `shared-with-trainer`
**REQ namespace**: `REQ-COACH-LINK-NNN`
**SCENARIO range**: 464–477 (14 total)
**Capabilities touched**:
- ANNOTATED: `coach-link-lifecycle` — adds `sharedWithTrainer` field, repo method, Firestore rule extension, and athlete UI toggle

---

## Annotated Capability: `coach-link-lifecycle`

### Annotation note

`TrainerLink` is extended with a new boolean privacy field `sharedWithTrainer` (`@Default(false)`).
`TrainerLinkRepository` gains one focused method: `setSharedWithTrainer`. The Firestore update rule
is extended with an athlete-only OR clause that permits flipping this field. `_LinkStateCard` in
`athlete_coach_view.dart` gains a `SwitchListTile`-style toggle visible only when `link.status == active`.
All existing lifecycle transitions (`request`, `accept`, `decline`, `cancel`, `terminate`) are
unchanged. No existing requirements are removed.

---

## Requirements — `coach-link-lifecycle` additions

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-LINK-001 | `TrainerLink.sharedWithTrainer` field — model contract | MUST |
| REQ-COACH-LINK-002 | `TrainerLink.sharedWithTrainer` default value | MUST |
| REQ-COACH-LINK-003 | `TrainerLinkRepository.setSharedWithTrainer` — update contract | MUST |
| REQ-COACH-LINK-004 | `setSharedWithTrainer` field isolation — no side effects | MUST |
| REQ-COACH-LINK-005 | `setSharedWithTrainer` missing link throws | MUST |
| REQ-COACH-LINK-006 | `setSharedWithTrainer` stamps only `sharedWithTrainer` | MUST |
| REQ-COACH-LINK-007 | Toggle visible only when `link.status == active` | MUST |
| REQ-COACH-LINK-008 | Toggle reflects `link.sharedWithTrainer` | MUST |
| REQ-COACH-LINK-009 | Enabling toggle shows confirmation dialog | MUST |
| REQ-COACH-LINK-010 | Confirming dialog calls repo and invalidates provider | MUST |
| REQ-COACH-LINK-011 | Disabling toggle skips dialog and calls repo directly | MUST |
| REQ-COACH-LINK-012 | Firestore rule — athlete can flip `sharedWithTrainer` | MUST |
| REQ-COACH-LINK-013 | Firestore rule — trainer CANNOT flip `sharedWithTrainer` | MUST |
| REQ-COACH-LINK-014 | Firestore rule — non-member CANNOT update the document | MUST |

---

## REQ-COACH-LINK-001 — `TrainerLink.sharedWithTrainer` field — model contract

`TrainerLink` MUST declare a `bool sharedWithTrainer` field annotated with
`@Default(false)` in the freezed factory so that:
- JSON deserialization succeeds when the `sharedWithTrainer` key is absent (legacy docs).
- `TrainerLink.toJson()` serializes the field as `"sharedWithTrainer": <bool>`.
- The freezed round-trip preserves the value unchanged.

#### SCENARIO-464: `TrainerLink` round-trip preserves `sharedWithTrainer: true`

- GIVEN a `TrainerLink` constructed with `sharedWithTrainer: true` and all required fields
- WHEN `TrainerLink.fromJson(link.toJson())` is called
- THEN the deserialized instance has `sharedWithTrainer == true`
- AND all other fields are unchanged

---

## REQ-COACH-LINK-002 — `TrainerLink.sharedWithTrainer` default value

When a `TrainerLink` is deserialized from a JSON map that does NOT contain the key
`sharedWithTrainer`, the resulting instance MUST have `sharedWithTrainer == false`.

#### SCENARIO-465: `TrainerLink.fromJson` defaults `sharedWithTrainer` to `false` when key absent

- GIVEN a JSON map with all required `TrainerLink` fields except `sharedWithTrainer`
- WHEN `TrainerLink.fromJson(map)` is called
- THEN the resulting instance has `sharedWithTrainer == false`

---

## REQ-COACH-LINK-003 — `TrainerLinkRepository.setSharedWithTrainer` — update contract

`TrainerLinkRepository` MUST expose:

```
Future<void> setSharedWithTrainer(String linkId, bool value)
```

The method MUST call `docRef.update({'sharedWithTrainer': value})` on the document
`trainer_links/{linkId}`. It MUST NOT write any other field.

#### SCENARIO-466: `setSharedWithTrainer` updates only `sharedWithTrainer` in Firestore

- GIVEN a `trainer_links` document with `sharedWithTrainer: false` and `status: 'active'`
- WHEN `setSharedWithTrainer(linkId, true)` is called
- THEN the document at `trainer_links/{linkId}` has `sharedWithTrainer == true`
- AND the `status`, `trainerId`, `athleteId`, and `requestedAt` fields are unchanged

---

## REQ-COACH-LINK-004 — `setSharedWithTrainer` field isolation — no side effects

The method MUST NOT touch any other field on the document — specifically `updatedAt` MUST NOT
be written (no such field exists in the schema; adding it would break the no-updatedAt convention
established by all other `TrainerLinkRepository` update methods).

*(Validated by SCENARIO-466 assertions on unchanged fields.)*

---

## REQ-COACH-LINK-005 — `setSharedWithTrainer` missing link throws

When `setSharedWithTrainer` is called with a `linkId` that does not exist in Firestore,
the method MUST surface the resulting `FirebaseException` to the caller. It MUST NOT swallow
the exception or return silently.

#### SCENARIO-467: `setSharedWithTrainer` propagates exception for missing document

- GIVEN no document exists at `trainer_links/non-existent-id`
- WHEN `setSharedWithTrainer('non-existent-id', true)` is called
- THEN a `FirebaseException` (or `Exception`) is thrown
- AND no silent no-op occurs

---

## REQ-COACH-LINK-006 — `setSharedWithTrainer` idempotent write

Calling `setSharedWithTrainer(linkId, false)` when `sharedWithTrainer` is already `false`
MUST NOT throw. The document MUST remain with `sharedWithTrainer == false`.

#### SCENARIO-468: `setSharedWithTrainer` with unchanged value is idempotent

- GIVEN a document with `sharedWithTrainer: false`
- WHEN `setSharedWithTrainer(linkId, false)` is called
- THEN no exception is thrown
- AND the document still has `sharedWithTrainer == false`

---

## REQ-COACH-LINK-007 — Toggle visible only when `link.status == active`

The `sharedWithTrainer` toggle inside `_LinkStateCard` MUST be rendered in the widget tree
only when `link.status == TrainerLinkStatus.active`. When `link.status` is `pending`,
`paused`, or `terminated`, no toggle widget MUST be present in the tree.

#### SCENARIO-469: toggle is present when link is active

- GIVEN `currentAthleteLinkProvider` returns a `TrainerLink` with `status: active`
- WHEN `_LinkStateCard` renders
- THEN a switch or toggle widget for "Compartir historial con mi PF" is visible in the widget tree

#### SCENARIO-470: toggle is absent when link is pending

- GIVEN `currentAthleteLinkProvider` returns a `TrainerLink` with `status: pending`
- WHEN `_LinkStateCard` renders
- THEN no switch or toggle widget for "Compartir historial con mi PF" is present in the tree

---

## REQ-COACH-LINK-008 — Toggle reflects `link.sharedWithTrainer`

The toggle MUST reflect the current value of `link.sharedWithTrainer` at render time.
When `link.sharedWithTrainer == true` the toggle MUST be on; when `false`, the toggle MUST be off.

#### SCENARIO-471: toggle is on when `link.sharedWithTrainer == true`

- GIVEN a `TrainerLink` with `status: active` and `sharedWithTrainer: true`
- WHEN `_LinkStateCard` renders
- THEN the toggle widget has `value: true` (switch is on)

---

## REQ-COACH-LINK-009 — Enabling toggle shows confirmation dialog

When the athlete taps the toggle to switch from `false → true` (enable sharing), a
confirmation dialog MUST appear before any repo call is made. The dialog MUST use the
`_confirm()` helper at `athlete_coach_view.dart:259` (extended with `confirmLabel: 'Compartir'`).
Dialog copy:
- Title: `¿Seguro?`
- Body: `Tu PF va a poder ver todas tus sesiones, volumen y racha. Podés desactivarlo cuando quieras.`
- Cancel button: `Cancelar`
- Confirm button: `Compartir`

If the user cancels the dialog, `setSharedWithTrainer` MUST NOT be called and the toggle
MUST NOT change state.

#### SCENARIO-472: tapping toggle (off → on) shows confirmation dialog

- GIVEN `_LinkStateCard` renders with `link.sharedWithTrainer: false` and `status: active`
- WHEN the athlete taps the toggle
- THEN a confirmation dialog is visible with the body text containing "sesiones, volumen y racha"
- AND `setSharedWithTrainer` has NOT been called yet

---

## REQ-COACH-LINK-010 — Confirming dialog calls repo and invalidates provider

When the athlete confirms the enable dialog, `setSharedWithTrainer(link.id, true)` MUST be called
and `currentAthleteLinkProvider` MUST be invalidated via `ref.invalidate(currentAthleteLinkProvider)`.
No optimistic UI is applied — the toggle state is driven by the reloaded provider value.

#### SCENARIO-473: confirming the dialog calls `setSharedWithTrainer` and invalidates provider

- GIVEN the confirmation dialog is open for enabling sharing
- WHEN the athlete taps "Compartir"
- THEN `setSharedWithTrainer(link.id, true)` is called exactly once
- AND `currentAthleteLinkProvider` is invalidated

---

## REQ-COACH-LINK-011 — Disabling toggle skips dialog and calls repo directly

When the athlete taps the toggle to switch from `true → false` (disable sharing), NO
confirmation dialog MUST be shown. `setSharedWithTrainer(link.id, false)` MUST be called
immediately and `currentAthleteLinkProvider` MUST be invalidated.

#### SCENARIO-474: tapping toggle (on → off) skips dialog and calls repo directly

- GIVEN `_LinkStateCard` renders with `link.sharedWithTrainer: true` and `status: active`
- WHEN the athlete taps the toggle
- THEN no dialog is shown
- AND `setSharedWithTrainer(link.id, false)` is called immediately
- AND `currentAthleteLinkProvider` is invalidated

---

## REQ-COACH-LINK-012 — Firestore rule — athlete can flip `sharedWithTrainer`

The `trainer_links/{linkId}` update rule MUST permit an authenticated user who is the
document's `athleteId` to change the `sharedWithTrainer` field, provided that all of the
following invariants are preserved (trainer-write-protected fields unchanged):
- `trainerId` unchanged
- `athleteId` unchanged
- `requestedAt` unchanged

The exact rule shape from the proposal MUST be implemented verbatim:

```
allow update: if request.auth != null
    && (request.auth.uid == resource.data.trainerId
        || request.auth.uid == resource.data.athleteId)
    && request.resource.data.trainerId == resource.data.trainerId
    && request.resource.data.athleteId == resource.data.athleteId
    && request.resource.data.requestedAt == resource.data.requestedAt
    && (request.resource.data.sharedWithTrainer == resource.data.sharedWithTrainer
        || request.auth.uid == resource.data.athleteId);
```

#### SCENARIO-475: athlete can update `sharedWithTrainer` — permitted

- GIVEN a Firestore emulator with the updated production rules applied
- AND a `trainer_links` document with `trainerId: 'trainer-1'`, `athleteId: 'athlete-1'`
- AND user `athlete-1` is authenticated
- WHEN `athlete-1` updates `sharedWithTrainer` from `false` to `true` (all other fields unchanged)
- THEN the update is permitted

*(Mark `@Skip('requires Firestore emulator')` when emulator is unavailable in CI.)*

---

## REQ-COACH-LINK-013 — Firestore rule — trainer CANNOT flip `sharedWithTrainer`

A request where `request.auth.uid == resource.data.trainerId` AND `sharedWithTrainer` differs
from the existing value MUST be denied. The OR clause in the rule restricts `sharedWithTrainer`
mutation to the athlete only.

#### SCENARIO-476: trainer attempt to flip `sharedWithTrainer` — denied

- GIVEN the same emulator setup as SCENARIO-475
- AND user `trainer-1` is authenticated
- WHEN `trainer-1` updates `sharedWithTrainer` from `false` to `true` (all other fields unchanged)
- THEN the update is denied with PERMISSION_DENIED

*(Mark `@Skip('requires Firestore emulator')` when emulator is unavailable in CI.)*

---

## REQ-COACH-LINK-014 — Firestore rule — non-member CANNOT update the document

A request from an authenticated user who is neither `trainerId` nor `athleteId` of the document
MUST be denied.

#### SCENARIO-477: non-member update attempt — denied

- GIVEN the same emulator setup as SCENARIO-475
- AND user `stranger-uid` is authenticated (neither trainer nor athlete for this link)
- WHEN `stranger-uid` attempts to update any field on the document
- THEN the update is denied with PERMISSION_DENIED

*(Mark `@Skip('requires Firestore emulator')` when emulator is unavailable in CI.)*

---

## Domain Invariants

1. **No `updatedAt`**: `setSharedWithTrainer` MUST NOT write `updatedAt`. This matches the
   convention of all other `TrainerLinkRepository` update methods (`accept`, `decline`, `cancel`,
   `terminate`).

2. **Privacy-restore is low-stakes**: disable (true → false) intentionally skips the confirmation
   dialog. Restoring privacy is less consequential than granting it; the asymmetry is deliberate.

3. **Trainer cannot see the toggle**: `_LinkStateCard` is private to `athlete_coach_view.dart`.
   `trainer_coach_view.dart` does NOT render it. No trainer-facing visibility toggle is in scope.

4. **Backfill script is idempotent**: `scripts/backfill_trainer_links_shared.js` MUST use batched
   writes and check for key absence before writing, so re-runs are safe.

5. **Etapa 6 gate**: `sharedWithTrainer` is a privacy gate only. Etapa 6 will add the query filter
   on `sessions/{athleteId}/*`. This change MUST NOT add any Etapa 6 behavior.

---

## Out of Scope (deferred)

| Deferred item | Target |
|---|---|
| Etapa 6 PF read gate on `sessions/{athleteId}/*` | Etapa 6 |
| Trainer-side UI indicator that history is shared | Future UX iteration |
| Granular sharing (date ranges, per-routine) | Out of MVP |
| Optimistic UI on toggle (toggle flips instantly before reload) | Out of MVP |
| Push / in-app notification on share change | Fase 6 notifications |

---

*Generated by sdd-spec — 2026-05-22*
