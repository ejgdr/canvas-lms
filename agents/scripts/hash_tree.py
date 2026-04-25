#!/usr/bin/env python3
"""hash_tree.py — emit .analysis/indexes/file-hashes.json

Walks git-tracked files only (respects .gitignore). Skips any file larger
than MAX_BYTES so we don't spend I/O on fixture dumps or binary blobs.

Output shape:
    {
      "<relative_path>": { "sha1": "...", "size": 1234, "mtime": 1700000000.0 },
      ...
    }

Usage:
    python3 agents/scripts/hash_tree.py <REPO_PATH>
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

MAX_BYTES = 500_000  # skip anything above this — fixtures, minified bundles, images


def sha1_of(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: hash_tree.py <REPO_PATH>", file=sys.stderr)
        return 2

    repo = Path(sys.argv[1]).resolve()
    index_dir = repo / ".analysis" / "indexes"
    index_dir.mkdir(parents=True, exist_ok=True)

    tracked = subprocess.check_output(
        ["git", "-C", str(repo), "ls-files"],
        text=True,
    ).splitlines()

    result: dict[str, dict] = {}
    skipped_large = 0
    for rel in tracked:
        abs_path = repo / rel
        try:
            stat = abs_path.stat()
        except (OSError, FileNotFoundError):
            continue
        if stat.st_size > MAX_BYTES:
            skipped_large += 1
            continue
        try:
            digest = sha1_of(abs_path)
        except OSError:
            continue
        result[rel] = {
            "sha1": digest,
            "size": stat.st_size,
            "mtime": stat.st_mtime,
        }

    out = index_dir / "file-hashes.json"
    out.write_text(json.dumps(result, indent=2, sort_keys=True))
    print(
        f"wrote {out} ({len(result)} files hashed, {skipped_large} skipped > {MAX_BYTES} bytes)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
