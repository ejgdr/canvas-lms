#!/usr/bin/env python3
"""token_count.py — estimate tokens for a file or for stdin.

Usage:
    python3 agents/scripts/token_count.py <path>
    cat something.rb | python3 agents/scripts/token_count.py -

Prints a single JSON line:
    {"tokens": 1234, "estimator": "tiktoken", "encoding": "cl100k_base"}

When tiktoken is not installed, falls back to a len(text)//4 heuristic and
sets "estimator" to "char_div_4" so the run report can note the approximation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def load_text(arg: str) -> str:
    if arg == "-":
        return sys.stdin.read()
    return Path(arg).read_text(errors="replace")


def count(text: str) -> tuple[int, str, str]:
    try:
        import tiktoken  # type: ignore
    except ImportError:
        return (max(1, len(text) // 4), "char_div_4", "n/a")
    enc = tiktoken.get_encoding("cl100k_base")
    return (len(enc.encode(text)), "tiktoken", "cl100k_base")


def main() -> int:
    if len(sys.argv) != 2:
        print('usage: token_count.py <path-or-">', file=sys.stderr)
        return 2
    text = load_text(sys.argv[1])
    tokens, estimator, encoding = count(text)
    print(json.dumps({"tokens": tokens, "estimator": estimator, "encoding": encoding}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
