#!/usr/bin/env bash
#
# Build de iOS para TestFlight / App Store, con la key de Google Places
# inyectada en el binario.
#
# ⚠️  IMPORTANTE — leé esto:
# Para distribución SIEMPRE usá este script (o `flutter build ipa` con el flag
# --dart-define-from-file). NO archives directo desde Xcode (Product → Archive):
# Xcode NO lee los dart-define por defecto, así que subirías un build con
# PLACES_CLIENT_KEY VACÍA → los gyms cercanos rotos en producción, sin ningún
# aviso. Es la trampa silenciosa de este mecanismo.
#
# Uso: ./scripts/build-ios.sh [args extra de `flutter build ipa`]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES="$ROOT/scripts/places.local.json"

# Para un build de DISTRIBUCIÓN, la key NO es opcional: fallamos fuerte en vez
# de shipear un build con los gyms rotos.
if [[ ! -f "$DEFINES" ]]; then
  echo "❌ Falta $DEFINES"
  echo "   Un build de distribución sin la key dejaría los gyms cercanos rotos."
  echo "   Creá el archivo antes de buildear:"
  echo "     cp scripts/places.local.example.json scripts/places.local.json"
  echo "     # y pegá tu PLACES_CLIENT_KEY (Google Cloud Console → Credentials)"
  exit 1
fi

echo "🏗️  flutter build ipa (release) con PLACES_CLIENT_KEY inyectada…"
flutter build ipa --release --dart-define-from-file="$DEFINES" "$@"

echo ""
echo "✅ Listo. El .ipa quedó en:  build/ios/ipa/"
echo ""
echo "   Para subirlo a TestFlight (lo más simple):"
echo "   1. Abrí la app «Transporter» (gratis, Mac App Store)."
echo "   2. Arrastrá el .ipa de build/ios/ipa/ y dale «Deliver»."
echo "   (Alternativa automatizable: fastlane pilot / xcrun altool.)"
