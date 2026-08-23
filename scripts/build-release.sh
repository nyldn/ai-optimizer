#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="${AI_ENV_OPTIMIZER_DIST_DIR:-${AI_OPTIMIZER_DIST_DIR:-$ROOT_DIR/dist}}"
ARCHIVE="ai-env-optimizer-${VERSION}.tar.gz"

case "$VERSION" in
  ''|*[!0-9.]*)
    echo "VERSION must contain only digits and dots" >&2
    exit 1
    ;;
esac

if ! git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "A committed Git HEAD is required for a reproducible release" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ARCHIVE" "$DIST_DIR/$ARCHIVE.sha256"
rm -f "$DIST_DIR/install.sh" "$DIST_DIR/install.sh.sha256"

git -C "$ROOT_DIR" archive --format=tar --prefix="ai-env-optimizer-${VERSION}/" HEAD | gzip -n -9 > "$DIST_DIR/$ARCHIVE"

cp "$ROOT_DIR/install.sh" "$DIST_DIR/install.sh"
(
  cd "$DIST_DIR"
  shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
  shasum -a 256 install.sh > install.sh.sha256
)

echo "$DIST_DIR/$ARCHIVE"
