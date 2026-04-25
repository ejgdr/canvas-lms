#!/usr/bin/env bash
# extract_span.sh — return a bounded window from a file.
#
# Usage:
#   bash agents/scripts/extract_span.sh <REPO_PATH> <relative_file> <A:B>          # line range
#   bash agents/scripts/extract_span.sh <REPO_PATH> <relative_file> <pattern> [ctx] # regex with N lines context (default 20)
#
# Prints the snippet with line numbers to stdout. Caps output at 400 lines to
# guarantee the agent can't accidentally blow the budget in a single call.

set -euo pipefail

REPO_PATH="${1:?usage: extract_span.sh <REPO_PATH> <relative_file> <pattern-or-A:B> [ctx]}"
FILE_REL="${2:?missing file}"
WHAT="${3:?missing pattern or line range}"
CTX="${4:-20}"
MAX_LINES=400

FILE_ABS="$REPO_PATH/$FILE_REL"
if [[ ! -f "$FILE_ABS" ]]; then
  echo "error: file not found: $FILE_ABS" >&2
  exit 1
fi

if [[ "$WHAT" =~ ^([0-9]+):([0-9]+)$ ]]; then
  A="${BASH_REMATCH[1]}"
  B="${BASH_REMATCH[2]}"
  awk -v A="$A" -v B="$B" -v MAX="$MAX_LINES" '
    NR>=A && NR<=B {
      printed++;
      if (printed > MAX) { print "... (truncated at " MAX " lines)"; exit }
      printf "%6d  %s\n", NR, $0;
    }' "$FILE_ABS"
else
  if ! command -v rg >/dev/null 2>&1; then
    echo "error: ripgrep (rg) is required for pattern mode." >&2
    exit 1
  fi
  rg --line-number --color never --context "$CTX" -e "$WHAT" "$FILE_ABS" \
    | head -n "$MAX_LINES"
fi
