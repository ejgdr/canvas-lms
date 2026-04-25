#!/usr/bin/env python3
"""detect_changes.py — emit .analysis/indexes/stale-paths.txt

Compares the current file-hashes.json against its previous snapshot (kept as
file-hashes.prev.json). On the first run, all tracked files are written as
"stale" so downstream index builds run fully.

Usage:
    python3 agents/scripts/detect_changes.py <REPO_PATH>
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: detect_changes.py <REPO_PATH>", file=sys.stderr)
        return 2

    repo = Path(sys.argv[1]).resolve()
    index_dir = repo / ".analysis" / "indexes"
    current_path = index_dir / "file-hashes.json"
    prev_path = index_dir / "file-hashes.prev.json"
    out_path = index_dir / "stale-paths.txt"

    if not current_path.exists():
        print(
            f"error: {current_path} missing. Run hash_tree.py first.",
            file=sys.stderr,
        )
        return 1

    current: dict[str, dict] = json.loads(current_path.read_text())
    if prev_path.exists():
        prev: dict[str, dict] = json.loads(prev_path.read_text())
    else:
        prev = {}

    stale: list[str] = []
    for rel, data in current.items():
        old = prev.get(rel)
        if old is None or old.get("sha1") != data.get("sha1"):
            stale.append(rel)
    for rel in prev:
        if rel not in current:
            # deleted file — also counts as stale so summaries get refreshed
            stale.append(rel)

    stale.sort()
    out_path.write_text("\n".join(stale) + ("\n" if stale else ""))
    # Promote current to prev so next run diffs against it.
    shutil.copyfile(current_path, prev_path)

    print(f"wrote {out_path} ({len(stale)} stale paths)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
