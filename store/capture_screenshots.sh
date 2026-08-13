#!/usr/bin/env bash
#
# Regenerate the store screenshots.
#
# Drives the app against the Firebase emulator with the seeded demo account, so
# no real person's data can reach a public store listing. See store/README.md.
#
#   bash store/capture_screenshots.sh              # 6.9" + the Play phone set
#   DEVICE=6.5 bash store/capture_screenshots.sh   # the optional 6.5" set
#
# Assumes the emulator is already running and seeded:
#   bash scripts/emulator.sh
#   cd scripts && npm run seed:emulator

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DEVICE="${DEVICE:-6.9}"

case "$DEVICE" in
  6.9) SIM_NAME="iPhone 16 Pro Max"; DEST="store/ios/screenshots/es/6.9-inch" ;;
  6.5) SIM_NAME="iPhone 14 Plus";    DEST="store/ios/screenshots/es/6.5-inch" ;;
  *) echo "Unknown DEVICE '$DEVICE' (expected 6.9 or 6.5)" >&2; exit 1 ;;
esac

echo "==> Target: $SIM_NAME -> $DEST"

# Seeding against a dead emulator silently produces empty screens, which is
# exactly the failure this script exists to prevent.
if ! curl -sf -o /dev/null http://127.0.0.1:4444/; then
  echo "ERROR: Firebase emulator is not running on port 4444." >&2
  echo "Start it first:  bash scripts/emulator.sh" >&2
  exit 1
fi

# Un emulador VIVO pero VACÍO produce exactamente las mismas pantallas en blanco
# que uno muerto: Insights sale "0 / 5", "No entrenaste este día" y todos los
# músculos en cero. Eso ya pasó una vez y las capturas llegaron a disco sin que
# nada avisara — el chequeo de arriba sólo mira que el proceso responda.
#
# `seed-routine-001` es la rutina que el driver navega en la captura 02, así que
# si falta, la corrida no puede producir nada usable. El header de admin saltea
# las reglas, que es lo correcto para un chequeo de infraestructura.
SEED_DOC="http://127.0.0.1:8080/v1/projects/treino-dev/databases/(default)/documents/routines/seed-routine-001"
if ! curl -sf -H "Authorization: Bearer owner" "$SEED_DOC" | grep -q 'seed-routine-001'; then
  echo "ERROR: el emulador está corriendo pero NO tiene datos sembrados." >&2
  echo "Sembralo primero:  cd scripts && npm run seed:emulator" >&2
  exit 1
fi

SIM_UDID="$(xcrun simctl list devices available \
  | grep -F "$SIM_NAME (" \
  | head -1 \
  | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"

if [ -z "$SIM_UDID" ]; then
  echo "ERROR: simulator '$SIM_NAME' not found." >&2
  echo "Install it from Xcode > Settings > Components." >&2
  exit 1
fi

echo "==> Booting $SIM_NAME ($SIM_UDID)"
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator || true

# `simctl boot` returns immediately; installing before the device finishes
# booting fails with "Unable to lookup in current state: Shutdown".
echo "==> Waiting for the simulator to finish booting"
for _ in $(seq 1 60); do
  if xcrun simctl list devices | grep -F "$SIM_UDID" | grep -q "Booted"; then
    break
  fi
  sleep 2
done

if ! xcrun simctl list devices | grep -F "$SIM_UDID" | grep -q "Booted"; then
  echo "ERROR: simulator did not reach Booted state in time." >&2
  exit 1
fi

# Booted still precedes SpringBoard being ready to accept installs.
xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true

rm -rf build/store-screenshots

echo "==> Running capture driver (this builds the app; first run is slow)"
flutter drive \
  --driver=test_driver/screenshots_driver.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define=USE_EMULATOR=true \
  -d "$SIM_UDID"

shopt -s nullglob
CAPTURED=(build/store-screenshots/*.png)
if [ ${#CAPTURED[@]} -eq 0 ]; then
  echo "ERROR: the driver produced no screenshots." >&2
  exit 1
fi

mkdir -p "$DEST"
cp build/store-screenshots/*.png "$DEST/"
echo "==> Copied ${#CAPTURED[@]} screenshots to $DEST"

# Play accepts the same portrait PNGs, so the 6.9" set doubles as the phone set
# rather than being captured twice.
if [ "$DEVICE" = "6.9" ]; then
  mkdir -p store/android/screenshots/es/phone
  cp build/store-screenshots/*.png store/android/screenshots/es/phone/
  echo "==> Copied to store/android/screenshots/es/phone"
fi

if command -v pngquant >/dev/null; then
  echo "==> Optimizing"
  pngquant --force --ext .png --quality 80-95 --skip-if-larger "$DEST"/*.png || true
  if [ "$DEVICE" = "6.9" ]; then
    pngquant --force --ext .png --quality 80-95 --skip-if-larger \
      store/android/screenshots/es/phone/*.png || true
  fi
else
  echo "==> pngquant not installed; skipping optimization (brew install pngquant)"
fi

echo
echo "Done. Now run the pre-publish checklist in store/README.md —"
echo "especially the anti-PII pass. Nothing here verifies what is IN the pixels."
