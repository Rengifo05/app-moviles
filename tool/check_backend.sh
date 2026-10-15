#!/usr/bin/env bash
# Puertas de calidad del backend: tipos, compilación y pruebas de reglas y
# funciones contra el emulador de Firestore (proyecto demo-nexo, sin
# credenciales). Requiere Node 22 y Java 21.
set -euo pipefail
cd "$(dirname "$0")/../functions"
npm install --no-fund --no-audit >/dev/null
npm run typecheck
npm run build
npm test
