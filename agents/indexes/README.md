# `agents/indexes/` — layout reference

The *actual* index files live inside the target repo at `.analysis/indexes/` (gitignored, since Canvas upstream shouldn't carry our cache). This folder in `agents/` is a **reference** describing what those generated files look like, so that anyone reading the spec (or a follow-up agent in Phase 1) can see the expected shape without cloning Canvas first.

Nothing in this folder is read at runtime.

## Expected files in `.analysis/indexes/`

### `TOC.md`

Auto-generated last on every `run_index.sh` call. Lists every other index file with a one-line description and the count of stale paths detected. The agent reads this first.

### `manifest.json`

```json
{
  "repo": "/home/ubuntu/canvas-lms",
  "tracked_files_total": 28412,
  "top_level": {
    "app":      { "files": 6123, "bytes": 48392011, "top_extensions": [[".rb", 4812], [".erb", 701], [".rake", 34]] },
    "ui":       { "files": 8211, "bytes": 62044812, "top_extensions": [[".tsx", 3911], [".ts", 2013], [".js", 1800]] },
    "packages": { "files": 3100, "bytes": 21100412, "top_extensions": [[".ts", 1900], [".tsx", 700]] },
    "gems":     { "files": 2044, "bytes": 18012300, "top_extensions": [[".rb", 1800]] },
    "spec":     { "files": 4011, "bytes": 34000100, "top_extensions": [[".rb", 3900]] }
  }
}
```

### `key-files.md`

Hand-seeded, agent-appended. The seed content depends on what stack the target repo uses — the agent picks a minimal set of manifests, routing tables, entrypoints, and schema snapshots. The example below is the Phase-1 seed for Canvas LMS; see `analyze-repo.md` appendix for this verbatim.

```markdown
# Key files — Canvas LMS (Phase 1 example)

- `Gemfile` / `Gemfile.lock` — Ruby dependency pins
- `package.json` / `yarn.lock` — JS root workspace
- `config/routes.rb` — every HTTP route in Canvas
- `config/application.rb` — Rails app config
- `app/controllers/application_controller.rb` — base controller, auth hooks
- `app/models/user.rb` — central user model
- `ui/index.tsx` — frontend entrypoint
- `db/schema.rb` — current DB schema snapshot
- `doc/api/README.md` — API reference starting point
```

For other repos, swap in the equivalents — e.g. `pyproject.toml` + top-level `__init__.py` for a Python project, or `go.mod` + `cmd/*/main.go` for a Go project.

### `symbol-map.tsv`

Tab-separated, one symbol per row:

```
GradeCalculator        class    lib/grade_calculator.rb                 14
Submission             class    app/models/submission.rb                22
Api::V1::Course        module   app/controllers/api/v1/course.rb         3
CoursesTable           const    ui/features/courses/CoursesTable.tsx    11
```

### `folder-summaries/<folder>.md`

≤ 400-word summary per top-level folder, generated via the LLM using `scripts/summarize_folder.prompt.md`. Ends with a `<!-- hash:... -->` footer used for staleness detection.

### `file-hashes.json`

```json
{
  "app/controllers/courses_controller.rb": { "sha1": "ab12…", "size": 23841, "mtime": 1745512301.0 },
  "app/models/submission.rb":              { "sha1": "cd34…", "size": 19102, "mtime": 1745512301.0 }
}
```

### `stale-paths.txt`

Plain text, one relative path per line — the paths whose SHA1 differs from the previous run. Used to decide which indexes to rebuild incrementally.

### `last-run-stats.json`

```json
{
  "timestamp": "2026-04-25T18:22:01Z",
  "model": "gpt-4o-mini",
  "window_tokens": 128000,
  "budget_tokens": 51200,
  "tokens_used": 18420,
  "percent_of_window": 14.4,
  "percent_of_budget": 36.0,
  "files_opened": 7,
  "spans_extracted": 12,
  "scripts_invoked": ["run_index.sh", "extract_span.sh", "token_count.py"],
  "status": "ok",
  "question": "Where is GradeCalculator defined and what does compute_scores do?"
}
```

This is the file whose contents + Cursor's own context gauge produce the rubric's required screenshot.
