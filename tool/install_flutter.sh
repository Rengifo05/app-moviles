#!/usr/bin/env bash
# Instala la versión fijada de Flutter (Linux x64) verificando su SHA-256.
# Idempotente: si la versión correcta ya está instalada, no hace nada.
# Uso: tool/install_flutter.sh [directorio_destino]   (por defecto /opt/flutter)
set -euo pipefail

FLUTTER_VERSION="3.47.7"
FLUTTER_SHA256="af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230"
ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}"

DEST="${1:-/opt/flutter}"
PARENT="$(dirname "$DEST")"

installed_version() {
  if [[ -x "$DEST/bin/flutter" && -f "$DEST/version" ]]; then
    cat "$DEST/version"
  elif [[ -x "$DEST/bin/flutter" ]]; then
    "$DEST/bin/flutter" --version --machine 2>/dev/null |
      sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p'
  fi
}

if [[ "$(installed_version)" == "$FLUTTER_VERSION" ]]; then
  echo "Flutter $FLUTTER_VERSION ya está instalado en $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Descargando Flutter $FLUTTER_VERSION…"
curl --fail --silent --show-error --location -o "$WORK/$ARCHIVE" "$URL"
echo "$FLUTTER_SHA256  $WORK/$ARCHIVE" | sha256sum --check --status ||
  { echo "ERROR: el SHA-256 del archivo no coincide" >&2; exit 1; }

mkdir -p "$PARENT"
rm -rf "$DEST"
tar -xJf "$WORK/$ARCHIVE" -C "$WORK"
mv "$WORK/flutter" "$DEST"
git config --global --add safe.directory "$DEST" || true

"$DEST/bin/flutter" --disable-analytics >/dev/null 2>&1 || true
"$DEST/bin/flutter" config --no-analytics --no-cli-animations >/dev/null 2>&1 || true
"$DEST/bin/flutter" --version
