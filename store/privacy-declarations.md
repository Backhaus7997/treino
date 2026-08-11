# Privacy declarations — draft

Proposed answers for **Google Play Data safety** and **App Store privacy
nutrition labels**.

> **This is a draft for the team to review, not a final answer.** Both forms are
> legal declarations. Someone with authority over the product has to confirm
> each line before it is submitted, particularly the health-data and
> data-deletion sections.

Every entry below was derived from what the app actually does — SDKs in
`pubspec.yaml`, permissions in `Info.plist` / `AndroidManifest.xml`, and the
Firestore collections the app reads and writes. If a feature is added or
removed, this file has to be revisited before the next submission.

---

## What the app collects

| Data | Where it comes from | Why | Linked to identity |
|---|---|---|---|
| Name, email, avatar | Signup, profile editing | Account, social features | Yes |
| Gym membership | Profile — gym selection | Gym feed and leaderboards | Yes |
| Approximate location | `ACCESS_FINE_LOCATION` / `NSLocationWhenInUse` | Finding trainers nearby | Yes |
| Photos and video | Camera, photo library | Avatar, feed posts, chat media | Yes |
| Body weight, height, measurements | Profile and measurements screen | Progress tracking, volume math | Yes |
| Workout history (sets, reps, weight) | Session player | The core product | Yes |
| Messages | Coach chat | Athlete↔trainer communication | Yes |
| Crash logs and diagnostics | Firebase Crashlytics | Stability | Yes |
| Usage analytics | Firebase Analytics | Product decisions | Yes |
| Push token | Firebase Messaging | Notifications | Yes |

Third-party SDKs in use: Firebase (Auth, Firestore, Storage, Crashlytics,
Analytics, Messaging, App Check), Google Sign-In, Google Fonts.

---

## Two calls the team must make

### 1. Body measurements are health data

Weight, height and body measurements are collected and stored. In both stores
this falls under health/fitness data, which carries stricter handling rules.

**Recommendation: declare it.** Under-declaring health data is the kind of
finding that gets an app pulled, and the data genuinely is collected.

If per-exercise discomfort reporting ships (tracked separately), that is also
health data and must be added here before the next submission.

### 2. Location is used for discovery, but stored as geohash

The app requests precise location (`ACCESS_FINE_LOCATION`) but stores a
truncated geohash for proximity queries, not exact coordinates.

Both stores ask about the location you **collect**, not only what you retain.
The permission requested is precise, so the honest answer is precise location,
with the geohash storage noted as a retention detail.

**Confirm with whoever owns the privacy policy** that the policy text matches
this reading.

---

## Google Play — Data safety

**Does your app collect or share any of the required user data types?** Yes
**Is all user data encrypted in transit?** Yes (Firebase, TLS)
**Do you provide a way for users to request data deletion?** Yes — in-app
account deletion exists. ⚠️ Confirm the deletion flow removes feed posts rather
than anonymizing them; there is a known follow-up on that behaviour.

| Category | Type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|---|
| Personal info | Name | Yes | No | Required | Account, social |
| Personal info | Email address | Yes | No | Required | Account |
| Personal info | User IDs | Yes | No | Required | Account |
| Photos and videos | Photos | Yes | No | Optional | Avatar, posts, chat |
| Photos and videos | Videos | Yes | No | Optional | Chat media |
| Location | Approximate location | Yes | No | Optional | Trainer discovery |
| Location | Precise location | Yes | No | Optional | Trainer discovery |
| Health and fitness | Health info | Yes | No | Optional | Body measurements |
| Health and fitness | Fitness info | Yes | No | Required | Workout history |
| Messages | Other in-app messages | Yes | No | Optional | Coach chat |
| App activity | App interactions | Yes | No | Required | Analytics |
| App info and performance | Crash logs | Yes | No | Required | Stability |
| App info and performance | Diagnostics | Yes | No | Required | Stability |

"Optional" means the user can use the app without providing it — location can be
denied, measurements left empty, avatar not uploaded.

Nothing is shared with third parties for advertising. Firebase is a processor,
not a recipient in the "shared" sense.

---

## App Store — privacy nutrition labels

### Data used to track you
**None.** No advertising SDKs, no cross-app tracking, no IDFA.

### Data linked to you

| Category | Types | Purposes |
|---|---|---|
| Contact Info | Name, Email Address | App Functionality |
| Health & Fitness | Fitness, Health | App Functionality |
| User Content | Photos or Videos, Other User Content | App Functionality |
| Identifiers | User ID | App Functionality |
| Location | Coarse Location, Precise Location | App Functionality |
| Usage Data | Product Interaction | Analytics |
| Diagnostics | Crash Data, Performance Data | App Functionality |

### Data not linked to you
None.

---

## Before submitting

- [ ] Product owner has reviewed and approved every line above
- [ ] Privacy Policy URL is live and its text matches these declarations
      (also required by Apple for External Testing)
- [ ] Account deletion behaviour confirmed against what Play expects
- [ ] Health-data declaration confirmed (see call #1)
- [ ] Location declaration confirmed against the privacy policy (see call #2)
- [ ] Re-checked after any feature that adds a new data type

---

## Sources

- `pubspec.yaml` — third-party SDKs
- `ios/Runner/Info.plist` — iOS permission strings
- `android/app/src/main/AndroidManifest.xml` — Android permissions
- Profile, measurements, feed, chat and session features under `lib/features/`
