# Legal Consent Versioning Specification

## Purpose

Gives versioned evidence of which legal text each user accepted, plus a
purpose-specific consent — separate from version acceptance — for publishing
a trainer's location. The location consent is triggered at promotion to
`trainer`, not at signup, tracks separately whether it was ever *asked*
versus *granted* (to avoid re-prompting), and is revocable without leaving
the profile in an invalid or silently-invisible state.

## Requirements

### Requirement: Independent Monotonic Version Constants

`legal_content.dart` MUST define `kTermsVersion` and `kPrivacyVersion` as
two independent, monotonically increasing integers, alongside the existing
`kTermsLastUpdated` / `kPrivacyLastUpdated` date constants. Bumping one
constant MUST NOT require changing the other.

#### Scenario: Privacy version bump does not affect Terms version

- GIVEN `kTermsVersion == 1` and `kPrivacyVersion == 1`
- WHEN `kPrivacyVersion` is bumped to `2` for a Privacy Policy edit
- THEN `kTermsVersion` remains `1`

### Requirement: Per-Document Accepted-Version Fields on UserProfile

`UserProfile` MUST expose nullable ints `acceptedTermsVersion` and
`acceptedPrivacyVersion`, alongside the existing `termsAcceptedAt`. `null` in
either field MUST mean "legacy account, no versioned evidence" — it MUST NOT
be treated as equivalent to having accepted version `0` or the current
version.

#### Scenario: Legacy account has no versioned evidence

- GIVEN a `UserProfile` created before this change shipped
- WHEN `acceptedTermsVersion` and `acceptedPrivacyVersion` are read
- THEN both are `null`, and no code path treats `null` as "accepted current"

### Requirement: Consent Fields Are Evidence, Not a Firestore-Rules-Enforced Boundary

`acceptedTermsVersion`, `acceptedPrivacyVersion`, `trainerLocationConsentAt`,
and `trainerLocationConsentPromptedAt` MUST be treated as evidence of what
the app showed and the user acted on, NOT as a security boundary.
`firestore.rules` MUST NOT gain a new allowlist restricting these fields as
part of this change — they stay writable by the document owner like any
other unpinned field on `users/{uid}`, the same posture `termsAcceptedAt`
already has.

#### Scenario: Owner can write these fields directly, same as any other unpinned field

- GIVEN an authenticated user with uid `U`
- WHEN they write `users/U` with an arbitrary `trainerLocationConsentAt` via
  a direct Firestore write (bypassing the app UI)
- THEN the write is NOT rejected by `firestore.rules` for that reason —
  same posture `termsAcceptedAt` already has today

### Requirement: Version Stamping at Every Acceptance Path

Every code path that stamps `termsAcceptedAt` MUST stamp
`acceptedTermsVersion` and `acceptedPrivacyVersion` with the current
`kTermsVersion` / `kPrivacyVersion` in the SAME write. Today that is exactly
three paths: email signup (`auth_service.dart`), OAuth `ProfileSetup`
submit, and `UserRepository.getOrCreate`. No path may write
`termsAcceptedAt` without also writing both version fields.

#### Scenario: Version stamping applies to all three acceptance paths

- GIVEN a `termsAcceptedAt` stamp is about to be written by email signup
  (`auth_service.dart`), OAuth `ProfileSetup` submit, or
  `UserRepository.getOrCreate`
- WHEN that write happens
- THEN `acceptedTermsVersion == kTermsVersion` and
  `acceptedPrivacyVersion == kPrivacyVersion` are written in the same
  operation

### Requirement: Non-Blocking Legacy Notice for Athletes

`legal_content.dart` MUST define `kPrivacyV1PublishedAt`, a machine-comparable
date constant marking when the current Privacy Policy text took effect
(distinct from `kPrivacyLastUpdated`, a display-only string that is never
parsed). Authenticated users with `role == 'athlete'`, a non-null
`termsAcceptedAt`, and `termsAcceptedAt.isBefore(kPrivacyV1PublishedAt)` MUST
see an informational notice about the updated Privacy Policy. The notice
MUST NOT block navigation or any in-app action, and MUST NOT be shown to an
athlete whose `termsAcceptedAt` is not before `kPrivacyV1PublishedAt`.

#### Scenario: Legacy athlete sees a non-blocking notice

- GIVEN an athlete with `termsAcceptedAt` before `kPrivacyV1PublishedAt`
- WHEN they enter the app
- THEN an informational notice about the Privacy Policy update is shown
- AND every other in-app action remains available while it is visible

#### Scenario: Athlete who accepted on or after the current text does not see the notice

- GIVEN an athlete with `termsAcceptedAt` on or after `kPrivacyV1PublishedAt`
- WHEN they enter the app
- THEN the notice is not shown

### Requirement: Trainer Location Consent Tracks "Granted" Separately From "Asked", and Independently of the Version Gate

`trainerLocationConsentAt` (nullable `DateTime`) MUST record consent for the
specific purpose of publishing the trainer's location — separate from
Terms/Privacy version acceptance. `trainerLocationConsentPromptedAt`
(nullable `DateTime`) MUST record only that the prompt was shown, regardless
of the outcome — it answers "did we ask?", not "did they agree?". Neither
field MUST be stamped automatically by promotion to `trainer`, by signup, or
by any version-acceptance write. A comparison of `acceptedPrivacyVersion`
against `kPrivacyVersion` MUST NOT be used as a substitute gate for location
consent: it does not cover a user who accepted the current Privacy version
as an athlete and is promoted afterward. If `trainerLocationConsentAt` is
non-null while `trainerLocationConsentPromptedAt` is null (not reachable
through the normal grant/revoke/dismiss paths, but not excluded by the
schema), the system MUST treat that state as granted.

#### Scenario: Promotion does not grant or ask for location consent

- GIVEN an athlete is promoted to `trainer` via `promote_user_to_trainer.js`
- WHEN the promotion completes
- THEN `trainerLocationConsentAt` and `trainerLocationConsentPromptedAt` are
  unchanged by the promotion itself (`null` for a first-time trainer)

#### Scenario: A version-current athlete promoted later still needs this specific consent

- GIVEN an athlete signs up today with `acceptedPrivacyVersion` equal to the
  current `kPrivacyVersion`
- WHEN that same user is promoted to `trainer` tomorrow and their profile
  has at least one published `trainerLocation`
- THEN the system still requires `trainerLocationConsentAt` to be set before
  treating the location publication as consented
- AND a gate based only on `acceptedPrivacyVersion < kPrivacyVersion` would
  NOT have caught this case

#### Scenario: consentAt set with promptedAt null is treated as granted

- GIVEN a `UserProfile` with `trainerLocationConsentAt` non-null and
  `trainerLocationConsentPromptedAt` null
- WHEN any gate reads this state
- THEN it is treated as consent granted (the prompt MUST NOT be shown)

### Requirement: Location Publication to the Public Mirror Requires Effective Consent at Write Time

A save whose partial contains any location key (`trainerLocations`,
`trainerGeohashes`, `trainerLatitude`, `trainerLongitude`, `trainerGeohash`)
MUST NOT dual-write those keys to `trainerPublicProfiles/{uid}` unless
`trainerLocationConsentAt` is non-null at write time. Non-location keys in
the same partial (e.g. `trainerBio`, `trainerMonthlyRate`,
`trainerOffersOnline`) MUST still be written normally — `trainerOffersOnline`
is not a location key and is unaffected by this gate.

#### Scenario: Location keys are withheld from the public mirror when consent is absent

- GIVEN a trainer with `trainerLocationConsentAt == null`
- WHEN `UserRepository.update()` is called with a partial containing both
  `trainerLocations` and unrelated fields (e.g. `trainerBio`)
- THEN the public-mirror write does NOT include the location keys
- AND the unrelated fields ARE written to the public mirror normally

#### Scenario: Location keys are written once consent is on record

- GIVEN a trainer with `trainerLocationConsentAt` non-null
- WHEN `UserRepository.update()` is called with a partial containing
  `trainerLocations`
- THEN the public-mirror write includes the location keys

### Requirement: Trainer Consent Prompt Blocks Accidental Dismissal; Three Deliberate Exits, None Re-Prompt

A user with `role == 'trainer'`, `trainerLocations` non-empty,
`trainerLocationConsentAt == null`, and `trainerLocationConsentPromptedAt ==
null` MUST be presented with a consent prompt describing the
location-publication purpose. `trainerLocations.isNotEmpty` is a relevance
filter (nothing to consent to without it) — it MUST NOT be used as the
signal for "already resolved"; only `trainerLocationConsentPromptedAt` MUST
gate re-display. The prompt MUST NOT be dismissible by an accidental tap
outside its bounds, but MUST support a deliberate close (drag or back). It
offers exactly three exits, and ALL THREE MUST stamp
`trainerLocationConsentPromptedAt`:

| Exit | Effect |
|---|---|
| Accept | `grantTrainerLocationConsent` |
| Revoke publication | `revokeTrainerLocationConsent` |
| Deliberate close (drag/back) | stamps `promptedAt` only — no grant, no revoke |

Athletes MUST NOT see this prompt under any condition.

#### Scenario: Trainer with published location and no prior prompt sees it, blocked from accidental dismissal

- GIVEN a `trainer` with `trainerLocations` non-empty, `consentAt == null`,
  `promptedAt == null`
- WHEN they enter the app
- THEN the prompt is shown
- AND tapping outside its bounds does NOT dismiss it

#### Scenario: Accepting stamps both timestamps and the prompt does not return

- GIVEN the prompt is shown to a trainer
- WHEN the trainer chooses accept
- THEN `trainerLocationConsentAt` and `trainerLocationConsentPromptedAt` are
  both set
- AND the prompt does not appear on subsequent app entries

#### Scenario: Closing without deciding stamps only promptedAt and does not reappear

- GIVEN the prompt is shown to a trainer
- WHEN the trainer closes it via drag or back, without choosing accept or
  revoke
- THEN `trainerLocationConsentPromptedAt` is set and
  `trainerLocationConsentAt` remains `null`
- AND the prompt does not appear on subsequent app entries
- AND the trainer's published location is unchanged (status quo — not
  revoked by closing without deciding)

#### Scenario: A trainer who already revoked does not see the prompt again despite trainerLocations still being non-empty

- GIVEN a trainer previously revoked publication, so `promptedAt` is set and
  `trainerLocations` in `users/{uid}` is still non-empty (revocation does
  not clear it — see the grant/revoke requirement below)
- WHEN they enter the app
- THEN the prompt is NOT shown (gated on `promptedAt`, not on
  `trainerLocations.isNotEmpty`)

#### Scenario: Trainer with no published location is not prompted

- GIVEN a `trainer` with `trainerLocations` empty and
  `trainerOffersOnline == true`
- WHEN they enter the app
- THEN the prompt is NOT shown — there is nothing location-specific to
  consent to

#### Scenario: Athlete is never shown the trainer prompt

- GIVEN a user with `role == 'athlete'`
- WHEN they enter the app
- THEN the trainer location-consent prompt is never shown, regardless of
  any other field value

### Requirement: Grant and Revoke Are Explicit Operations With Deterministic, Asymmetric Mirror Effects

Consent state MUST change only via two explicit repository methods —
`grantTrainerLocationConsent(uid)` and `revokeTrainerLocationConsent(uid)` —
never inferred from a generic partial `update()` call.

`grantTrainerLocationConsent` MUST, in the same operation: stamp
`trainerLocationConsentAt` and `trainerLocationConsentPromptedAt` on
`users/{uid}`, AND re-write the trainer's currently-stored locations to
`trainerPublicProfiles/{uid}`. A consent-only partial carries no location
keys, so without this explicit re-mirror the trainer would end up consented
but invisible.

`revokeTrainerLocationConsent` MUST write to `users/{uid}` only
`{trainerLocationConsentAt: null, trainerLocationConsentPromptedAt: <now>}`
— zero location keys, so `trainerLocations` and all other private location
data on `users/{uid}` remain untouched, and
`_assertTrainerLocationStateIsValid` never sees a state it could reject. On
`trainerPublicProfiles/{uid}` it MUST clear the location keys
(`trainerLocations`, `trainerGeohashes`, `trainerLatitude`,
`trainerLongitude`, `trainerGeohash`) while leaving `trainerOffersOnline`
untouched. If the trainer's `trainerOffersOnline` is `false` at the time of
revocation, the trainer becoming unreachable through nearby-location search
is an accepted consequence of the trainer's own choice, not a defect — the
system MUST NOT compensate by forcing `trainerOffersOnline` to `true`.

#### Scenario: Granting re-mirrors already-stored locations, not just the timestamp

- GIVEN a trainer with `trainerLocations` already stored on `users/{uid}`
  and `trainerLocationConsentAt == null`
- WHEN `grantTrainerLocationConsent(uid)` is called
- THEN `trainerPublicProfiles/{uid}` is written with those same locations
- AND the trainer is not left "consented but invisible"

#### Scenario: Revoking never throws and never touches users/ location data

- GIVEN a trainer with a published `trainerLocation`
- WHEN `revokeTrainerLocationConsent(uid)` is called
- THEN no exception is raised
- AND `users/{uid}.trainerLocations` and `users/{uid}.trainerOffersOnline`
  are unchanged from their values before the call

#### Scenario: Revoking clears only the public mirror's location keys

- GIVEN a trainer revokes as above
- WHEN the write completes
- THEN `trainerPublicProfiles/{uid}` no longer exposes any location key
- AND `trainerPublicProfiles/{uid}.trainerOffersOnline` is unchanged

#### Scenario: A location-only trainer who revokes and doesn't offer online loses nearby-search visibility, by design

- GIVEN a trainer with `trainerOffersOnline == false` who revokes their
  only published location
- WHEN the revocation completes
- THEN the trainer no longer appears in nearby-location trainer search
- AND this is the intended outcome of the trainer's choice, not a bug to be
  silently worked around

## Out of Scope (this change)

- Backfilling version/consent fields on existing accounts.
- Immutable append-only consent audit log (`consents/` collection with
  IP/user-agent).
- Push notification of policy changes.
- Re-consent flow for Terms (only the Privacy Policy text changed).
- i18n / translation of legal text.
- Hardening `trainerPublicProfiles` Firestore rules or changing discovery
  visibility — location publication stays intentionally public; this change
  is about consenting to that, not restricting it.
- Rewriting Privacy Policy §10 to stop promising a notification channel
  that doesn't exist.
- Hardening `_assertTrainerLocationStateIsValid` against its known
  partial-key gap — real gap, deliberately left unexercised by this
  change's write paths rather than fixed (see the `trainer-profile-onboarding`
  delta).

## Product / Legal Decisions (not specified here)

- Exact copy of the trainer sheet and the athlete notice.
- Whether "revoke publication" should also unlink the trainer from current
  athletes (engineering lean: no — the link doesn't depend on location).
- Whether closing the prompt without deciding should count as a refusal
  requiring auto-unpublish under a strict reading of affirmative-consent
  law (engineering default: no — status quo stays, evidence that the
  trainer was informed is preserved via `promptedAt`).
