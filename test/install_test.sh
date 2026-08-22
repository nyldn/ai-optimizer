#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="${AI_OPTIMIZER_DIST_DIR:-$ROOT_DIR/dist}"
ARCHIVE="ai-optimizer-${VERSION}.tar.gz"

[ -f "$DIST_DIR/$ARCHIVE" ] || "$ROOT_DIR/scripts/build-release.sh" >/dev/null

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-optimizer-roundtrip.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

INSTALL_ROOT="$TEST_ROOT/share/ai-optimizer"
BIN_DIR="$TEST_ROOT/bin"
DATA_DIR="$TEST_ROOT/data"
AGENTS_DIR="$TEST_ROOT/LaunchAgents"

OUTPUT="$(env AI_OPTIMIZER_RELEASE_BASE="file://$DIST_DIR" AI_OPTIMIZER_PREFIX="$INSTALL_ROOT" AI_OPTIMIZER_BIN_DIR="$BIN_DIR" PATH="/usr/bin:/bin" /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION")"

echo "$OUTPUT" | grep -q "Installed AI Optimizer $VERSION"
echo "$OUTPUT" | grep -q "Add AI Optimizer to zsh PATH"
[ -L "$BIN_DIR/ai-optimizer" ]
[ "$("$BIN_DIR/ai-optimizer" version)" = "ai-optimizer $VERSION" ]

mkdir -p "$TEST_ROOT/workspaces"
env AI_OPTIMIZER_DATA_DIR="$DATA_DIR" AI_OPTIMIZER_LAUNCH_AGENTS_DIR="$AGENTS_DIR" "$BIN_DIR/ai-optimizer" setup --workspace-root "$TEST_ROOT/workspaces" >/dev/null

[ -f "$DATA_DIR/state-manifest.json" ]

env AI_OPTIMIZER_PREFIX="$INSTALL_ROOT" AI_OPTIMIZER_BIN_DIR="$BIN_DIR" AI_OPTIMIZER_DATA_DIR="$DATA_DIR" AI_OPTIMIZER_LAUNCH_AGENTS_DIR="$AGENTS_DIR" /bin/bash "$INSTALL_ROOT/scripts/uninstall.sh" --force >/dev/null

[ ! -e "$INSTALL_ROOT" ]
[ ! -e "$BIN_DIR/ai-optimizer" ]
[ ! -e "$DATA_DIR" ]

TAMPERED_DIR="$TEST_ROOT/tampered"
mkdir -p "$TAMPERED_DIR"
cp "$DIST_DIR/$ARCHIVE" "$DIST_DIR/$ARCHIVE.sha256" "$TAMPERED_DIR/"
printf 'tampered' >> "$TAMPERED_DIR/$ARCHIVE"

if env AI_OPTIMIZER_RELEASE_BASE="file://$TAMPERED_DIR" AI_OPTIMIZER_PREFIX="$TEST_ROOT/tampered-install" AI_OPTIMIZER_BIN_DIR="$TEST_ROOT/tampered-bin" /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION" >/dev/null 2>&1; then
  echo "tampered archive was accepted" >&2
  exit 1
fi

[ ! -e "$TEST_ROOT/tampered-install" ]
echo "install round trip passed"
