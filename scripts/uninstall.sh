#!/usr/bin/env bash
set -euo pipefail

FORCE=0
KEEP_STATE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --keep-state) KEEP_STATE=1; shift ;;
    -h|--help)
      echo "Usage: uninstall.sh [--force] [--keep-state]"
      exit 0
      ;;
    *)
      echo "Usage: uninstall.sh [--force] [--keep-state]" >&2
      exit 2
      ;;
  esac
done

CANONICAL_INSTALL_ROOT="$HOME/.local/share/ai-env-optimizer"
LEGACY_INSTALL_ROOT="$HOME/.local/share/ai-optimizer"
if [ -n "${AI_ENV_OPTIMIZER_PREFIX:-}" ]; then
  INSTALL_ROOT="$AI_ENV_OPTIMIZER_PREFIX"
elif [ -n "${AI_OPTIMIZER_PREFIX:-}" ]; then
  INSTALL_ROOT="$AI_OPTIMIZER_PREFIX"
elif [ -f "$CANONICAL_INSTALL_ROOT/.ai-env-optimizer-install" ]; then
  INSTALL_ROOT="$CANONICAL_INSTALL_ROOT"
else
  INSTALL_ROOT="$LEGACY_INSTALL_ROOT"
fi
BIN_DIR="${AI_ENV_OPTIMIZER_BIN_DIR:-${AI_OPTIMIZER_BIN_DIR:-$HOME/.local/bin}}"
CANONICAL_DATA_DIR="$HOME/Library/Application Support/io.github.nyldn.ai-env-optimizer"
LEGACY_DATA_DIR="$HOME/Library/Application Support/io.github.nyldn.ai-optimizer"
if [ -n "${AI_ENV_OPTIMIZER_DATA_DIR:-}" ]; then
  DATA_DIR="$AI_ENV_OPTIMIZER_DATA_DIR"
elif [ -n "${AI_OPTIMIZER_DATA_DIR:-}" ]; then
  DATA_DIR="$AI_OPTIMIZER_DATA_DIR"
elif [ -e "$CANONICAL_DATA_DIR" ]; then
  DATA_DIR="$CANONICAL_DATA_DIR"
else
  DATA_DIR="$LEGACY_DATA_DIR"
fi
CANONICAL_LINK="$BIN_DIR/ai-env-optimizer"
LEGACY_LINK="$BIN_DIR/ai-optimizer"

case "$INSTALL_ROOT" in
  ''|/|"$HOME")
    echo "Refusing unsafe install root: $INSTALL_ROOT" >&2
    exit 1
    ;;
esac

if ! { [ -f "$INSTALL_ROOT/.ai-env-optimizer-install" ] &&
       grep -q '^owner=ai-env-optimizer$' "$INSTALL_ROOT/.ai-env-optimizer-install"; } &&
   ! { [ -f "$INSTALL_ROOT/.ai-optimizer-install" ] &&
       grep -q '^owner=ai-optimizer$' "$INSTALL_ROOT/.ai-optimizer-install"; }; then
  echo "Refusing to remove an install root without AI Environment Optimizer provenance." >&2
  exit 1
fi

echo "AI Environment Optimizer will remove:"
echo "  $INSTALL_ROOT"
if [ -L "$CANONICAL_LINK" ] && [ "$(readlink "$CANONICAL_LINK")" = "$INSTALL_ROOT/bin/ai-env-optimizer" ]; then
  echo "  $CANONICAL_LINK"
fi
if [ -L "$LEGACY_LINK" ] &&
   { [ "$(readlink "$LEGACY_LINK")" = "$INSTALL_ROOT/bin/ai-env-optimizer" ] ||
     [ "$(readlink "$LEGACY_LINK")" = "$INSTALL_ROOT/bin/ai-optimizer" ]; }; then
  echo "  $LEGACY_LINK"
fi
if [ "$KEEP_STATE" -eq 0 ] && [ -f "$DATA_DIR/state-manifest.json" ] &&
   grep -Eq '"owner": "(ai-env-optimizer|ai-optimizer)"' "$DATA_DIR/state-manifest.json"; then
  echo "  $DATA_DIR"
fi

if [ "$FORCE" -eq 0 ]; then
  printf "Continue? [y/N] "
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

if [ -x "$INSTALL_ROOT/bin/ai-env-optimizer" ]; then
  env AI_ENV_OPTIMIZER_DATA_DIR="$DATA_DIR" "$INSTALL_ROOT/bin/ai-env-optimizer" unschedule >/dev/null 2>&1 || true
elif [ -x "$INSTALL_ROOT/bin/ai-optimizer" ]; then
  env AI_OPTIMIZER_DATA_DIR="$DATA_DIR" "$INSTALL_ROOT/bin/ai-optimizer" unschedule >/dev/null 2>&1 || true
fi

if [ -L "$CANONICAL_LINK" ] && [ "$(readlink "$CANONICAL_LINK")" = "$INSTALL_ROOT/bin/ai-env-optimizer" ]; then
  rm -f "$CANONICAL_LINK"
fi
if [ -L "$LEGACY_LINK" ] &&
   { [ "$(readlink "$LEGACY_LINK")" = "$INSTALL_ROOT/bin/ai-env-optimizer" ] ||
     [ "$(readlink "$LEGACY_LINK")" = "$INSTALL_ROOT/bin/ai-optimizer" ]; }; then
  rm -f "$LEGACY_LINK"
fi

rm -rf "$INSTALL_ROOT"

if [ "$KEEP_STATE" -eq 0 ] && [ -f "$DATA_DIR/state-manifest.json" ] &&
   grep -Eq '"owner": "(ai-env-optimizer|ai-optimizer)"' "$DATA_DIR/state-manifest.json"; then
  rm -rf "$DATA_DIR"
fi

echo "AI Environment Optimizer uninstalled."
