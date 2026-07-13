#!/usr/bin/env bash
#
# Corre la app inyectando la key local de Google Places.
#
# La feature de gimnasios (buscar gym / gyms cercanos) usa Google Places, que
# necesita PLACES_CLIENT_KEY en tiempo de build (`--dart-define`). La key vive
# en scripts/places.local.json (GITIGNOREADO — nunca se commitea). Creala una
# sola vez:
#
#   cp scripts/places.local.example.json scripts/places.local.json
#   # y pegá tu key (Google Cloud Console → APIs & Services → Credentials)
#
# Uso: ./scripts/run.sh [args de flutter run]
#   ./scripts/run.sh                 # simulador/device por default
#   ./scripts/run.sh --release       # release por cable
#   ./scripts/run.sh -d <device-id>
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES="$ROOT/scripts/places.local.json"

if [[ -f "$DEFINES" ]]; then
  exec flutter run --dart-define-from-file="$DEFINES" "$@"
fi

echo "⚠️  Falta scripts/places.local.json — corro SIN PLACES_CLIENT_KEY."
echo "    Los gyms cercanos van a fallar; el resto de la app anda igual."
echo "    Para activarlos:"
echo "      cp scripts/places.local.example.json scripts/places.local.json"
echo "      # y pegá tu key de Google Places en ese archivo"
exec flutter run "$@"
