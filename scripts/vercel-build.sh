#!/usr/bin/env bash
#
# Build del Coach Hub web para Vercel.
#
# Vercel no tiene runtime de Flutter, así que el SDK se instala acá y el
# artefacto final es estático (`build/web`). Es la razón por la que este script
# existe en vez de un `buildCommand` de una línea en vercel.json.
#
# La versión está PINEADA y tiene que coincidir con la de
# `.github/workflows/ci.yml` (subosito/flutter-action, flutter-version). Si CI
# compila con una versión y Vercel con otra, un build puede pasar en CI y
# romperse en producción sin que nada lo avise.
#
# El entrypoint es `lib/main_coach_hub.dart`, NO `lib/main.dart`: la web es el
# dashboard del PF, no la app del atleta.

set -euo pipefail

FLUTTER_VERSION="3.41.9"
FLUTTER_HOME="${HOME}/flutter"

echo "▸ Instalando Flutter ${FLUTTER_VERSION}"

# Clone superficial del tag exacto. Se elige `git clone` sobre el tarball porque
# git es lo único que se puede dar por sentado en el contenedor de build; el
# tarball necesita `xz`, que no siempre está.
if [ ! -d "${FLUTTER_HOME}" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_HOME}"
fi

export PATH="${FLUTTER_HOME}/bin:${PATH}"

# El contenedor de Vercel corre como un usuario distinto al dueño del clone.
git config --global --add safe.directory "${FLUTTER_HOME}"

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true

echo "▸ Resolviendo dependencias"
flutter pub get

echo "▸ Compilando el Coach Hub"
flutter build web \
  --release \
  --target lib/main_coach_hub.dart

echo "▸ Listo — artefacto en build/web"
