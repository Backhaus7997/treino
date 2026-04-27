#!/usr/bin/env bash
# Bootstrap script para nuevos devs de TREINO.
# Idempotente: podés re-correrlo cuantas veces quieras.
# Funciona en macOS (Apple Silicon e Intel). Linux: adaptar manualmente.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red() { printf "\033[31m%s\033[0m\n" "$*" >&2; }

bold "TREINO bootstrap — instalando toolchain y dependencias..."

# 1. Verificar Homebrew
if ! command -v brew >/dev/null 2>&1; then
  red "Homebrew no está instalado. Instalalo desde https://brew.sh y volvé a correr este script."
  exit 1
fi
green "✓ Homebrew detectado: $(brew --version | head -1)"

# 2. Instalar Flutter
if command -v flutter >/dev/null 2>&1; then
  green "✓ Flutter detectado: $(flutter --version | head -1)"
else
  yellow "→ Instalando Flutter via brew..."
  brew install --cask flutter
  green "✓ Flutter instalado"
fi

# 3. Instalar gentle-ai
if command -v gentle-ai >/dev/null 2>&1; then
  green "✓ gentle-ai detectado: $(gentle-ai version 2>/dev/null || echo 'instalado')"
else
  yellow "→ Tapeando Gentleman-Programming/homebrew-tap..."
  brew tap Gentleman-Programming/homebrew-tap
  yellow "→ Instalando gentle-ai..."
  brew install gentle-ai
  green "✓ gentle-ai instalado"
fi

# 4. Instalar engram
if command -v engram >/dev/null 2>&1; then
  green "✓ engram detectado: $(engram --version 2>/dev/null | head -1)"
else
  yellow "→ Instalando engram..."
  brew install gentleman-programming/tap/engram
  green "✓ engram instalado"
fi

# 5. Wire up gentle-ai con los agentes que tengas en la máquina
yellow "→ Corriendo 'gentle-ai install' (registra los subagentes en Claude Code y otros)..."
gentle-ai install || yellow "  (advertencias OK; verificá la salida arriba si algo no validó)"
green "✓ gentle-ai conectado a tus agentes"

# 6. Resolver dependencias del proyecto
yellow "→ Corriendo 'flutter pub get'..."
flutter pub get
green "✓ Dependencias del proyecto resueltas"

# 7. Análisis estático
yellow "→ Corriendo 'flutter analyze'..."
if flutter analyze; then
  green "✓ flutter analyze: 0 issues"
else
  red "✗ flutter analyze reportó issues. Revisalos antes de empezar."
  exit 1
fi

# 8. Doctor (informativo)
yellow "→ Corriendo 'flutter doctor' (informativo, no bloquea)..."
flutter doctor || true

bold ""
bold "✅ Bootstrap completo."
bold ""
echo "Próximos pasos:"
echo "  • Leé AGENTS.md y CONTRIBUTING.md."
echo "  • Abrí el repo en VS Code (con la extensión de Claude Code) o Claude Code Desktop."
echo "  • Para correr la app:"
echo "      open -a Simulator    # bootea un simulator iOS"
echo "      flutter run"
echo ""
echo "Para empezar un cambio nuevo (Fase 1+):"
echo "  git checkout -b feat/<scope>-<descripción>"
echo "  /sdd-new <change-name>     (dentro de Claude Code)"
echo ""
