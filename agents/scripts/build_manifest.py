#!/usr/bin/env python3
"""build_manifest.py — emit .analysis/indexes/manifest.json

For each top-level directory in the target repo, record:
  - file count (git-tracked only)
  - total bytes
  - top N file extensions by count

Uses `git ls-files` so .gitignore is respected automatically and so we don't
walk into node_modules / vendor / log directories.

Usage:
    python3 agents/scripts/build_manifest.py <REPO_PATH>
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: build_manifest.py <REPO_PATH>", file=sys.stderr)
        return 2

    repo = Path(sys.argv[1]).resolve()
    index_dir = repo / ".analysis" / "indexes"
    index_dir.mkdir(parents=True, exist_ok=True)

    tracked = subprocess.check_output(
        ["git", "-C", str(repo), "ls-files"],
        text=True,
    ).splitlines()

    # Bucket by top-level directory. Files at repo root go into "_root".
    by_top: dict[str, dict] = defaultdict(
        lambda: {"files": 0, "bytes": 0, "extensions": Counter()}
    )

    for rel in tracked:
        parts = rel.split("/", 1)
        top = parts[0] if len(parts) > 1 else "_root"
        bucket = by_top[top]
        bucket["files"] += 1
        try:
            bucket["bytes"] += (repo / rel).stat().st_size
        except (OSError, FileNotFoundError):
            continue
        ext = os.path.splitext(rel)[1].lower() or "<none>"
        bucket["extensions"][ext] += 1

    manifest = {
        "repo": str(repo),
        "tracked_files_total": len(tracked),
        "top_level": {},
    }
    for top, data in sorted(by_top.items()):
        manifest["top_level"][top] = {
            "files": data["files"],
            "bytes": data["bytes"],
            "top_extensions": data["extensions"].most_common(5),
        }

    out = index_dir / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2))
    print(f"wrote {out} ({len(tracked)} files across {len(by_top)} top-level dirs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
