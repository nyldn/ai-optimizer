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

RELEASE_BASE="${AI_ENV_OPTIMIZER_RELEASE_BASE:-${AI_OPTIMIZER_RELEASE_BASE:-https://github.com/nyldn/ai-env-optimizer/releases/download/v${VERSION}}}"
CANONICAL_INSTALL_ROOT="$HOME/.local/share/ai-env-optimizer"
LEGACY_INSTALL_ROOT="$HOME/.local/share/ai-optimizer"
if [ -n "${AI_ENV_OPTIMIZER_PREFIX:-}" ]; then
  INSTALL_ROOT="$AI_ENV_OPTIMIZER_PREFIX"
elif [ -n "${AI_OPTIMIZER_PREFIX:-}" ]; then
  INSTALL_ROOT="$AI_OPTIMIZER_PREFIX"
elif [ -e "$CANONICAL_INSTALL_ROOT" ]; then
  INSTALL_ROOT="$CANONICAL_INSTALL_ROOT"
elif [ -f "$LEGACY_INSTALL_ROOT/.ai-env-optimizer-install" ] ||
     [ -f "$LEGACY_INSTALL_ROOT/.ai-optimizer-install" ]; then
  INSTALL_ROOT="$LEGACY_INSTALL_ROOT"
else
  INSTALL_ROOT="$CANONICAL_INSTALL_ROOT"
fi
BIN_DIR="${AI_ENV_OPTIMIZER_BIN_DIR:-${AI_OPTIMIZER_BIN_DIR:-$HOME/.local/bin}}"
ARCHIVE="ai-env-optimizer-${VERSION}.tar.gz"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-env-optimizer-install.XXXXXX")"
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
    "ai-env-optimizer-${VERSION}"|"ai-env-optimizer-${VERSION}/"|"ai-env-optimizer-${VERSION}/"*) ;;
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
SOURCE_ROOT="$TEMP_DIR/ai-env-optimizer-${VERSION}"
[ ! -L "$SOURCE_ROOT" ] || {
  echo "Release root must not be a symlink." >&2
  exit 1
}
[ -x "$SOURCE_ROOT/bin/ai-env-optimizer" ] || {
  echo "Release archive is missing bin/ai-env-optimizer." >&2
  exit 1
}

ACTUAL_VERSION="$(/usr/bin/ruby "$SOURCE_ROOT/bin/ai-env-optimizer" version)"
[ "$ACTUAL_VERSION" = "ai-env-optimizer $VERSION" ] || {
  echo "Release version validation failed." >&2
  exit 1
}

if [ -e "$INSTALL_ROOT" ]; then
  [ ! -L "$INSTALL_ROOT" ] || {
    echo "Refusing to replace a symlinked install root." >&2
    exit 1
  }
  if ! { [ -f "$INSTALL_ROOT/.ai-env-optimizer-install" ] &&
         grep -q '^owner=ai-env-optimizer$' "$INSTALL_ROOT/.ai-env-optimizer-install"; } &&
     ! { [ -f "$INSTALL_ROOT/.ai-optimizer-install" ] &&
         grep -q '^owner=ai-optimizer$' "$INSTALL_ROOT/.ai-optimizer-install"; }; then
    echo "Refusing to replace a directory not owned by AI Environment Optimizer." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$INSTALL_ROOT")" "$BIN_DIR"

CANONICAL_LINK="$BIN_DIR/ai-env-optimizer"
LEGACY_LINK="$BIN_DIR/ai-optimizer"
validate_existing_link() {
  link_path="$1"
  shift
  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    [ -L "$link_path" ] || {
      echo "Refusing to replace unrelated $link_path." >&2
      exit 1
    }
    link_target="$(readlink "$link_path")"
    for expected_target in "$@"; do
      [ "$link_target" != "$expected_target" ] || return 0
    done
    echo "Refusing to replace unrelated $link_path." >&2
    exit 1
  fi
}
validate_existing_link "$CANONICAL_LINK" "$INSTALL_ROOT/bin/ai-env-optimizer"
validate_existing_link "$LEGACY_LINK" \
  "$INSTALL_ROOT/bin/ai-env-optimizer" \
  "$INSTALL_ROOT/bin/ai-optimizer"

mv "$SOURCE_ROOT" "$STAGED_ROOT"
printf 'owner=ai-env-optimizer\nversion=%s\n' "$VERSION" > "$STAGED_ROOT/.ai-env-optimizer-install"

if [ -e "$INSTALL_ROOT" ]; then
  mv "$INSTALL_ROOT" "$BACKUP_ROOT"
fi

if ! mv "$STAGED_ROOT" "$INSTALL_ROOT"; then
  [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
  echo "Install swap failed; the previous version was restored." >&2
  exit 1
fi

if ! ln -sfn "$INSTALL_ROOT/bin/ai-env-optimizer" "$CANONICAL_LINK" ||
   ! ln -sfn "$INSTALL_ROOT/bin/ai-env-optimizer" "$LEGACY_LINK"; then
  rm -rf "$INSTALL_ROOT"
  [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$INSTALL_ROOT"
  echo "Command links failed; the previous version was restored." >&2
  exit 1
fi
rm -rf "$BACKUP_ROOT"

echo "Installed AI Environment Optimizer $VERSION."
echo "Run: $CANONICAL_LINK setup"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "Add AI Environment Optimizer to zsh PATH:"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
    ;;
esac
