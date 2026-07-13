#!/usr/bin/env bash
#
# Build de Android para Play Store (App Bundle), con la key de Google Places
# inyectada en el binario. Mismo criterio que build-ios.sh: la key va sí o sí.
#
# Uso: ./scripts/build-android.sh [args extra de `flutter build appbundle`]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES="$ROOT/scripts/places.local.json"

if [[ ! -f "$DEFINES" ]]; then
  echo "❌ Falta $DEFINES"
  echo "   Un build de distribución sin la key dejaría los gyms cercanos rotos."
  echo "   Creá el archivo antes de buildear:"
  echo "     cp scripts/places.local.example.json scripts/places.local.json"
  echo "     # y pegá tu PLACES_CLIENT_KEY (Google Cloud Console → Credentials)"
  exit 1
fi

echo "🏗️  flutter build appbundle (release) con PLACES_CLIENT_KEY inyectada…"
flutter build appbundle --release --dart-define-from-file="$DEFINES" "$@"

echo ""
echo "✅ Listo. El .aab quedó en:  build/app/outputs/bundle/release/app-release.aab"
echo "   Subilo a Play Console → tu app → Testing/Production → Create release."
