# Delta for Trainer Profile Onboarding

## ADDED Requirements

### Requirement: Revocation Never Exercises the Location-Guard's Known Partial-Key Gap

`UserRepository._assertTrainerLocationStateIsValid` (REQ-TPO-DATA-003) is
**not modified** by this change. Its known gap — the guard only evaluates
the invariant when a partial contains BOTH `trainerLocations` and
`trainerOffersOnline` keys, so a partial supplying only one key bypasses it
— is real and stays unfixed here (closing it requires a `get` on every
`update()` call and is its own refactor with its own blast radius). This
change MUST NOT introduce any write path that exercises that gap:
`revokeTrainerLocationConsent` MUST NOT include `trainerLocations` or
`trainerOffersOnline` in the partial it writes to `users/{uid}`.

#### Scenario: Revocation's partial contains zero location-guard keys

- GIVEN a trainer with a published `trainerLocation` and a stored
  `trainerOffersOnline` value
- WHEN `revokeTrainerLocationConsent(uid)` writes to `users/{uid}`
- THEN the partial contains only `trainerLocationConsentAt` and
  `trainerLocationConsentPromptedAt`
- AND `trainerLocations` and `trainerOffersOnline` on `users/{uid}` are read
  back unchanged, exactly as before the call

### Requirement: profile_edit_trainer_screen Requests Location Consent Before First-Time Publication and Shows True Publication Status

The trainer-consent prompt (see `legal-consent-versioning`) only fires when
`trainerLocations` is already non-empty, so it never fires for a
freshly-promoted trainer with zero locations. `ProfileEditTrainerScreen`
MUST request trainer-location consent inline, before saving, the first time
a trainer with no prior consent submits a form that would introduce a
non-empty `trainerLocations` — otherwise the consent-gated public dual-write
would silently drop the new locations from `trainerPublicProfiles/{uid}`
with no error shown to the trainer (the same silent-failure shape as the
guard's known gap, on a different code path). The screen MUST also display
whether the trainer's location is actually published (has consent) so the
form never lists addresses as live when only the private `users/{uid}`
document has them (e.g. immediately after a revocation).

#### Scenario: First-time location entry with no consent triggers a request instead of a silent drop

- GIVEN a freshly-promoted trainer with `trainerLocations` empty and
  `trainerLocationConsentAt == null`
- WHEN they enter at least one location in `ProfileEditTrainerScreen` and
  attempt to save
- THEN the screen requests location consent before completing the save
- AND the saved locations are NOT silently absent from
  `trainerPublicProfiles/{uid}` with no explanation shown

#### Scenario: Status row reflects unpublished state after revocation

- GIVEN a trainer revoked location publication, so `users/{uid}` still
  lists their locations but `trainerPublicProfiles/{uid}` does not
- WHEN they open `ProfileEditTrainerScreen`
- THEN the screen indicates those locations are NOT currently published,
  rather than presenting them as live
