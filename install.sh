#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: install.sh --version VERSION" >&2
}

VERSION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$VERSION" in
  ''|*[!0-9.]*)
    echo "A numeric dotted --version is required." >&2
    exit 2
    ;;
esac

RELEASE_BASE="${AI_OPTIMIZER_RELEASE_BASE:-https://github.com/nyldn/ai-optimizer/releases/download/v${VERSION}}"
INSTALL_ROOT="${AI_OPTIMIZER_PREFIX:-$HOME/.local/share/ai-optimizer}"
BIN_DIR="${AI_OPTIMIZER_BIN_DIR:-$HOME/.local/bin}"
ARCHIVE="ai-optimizer-${VERSION}.tar.gz"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-optimizer-install.XXXXXX")"
STAGED_ROOT="${INSTALL_ROOT}.staged.$$"
BACKUP_ROOT="${INSTALL_ROOT}.backup.$$"

cleanup() {
  rm -rf "$TEMP_DIR"
  rm -rf "$STAGED_ROOT"
}
trap cleanup EXIT INT TERM

case "$INSTALL_ROOT" in
  ''|/|"$HOME")
    echo "Refusing unsafe install root: $INSTALL_ROOT" >&2
    exit 1
    ;;
esac

curl -fsSL --retry 2 --connect-timeout 10 "$RELEASE_BASE/$ARCHIVE" -o "$TEMP_DIR/$ARCHIVE"
curl -fsSL --retry 2 --connect-timeout 10 "$RELEASE_BASE/$ARCHIVE.sha256" -o "$TEMP_DIR/$ARCHIVE.sha256"

(
  cd "$TEMP_DIR"
  shasum -a 256 -c "$ARCHIVE.sha256"
)

while IFS= read -r entry; do
  case "$entry" in
    "ai-optimizer-${VERSION}"|"ai-optimizer-${VERSION}/"|"ai-optimizer-${VERSION}/"*) ;;
    *)
      echo "Release archive contains an unexpected path." >&2
      exit 1
      ;;
  esac
  case "/$entry/" in
    *"/../"*)
      echo "Release archive contains parent traversal." >&2
      exit 1
      ;;
  esac
done < <(tar -tzf "$TEMP_DIR/$ARCHIVE")

tar -xzf "$TEMP_DIR/$ARCHIVE" -C "$TEMP_DIR"
SOURCE_ROOT="$TEMP_DIR/ai-optimizer-${VERSION}"
[ ! -L "$SOURCE_ROOT" ] || {
  echo "Release root must not be a symlink." >&2
  exit 1
}
[ -x "$SOURCE_ROOT/bin/ai-optimizer" ] || {
  echo "Release archive is missing bin/ai-optimizer." >&2
  exit 1
}

ACTUAL_VERSION="$(/usr/bin/ruby "$SOURCE_ROOT/bin/ai-optimizer" version)"
[ "$ACTUAL_VERSION" = "ai-optimizer $VERSION" ] || {
  echo "Release version validation failed." >&2
  exit 1
}

if [ -e "$INSTALL_ROOT" ]; then
  [ ! -L "$INSTALL_ROOT" ] || {
    echo "Refusing to replace a symlinked install root." >&2
    exit 1
  }
  [ -f "$INSTALL_ROOT/.ai-optimizer-install" ] || {
    echo "Refusing to replace a directory not owned by AI Optimizer." >&2
    exit 1
  }
fi

mkdir -p "$(dirname "$INSTALL_ROOT")" "$BIN_DIR"
mv "$SOURCE_ROOT" "$STAGED_ROOT"
printf 'owner=ai-optimizer\nversion=%s\n' "$VERSION" > "$STAGED_ROOT/.ai-optimizer-install"

if [ -e "$INSTALL_ROOT" ]; then
  mv "$INSTALL_ROOT" "$BACKUP_ROOT"
fi

if ! mv "$STAGED_ROOT" "$INSTALL_ROOT"; then
  [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
  echo "Install swap failed; the previous version was restored." >&2
  exit 1
fi

LINK_PATH="$BIN_DIR/ai-optimizer"
if [ -e "$LINK_PATH" ] || [ -L "$LINK_PATH" ]; then
  if [ -L "$LINK_PATH" ]; then
    LINK_TARGET="$(readlink "$LINK_PATH")"
    case "$LINK_TARGET" in
      "$INSTALL_ROOT"/bin/ai-optimizer) ;;
      *)
        rm -rf "$INSTALL_ROOT"
        [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
        echo "Refusing to replace unrelated $LINK_PATH." >&2
        exit 1
        ;;
    esac
  else
    rm -rf "$INSTALL_ROOT"
    [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
    echo "Refusing to replace unrelated $LINK_PATH." >&2
    exit 1
  fi
fi

if ! ln -sfn "$INSTALL_ROOT/bin/ai-optimizer" "$LINK_PATH"; then
  rm -rf "$INSTALL_ROOT"
  [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
  echo "Command link failed; the previous version was restored." >&2
  exit 1
fi
rm -rf "$BACKUP_ROOT"

echo "Installed AI Optimizer $VERSION."
echo "Run: $LINK_PATH setup"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "Add AI Optimizer to zsh PATH:"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
    ;;
esac
