#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

while IFS= read -r file; do
  /usr/bin/ruby -c "$file" >/dev/null
done < <(find "$ROOT_DIR/lib" "$ROOT_DIR/test" -type f -name '*.rb' -print | sort)

/usr/bin/ruby -c "$ROOT_DIR/bin/ai-env-optimizer" >/dev/null

while IFS= read -r file; do
  /bin/bash -n "$file"
done < <(find "$ROOT_DIR" -type f -name '*.sh' -not -path '*/.git/*' -print | sort)

echo "syntax checks passed"
