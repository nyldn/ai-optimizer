#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="${AI_ENV_OPTIMIZER_DIST_DIR:-${AI_OPTIMIZER_DIST_DIR:-$ROOT_DIR/dist}}"
ARCHIVE="ai-env-optimizer-${VERSION}.tar.gz"

[ -f "$DIST_DIR/$ARCHIVE" ] || "$ROOT_DIR/scripts/build-release.sh" >/dev/null

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-env-optimizer-roundtrip.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

INSTALL_ROOT="$TEST_ROOT/share/ai-env-optimizer"
BIN_DIR="$TEST_ROOT/bin"
DATA_DIR="$TEST_ROOT/data"
AGENTS_DIR="$TEST_ROOT/LaunchAgents"

OUTPUT="$(env AI_ENV_OPTIMIZER_RELEASE_BASE="file://$DIST_DIR" AI_ENV_OPTIMIZER_PREFIX="$INSTALL_ROOT" AI_ENV_OPTIMIZER_BIN_DIR="$BIN_DIR" PATH="/usr/bin:/bin" /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION")"

echo "$OUTPUT" | grep -q "Installed AI Environment Optimizer $VERSION"
echo "$OUTPUT" | grep -q "Add AI Environment Optimizer to zsh PATH"
[ -L "$BIN_DIR/ai-env-optimizer" ]
[ -L "$BIN_DIR/ai-optimizer" ]
[ "$("$BIN_DIR/ai-env-optimizer" version)" = "ai-env-optimizer $VERSION" ]
[ "$("$BIN_DIR/ai-optimizer" version)" = "ai-env-optimizer $VERSION" ]

mkdir -p "$TEST_ROOT/workspaces"
env AI_ENV_OPTIMIZER_DATA_DIR="$DATA_DIR" AI_ENV_OPTIMIZER_LAUNCH_AGENTS_DIR="$AGENTS_DIR" "$BIN_DIR/ai-env-optimizer" setup --workspace-root "$TEST_ROOT/workspaces" >/dev/null

[ -f "$DATA_DIR/state-manifest.json" ]

env AI_ENV_OPTIMIZER_PREFIX="$INSTALL_ROOT" AI_ENV_OPTIMIZER_BIN_DIR="$BIN_DIR" AI_ENV_OPTIMIZER_DATA_DIR="$DATA_DIR" AI_ENV_OPTIMIZER_LAUNCH_AGENTS_DIR="$AGENTS_DIR" /bin/bash "$INSTALL_ROOT/scripts/uninstall.sh" --force >/dev/null

[ ! -e "$INSTALL_ROOT" ]
[ ! -e "$BIN_DIR/ai-env-optimizer" ]
[ ! -e "$BIN_DIR/ai-optimizer" ]
[ ! -e "$DATA_DIR" ]

TAMPERED_DIR="$TEST_ROOT/tampered"
mkdir -p "$TAMPERED_DIR"
cp "$DIST_DIR/$ARCHIVE" "$DIST_DIR/$ARCHIVE.sha256" "$TAMPERED_DIR/"
printf 'tampered' >> "$TAMPERED_DIR/$ARCHIVE"

if env AI_ENV_OPTIMIZER_RELEASE_BASE="file://$TAMPERED_DIR" AI_ENV_OPTIMIZER_PREFIX="$TEST_ROOT/tampered-install" AI_ENV_OPTIMIZER_BIN_DIR="$TEST_ROOT/tampered-bin" /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION" >/dev/null 2>&1; then
  echo "tampered archive was accepted" >&2
  exit 1
fi

[ ! -e "$TEST_ROOT/tampered-install" ]

UNOWNED_ROOT="$TEST_ROOT/unowned-install"
mkdir -p "$UNOWNED_ROOT"
printf 'owner=someone-else\n' > "$UNOWNED_ROOT/.ai-env-optimizer-install"
printf 'preserve\n' > "$UNOWNED_ROOT/sentinel"
if env AI_ENV_OPTIMIZER_RELEASE_BASE="file://$DIST_DIR" AI_ENV_OPTIMIZER_PREFIX="$UNOWNED_ROOT" AI_ENV_OPTIMIZER_BIN_DIR="$TEST_ROOT/unowned-bin" /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION" >/dev/null 2>&1; then
  echo "unowned install root was accepted" >&2
  exit 1
fi
[ "$(cat "$UNOWNED_ROOT/sentinel")" = "preserve" ]

LEGACY_HOME="$TEST_ROOT/legacy-home"
LEGACY_ROOT="$LEGACY_HOME/.local/share/ai-optimizer"
LEGACY_BIN_DIR="$LEGACY_HOME/.local/bin"
mkdir -p "$LEGACY_ROOT/bin" "$LEGACY_BIN_DIR"
printf 'owner=ai-optimizer\nversion=0.1.8\n' > "$LEGACY_ROOT/.ai-optimizer-install"
printf '#!/bin/sh\nexit 0\n' > "$LEGACY_ROOT/bin/ai-optimizer"
chmod +x "$LEGACY_ROOT/bin/ai-optimizer"
ln -s "$LEGACY_ROOT/bin/ai-optimizer" "$LEGACY_BIN_DIR/ai-optimizer"

env HOME="$LEGACY_HOME" AI_ENV_OPTIMIZER_RELEASE_BASE="file://$DIST_DIR" PATH="/usr/bin:/bin" /bin/bash "$ROOT_DIR/install.sh" --version "$VERSION" >/dev/null

[ ! -e "$LEGACY_HOME/.local/share/ai-env-optimizer" ]
[ -f "$LEGACY_ROOT/.ai-env-optimizer-install" ]
[ -L "$LEGACY_BIN_DIR/ai-env-optimizer" ]
[ "$("$LEGACY_BIN_DIR/ai-env-optimizer" version)" = "ai-env-optimizer $VERSION" ]
[ "$("$LEGACY_BIN_DIR/ai-optimizer" version)" = "ai-env-optimizer $VERSION" ]

env HOME="$LEGACY_HOME" AI_ENV_OPTIMIZER_DATA_DIR="$TEST_ROOT/legacy-data" AI_ENV_OPTIMIZER_LAUNCH_AGENTS_DIR="$TEST_ROOT/legacy-agents" /bin/bash "$LEGACY_ROOT/scripts/uninstall.sh" --force >/dev/null

[ ! -e "$LEGACY_ROOT" ]
[ ! -e "$LEGACY_BIN_DIR/ai-env-optimizer" ]
[ ! -e "$LEGACY_BIN_DIR/ai-optimizer" ]
echo "install round trip passed"
