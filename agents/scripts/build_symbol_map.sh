#!/usr/bin/env bash
# build_symbol_map.sh — emit .analysis/indexes/symbol-map.tsv
#
# Fields (tab-separated):
#   symbol    kind    path    line
#
# Default language profile (extend the ripgrep blocks below for more):
#   - Ruby   : `class Foo`, `module Bar`
#   - JS/TS  : top-level `export` declarations
#   - Python : top-level `class Foo:` and `def foo(`
#
# To add a language (e.g. Go, Rust), append another ripgrep+awk block producing
# the same four tab-separated fields: symbol, kind, path, line.
#
# Requires ripgrep. If rg is not installed, fail loudly — the agent depends on it.

set -euo pipefail

REPO_PATH="${1:?usage: build_symbol_map.sh <REPO_PATH>}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required. Install with 'sudo apt install ripgrep'." >&2
  exit 1
fi

INDEX_DIR="$REPO_PATH/.analysis/indexes"
mkdir -p "$INDEX_DIR"
OUT="$INDEX_DIR/symbol-map.tsv"

{
  # Ruby: class / module declarations. Capture the leading identifier.
  rg --no-heading --line-number --color never \
     --type ruby \
     -g '!vendor/**' -g '!node_modules/**' -g '!tmp/**' -g '!log/**' \
     -e '^\s*(class|module)\s+([A-Z][A-Za-z0-9_:]+)' \
     "$REPO_PATH" \
  | awk -F: '
      {
        file=$1; line=$2;
        # Rebuild the match body in case it contained ":".
        body="";
        for (i=3; i<=NF; i++) body = body (i>3?":":"") $i;
        if (match(body, /(class|module)[[:space:]]+([A-Z][A-Za-z0-9_:]+)/, m)) {
          printf "%s\t%s\t%s\t%s\n", m[2], m[1], file, line;
        }
      }'

  # JS/TS: top-level export declarations. Capture the exported identifier.
  rg --no-heading --line-number --color never \
     --type-add 'tsx:*.tsx' --type-add 'jsx:*.jsx' \
     -t ts -t tsx -t js -t jsx \
     -g '!node_modules/**' -g '!**/dist/**' -g '!**/build/**' -g '!tmp/**' \
     -e '^export\s+(default\s+)?(async\s+)?(function|class|const|let|var|interface|type|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)' \
     "$REPO_PATH" \
  | awk -F: '
      {
        file=$1; line=$2;
        body="";
        for (i=3; i<=NF; i++) body = body (i>3?":":"") $i;
        if (match(body, /(function|class|const|let|var|interface|type|enum)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)/, m)) {
          printf "%s\t%s\t%s\t%s\n", m[2], m[1], file, line;
        }
      }'

  # Python: top-level class and def declarations (col 0 only, so we skip nested defs).
  rg --no-heading --line-number --color never \
     --type py \
     -g '!**/venv/**' -g '!**/.venv/**' -g '!**/__pycache__/**' \
     -e '^(class|def)\s+([A-Za-z_][A-Za-z0-9_]*)' \
     "$REPO_PATH" \
  | awk -F: '
      {
        file=$1; line=$2;
        body="";
        for (i=3; i<=NF; i++) body = body (i>3?":":"") $i;
        if (match(body, /(class|def)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m)) {
          printf "%s\t%s\t%s\t%s\n", m[2], m[1], file, line;
        }
      }'
} | sort -u > "$OUT"

COUNT=$(wc -l < "$OUT" | tr -d ' ')
echo "wrote $OUT ($COUNT symbols)"
