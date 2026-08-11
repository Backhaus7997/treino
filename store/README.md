# Store assets — App Store & Google Play

Everything this repo needs to publish TREINO: screenshots, graphics and listing
metadata, plus the procedure to regenerate all of it.

The point of this directory is that **nobody ever takes store screenshots from
their own phone again**. Screenshots come from a seeded emulator with a
fictional demo account, so regenerating them is a repeatable command instead of
a favor someone does on a Friday — and so no real person's name, gym or chat can
leak into a public listing.

A store listing is public permanently. Treat everything here as published.

---

## Layout

```
store/
├── README.md                     ← you are here
├── capture_screenshots.sh        ← regenerates every screenshot
├── privacy-declarations.md       ← draft answers for Data safety / privacy labels
├── ios/
│   ├── screenshots/es/{6.9-inch,6.5-inch}/*.png
│   └── metadata/{es,en}/{name,subtitle,description,keywords,release_notes}.txt
└── android/
    ├── screenshots/es/phone/*.png
    ├── graphics/{feature-graphic.png,icon-512.png,generate_*.py}
    └── metadata/{es,en}/{title,short_description,full_description,release_notes}.txt
```

The capture itself lives with the other tests:

```
integration_test/screenshots_test.dart   ← drives the app, takes the shots
test_driver/screenshots_driver.dart      ← host side, writes the PNGs to disk
```

Metadata ships in **Spanish and English**. Screenshots ship in **Spanish only** —
see [Why there are no English screenshots](#why-there-are-no-english-screenshots).

---

## Screenshot set

Five screens, same order in both stores. Ordered by what sells, not by app
navigation — the first two are what a browsing user actually judges.

| # | File | Screen | Route |
|---|---|---|---|
| 1 | `01-session.png` | Live session player | `/workout/session/seed-routine-001/1?week=1` |
| 2 | `02-routine.png` | Routine detail | `/workout/routine/seed-routine-001` |
| 3 | `03-insights.png` | Insights + exercise progression | `/home/insights` |
| 4 | `04-coach.png` | Coach — trainer discovery | `/coach` |
| 5 | `05-feed-rankings.png` | Feed / gym rankings | `/feed?tab=rankings` |

Screens 1 and 3 sit outside the router's ShellRoute, so they render without the
bottom nav bar — that is deliberate, it makes for a cleaner capture.

---

## Regenerating the screenshots

### The short version

```bash
bash scripts/emulator.sh                         # terminal 1 — needs JDK 21+
cd scripts && npm run seed:emulator && cd ..     # terminal 2
bash store/capture_screenshots.sh                # 6.9" + the Play phone set
DEVICE=6.5 bash store/capture_screenshots.sh     # optional second iOS size
```

`capture_screenshots.sh` drives the app through
`integration_test/screenshots_test.dart`, signs in as the seeded demo account,
visits each store screen, writes the PNGs, copies them into place and optimizes
them. It refuses to run if the emulator is down, because capturing against a
dead emulator silently produces empty screens.

**It does not check what is in the pixels.** Run the
[pre-publish checklist](#pre-publish-checklist) afterwards regardless.

The manual procedure below is the fallback for when the driver breaks — for
example after a router change that moves one of the captured routes.

### The manual version

### 0. Prerequisites

- **Java 21+** — firebase-tools 15+ refuses to start on anything older, with
  `Error: firebase-tools no longer supports Java version before 21`.
- **`pngquant`** — `brew install pngquant`
- Firebase CLI, Flutter, Xcode simulators.

Check what you have with `java -version`. If it is older than 21:

```bash
brew install openjdk@21
```

Homebrew installs `openjdk@21` **keg-only**, meaning it is not registered as a
system JVM and `firebase` will not find it on its own — installing alone does
not fix the error. Point `JAVA_HOME` at it in the shell you run the emulator
from:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
```

This is scoped to that shell, so any other project keeps using your default JDK.
If you would rather register it system-wide, `brew info openjdk@21` prints the
`sudo ln -sfn …` command for that.

### 1. Start the emulator

In the shell where you exported `JAVA_HOME`:

```bash
bash scripts/emulator.sh
```

Firestore `8080`, Auth `9099`, Functions `5001`, UI `4444`. Confirm all four are
up at <http://localhost:4444>.

> **Do not use `SKIP_FUNCTIONS=1` for screenshot runs.** The volume and main-lift
> leaderboards are computed by the `ranking-aggregate` Cloud Function. Without
> Functions running, screenshot #5 renders empty leaderboards even though every
> athlete is seeded correctly.

### 2. Seed the data

```bash
cd scripts
npm run seed:emulator:clear   # wipes previous seed data — does NOT re-seed
npm run seed:emulator         # seeds
cd ..
```

Both steps matter. `--clear` only deletes; running it alone leaves you with an
empty emulator. The seed itself is idempotent, so `seed:emulator` on its own is
fine for a fresh emulator — the clear is there for reruns.

For byte-identical data across runs, pin the clock:

```bash
SEED_NOW=2026-06-16T12:00:00Z npm run seed:emulator
```

Worth doing before a release: it keeps relative dates ("hace 3 días") stable, so
regenerated screenshots differ only where the UI actually changed.

### 3. Run the app

```bash
flutter run --dart-define=USE_EMULATOR=true
```

Add `--dart-define=PLACES_CLIENT_KEY=...` only if a capture includes gym search.

Pick the simulator that matches the device size you are capturing (see
[Device sizes](#device-sizes)).

### 4. Log in with the demo account

```
martin@emulator.treino / Emulator1234!
```

**Never a real account.** This is the requirement the whole directory exists for.

This account has the fullest state: 14 sessions of history, an active coach with
an assigned plan, accepted friendships, and gym membership with ranking opt-in.

For coach-side captures: `coach.lautaro@emulator.treino`, same password.

### 5. Capture

Navigate to each route in the table above, then:

```bash
xcrun simctl io booted screenshot store/ios/screenshots/es/6.9-inch/01-session.png
```

Capture through `simctl`, never a manual crop — a hand-cropped PNG is the wrong
pixel dimensions and App Store Connect rejects it.

Let charts and lists finish animating before you capture. The progression chart
draws its line on entry; capturing early gets you a half-drawn graph.

### 6. Optimize

```bash
pngquant --force --ext .png --quality 80-95 --skip-if-larger store/ios/screenshots/es/**/*.png
pngquant --force --ext .png --quality 80-95 --skip-if-larger store/android/screenshots/es/phone/*.png
```

`pngquant` is lossy (it quantizes to a 256-colour palette). That is fine for UI
screenshots and typically cuts them by 60-70%.

**Do not run it on `graphics/icon-512.png`.** Icons need clean flat colour and
an intact alpha channel; use `oxipng -o4 --strip safe` there if you want
lossless compression, or leave it alone — it is one small file.

### 7. Verify before committing

Run the [pre-publish checklist](#pre-publish-checklist).

---

## Device sizes

Verified against Apple and Google documentation on **2026-08-11**. Both change
these regularly — re-check before a submission rather than trusting this table
blindly:

- App Store Connect → your app → the localization's Media Manager.
- Play Console → Store presence → Main store listing → Graphics.

**iOS** (portrait):

| Display | Pixels | Status |
|---|---|---|
| 6.9" | 1320 × 2868 | **Required** |
| 6.5" | 1284 × 2778 | Required *only* if 6.9" is not supplied |
| 6.3" / 6.1" / 5.5" / 4.7" | smaller | Optional — Apple scales down from 6.9" |

Since we ship 6.9", the 6.5" set is strictly optional. It is kept because
down-scaled screenshots soften text, and the extra capture run is cheap.

Limits: 1–10 screenshots per localization, `.png`/`.jpg`, **no alpha channel**.

**Play** (phone):

- Minimum 2 screenshots to publish; 4+ at ≥1080px to qualify for large-format
  promotional placements.
- 320px min / 3840px max per side, and the long side may not exceed twice the
  short side.
- JPEG or 24-bit PNG, **no alpha**.

Screenshots captured from the 6.9" iOS simulator (1320 × 2868) satisfy every
Play phone constraint, so the same PNGs can be reused for both stores.

The folder names here (`6.9-inch`, `6.5-inch`) reflect what Apple accepted when
this directory was created. If Apple's required sizes change, rename the folders
to match and regenerate — do not scale existing PNGs up or down.

Simulators that produce those sizes, verified on this repo:

| Folder | Simulator | Output |
|---|---|---|
| `6.9-inch` | iPhone 16 Pro Max | 1320 × 2868 |
| `6.5-inch` | iPhone 14 Plus | 1284 × 2778 |

Confirm with `xcrun simctl list devices available`. If a device is missing,
install it from Xcode → Settings → Components.

What does *not* change: one source PNG per size, generated from the simulator at
native resolution. Never upscale, never crop by hand.

---

## Graphics (Play)

| Asset | Spec | Source |
|---|---|---|
| `graphics/icon-512.png` | 512×512, **32-bit PNG with alpha**, ≤1024 KB | `generate_play_icon.py` |
| `graphics/feature-graphic.png` | 1024×500, 24-bit PNG **no alpha** | `generate_feature_graphic.py` |

Note the alpha rules are opposite for the two assets — Play requires alpha on
the icon and forbids it on the feature graphic. Verified against Play Console
docs (2026-08).

Generate the Play icon from the same `assets/icon/app_icon.png` that
`flutter_launcher_icons` consumes, so the store icon and the installed app icon
cannot drift:

```bash
/tmp/fg/bin/python store/android/graphics/generate_play_icon.py
```

Do **not** use `sips -z 512 512` for this: it drops the alpha channel and
produces a 24-bit file that Play rejects.

The feature graphic is composed from brand assets by a script, so it can be
regenerated when the logo or palette changes:

```bash
python3 -m venv /tmp/fg && /tmp/fg/bin/pip install Pillow
/tmp/fg/bin/python store/android/graphics/generate_feature_graphic.py
```

It keys the mint monogram out of `assets/icon/app_icon.png` (the source is a
glyph on an opaque black tile — pasting it whole leaves a black square), sets
the wordmark and tagline, and pulls its colours from
`lib/app/theme/app_palette.dart` (`ink` `#0A0A0A`, `mint` `#2CE5A2`).

This is a functional asset built from the design system, **not** a designed
marketing panel. If the team wants something richer — product shot, gradient
treatment, real typography — replace the PNG; the script is a floor, not a
ceiling.

Note the app icon is still listed as pending final design in `docs/roadmap.md`
(Fase 7). If it is replaced, regenerate this file from the new source.

---

## Metadata

Plain `.txt`, one file per field, so the format matches what `fastlane deliver`
and `supply` expect if upload is automated later (a separate issue).

Naming rules from `AGENTS.md` — these are not stylistic preferences:

- **TREINO** is the brand.
- **Coach** is the personal-trainer module.
- **Entreno IA** is the AI feature. Never "Coach IA".

Voice follows `docs/product.md`: rioplatense voseo, short imperative sentences,
no opening `¡` / `¿`, no corporate filler.

### Length limits

| Field | Limit |
|---|---|
| iOS `name` | 30 |
| iOS `subtitle` | 30 |
| iOS `keywords` | 100 (comma-separated, no spaces after commas) |
| iOS `description` | 4000 |
| Play `title` | 30 |
| Play `short_description` | 80 |
| Play `full_description` | 4000 |

Check them before uploading:

```bash
for f in store/*/metadata/*/*.txt; do printf '%4d  %s\n' "$(wc -m < "$f")" "$f"; done
```

### App Store Connect identity

The listing name is **"TREINO Fitness"**, not "TREINO" — the plain name was
already taken. App ID `6781307745`, primary language Spanish (Mexico).
`ios/metadata/es/name.txt` reflects that; do not "fix" it to match the brand.

---

## Why there are no English screenshots

The app cannot render an English UI today.

`lib/app/locale_resolver.dart` returns `Locale('es','AR')` unconditionally and
ignores the device locale. That is deliberate (ADR-I18N-005): `intl_en.arb` is a
codegen scaffold with empty values, so serving English renders blank strings.
The generated `app_l10n_en.dart` exists, but there is no actual translation
behind it.

So there is no flag, no `--dart-define` and no system setting that produces an
English capture. English screenshots are blocked on populating `intl_en.arb` and
restoring locale resolution — separate i18n work, tracked separately.

English **metadata** ships now regardless: listing copy is marketing text and
does not depend on the app's runtime locale.

When English lands, drop PNGs into the existing `screenshots/en/` folders. The
layout already accounts for it — no restructuring needed.

---

## Pre-publish checklist

Run through this every time, not just the first time.

**No personal data**
- [ ] Every screenshot came from `martin@emulator.treino` or another
      `@emulator.treino` account — never a personal or production login.
- [ ] No real person's name appears in any capture.
- [ ] No real gym or commercial brand name appears. The seed uses fictional
      gyms (Iron House, Vector Fit) on purpose — if a real chain shows up,
      something re-seeded from `seed_gyms.js`, which contains real venues.
- [ ] No real chat threads, no real avatars.
- [ ] Status bar shows nothing personal (carrier name, real time is fine).

**Content quality**
- [ ] Progression chart shows **at least 3 data points**. One or two points
      means the account lacked history — reseed and check you logged in as
      `martin@`.
- [ ] Rankings show **at least 3 profiles** in the gym. Empty means Functions
      were not running (`SKIP_FUNCTIONS=1`) — restart the emulator fully.
- [ ] No empty states, no loading spinners, no half-drawn animations.
- [ ] No debug banner.

**Technical**
- [ ] Pixel dimensions match what the store currently requires (6.9" = 1320×2868).
- [ ] Screenshots have **no alpha channel** — both stores reject it.
- [ ] PNGs optimized (step 6).
- [ ] `graphics/feature-graphic.png` is 24-bit, **no alpha**.
- [ ] `graphics/icon-512.png` is 32-bit RGBA, **with alpha** — the opposite rule.

Check all three at once:

```bash
file store/android/graphics/*.png store/ios/screenshots/es/*/*.png
```

`feature-graphic.png` and every screenshot must read `RGB`; `icon-512.png` must
read `RGBA`.

**Scope**
- [ ] `git status` shows no changes under `lib/`. Generating screenshots must
      never require touching production code. If it did, the seed is missing
      something — fix the seed, not the app.

---

## Out of scope here

Tracked separately, deliberately not bundled in:

- Automated upload (`fastlane deliver` / `supply`, release CI).
- `fastlane snapshot` / `screengrab` — the project has no `integration_test/`
  setup yet, which is a prerequisite.
- English screenshots (blocked on i18n, above).
- App icon redesign.
- App preview videos.

For External Testing on TestFlight, Apple additionally requires a **Privacy
Policy URL** and **Beta App Review** (~24h). Neither is an asset in this
directory, but both gate the same release.
