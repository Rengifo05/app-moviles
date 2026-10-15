#!/usr/bin/env bash
# Puertas de calidad locales: las mismas que ejecuta CI para la app Flutter.
# Uso: tool/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "› flutter pub get"
flutter pub get >/dev/null

echo "› dart format (verificación)"
dart format --output=none --set-exit-if-changed lib test

echo "› flutter analyze"
flutter analyze --fatal-infos

echo "› flutter test"
flutter test
