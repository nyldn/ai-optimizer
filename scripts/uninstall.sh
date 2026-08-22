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

INSTALL_ROOT="${AI_OPTIMIZER_PREFIX:-$HOME/.local/share/ai-optimizer}"
BIN_DIR="${AI_OPTIMIZER_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${AI_OPTIMIZER_DATA_DIR:-$HOME/Library/Application Support/io.github.nyldn.ai-optimizer}"
LINK_PATH="$BIN_DIR/ai-optimizer"

case "$INSTALL_ROOT" in
  ''|/|"$HOME")
    echo "Refusing unsafe install root: $INSTALL_ROOT" >&2
    exit 1
    ;;
esac

if [ ! -f "$INSTALL_ROOT/.ai-optimizer-install" ] ||
   ! grep -q '^owner=ai-optimizer$' "$INSTALL_ROOT/.ai-optimizer-install"; then
  echo "Refusing to remove an install root without AI Optimizer provenance." >&2
  exit 1
fi

echo "AI Optimizer will remove:"
echo "  $INSTALL_ROOT"
if [ -L "$LINK_PATH" ] && [ "$(readlink "$LINK_PATH")" = "$INSTALL_ROOT/bin/ai-optimizer" ]; then
  echo "  $LINK_PATH"
fi
if [ "$KEEP_STATE" -eq 0 ] && [ -f "$DATA_DIR/state-manifest.json" ] &&
   grep -q '"owner": "ai-optimizer"' "$DATA_DIR/state-manifest.json"; then
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

if [ -x "$INSTALL_ROOT/bin/ai-optimizer" ]; then
  env AI_OPTIMIZER_DATA_DIR="$DATA_DIR" "$INSTALL_ROOT/bin/ai-optimizer" unschedule >/dev/null 2>&1 || true
fi

if [ -L "$LINK_PATH" ] && [ "$(readlink "$LINK_PATH")" = "$INSTALL_ROOT/bin/ai-optimizer" ]; then
  rm -f "$LINK_PATH"
fi

rm -rf "$INSTALL_ROOT"

if [ "$KEEP_STATE" -eq 0 ] && [ -f "$DATA_DIR/state-manifest.json" ] &&
   grep -q '"owner": "ai-optimizer"' "$DATA_DIR/state-manifest.json"; then
  rm -rf "$DATA_DIR"
fi

echo "AI Optimizer uninstalled."
