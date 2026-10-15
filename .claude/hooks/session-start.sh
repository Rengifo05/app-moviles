#!/bin/bash
# SessionStart hook (solo sesiones remotas de Claude Code): prepara Flutter y
# las dependencias para que `tool/check.sh` (format, analyze, test) funcione.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_HOME="/opt/flutter"
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Instalación verificada por SHA-256 e idempotente.
tool/install_flutter.sh "$FLUTTER_HOME" >&2

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"

# Dependencias de la app (también genera la localización en lib/l10n/gen).
flutter pub get >&2

# Dependencias del backend, cuando exista functions/package.json.
if [ -f functions/package.json ]; then
  (cd functions && npm install --no-fund --no-audit >&2)
fi
