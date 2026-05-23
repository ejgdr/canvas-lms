# Feature-1 QA Evidence

This file records the QA-agent outcome for each slice closed under the workflow in `agents/quality-assurance.md`. Each entry pairs the corresponding `agents/tasks/feature-1/implementation-evidence.md` cycle with the QA decision: classification, test added or justified-skip rationale, command and outcome, the resulting `QA Status` on the project board, and a one-line trace back to the feature's FR.

## Entry shape

Each entry below uses the following fields, in order:

| Field | Content |
|---|---|
| Slice | Issue title and link; branch name |
| Classification | One of: behavior-changing code / config-only / docs-only / pure rename / dependency bump |
| Tests added or updated | File path(s) and a one-line AAA-style description per test (or "none — see rationale" for justified skips) |
| Command | The exact command string that was run |
| Outcome | Exit code and the clipped summary line(s) from stdout |
| `QA Status` | `Pass`, `Skip — justified`, or `Fail` — must match the board field |
| PR / commit | Link to the PR or merged commit |
| Trace to plan | One sentence linking the test (or skip rationale) to the FR-N defended in `implementation-research.md` |

## Cycle 1 — Feature-flag declaration (retroactive classification)

The first closed slice (issue #1, PR #54) merged before this workflow was introduced. Classifying retroactively under the criteria in `agents/quality-assurance.md` for traceability; the formal QA workflow begins with Cycle 2.

| Field | Content |
|---|---|
| Slice | [#1](https://github.com/ejgdr/canvas-lms/issues/1) — "[M1] Declare discussion_thread_summarizer feature flag." Branch `feat/m1-feature-flag-discussion-summarizer`. |
| Classification | Config-only (YAML, no embedded ERB or runtime logic) |
| Tests added or updated | None — config-only allows the smallest credible substitute per the criteria |
| Command | `python -c "import yaml; yaml.safe_load(open('config/feature_flags/discussion_thread_summarizer.yml'))"` (Ruby unavailable on the development host; Python `yaml` fallback per the QA agent spec) |
| Outcome | Exit code 0; both flag entries parsed as well-formed mappings |
| `QA Status` | `Skip — justified` (config-only with parse-check substitute) |
| PR / commit | [PR #54](https://github.com/ejgdr/canvas-lms/pull/54), squash-merged at `fb2736d9b3abd45e573dc865a52dcb7552eecc4f` |
| Trace to plan | FR-4 — the system must not generate, render, or call out to summarization when the feature is disabled; the declared flag is the precondition every downstream slice gates on |

---

## Cycle 2 — Toggle UI plumbing (issue #2, M1 Foundations)

| Field | Content |
|---|---|
| Slice | [#2](https://github.com/ejgdr/canvas-lms/issues/2) — "[M1] Account- and course-level feature toggle UI plumbing." Branch `feat/m1-toggle-ui-plumbing`. |
| Classification | Behavior-changing code (the controller line adds a runtime flag check and a new observable `js_env` key). The `environments` block added to the YAML is incidental config-only; it is covered by the Ruby feature-flag loader running in the same RSpec session and does not require a separate parse check. |
| Tests added or updated | `spec/controllers/discussion_topics_controller_spec.rb` — two examples added inside `describe "GET 'show'"`, `context "discussion_thread_summarizer_enabled js_env"`: (1) Given the feature is enabled for the course, GET show sets `discussion_thread_summarizer_enabled: true` in js_env. (2) Given the feature is disabled for the course, GET show sets `discussion_thread_summarizer_enabled: false` in js_env. |
| Command | `docker compose exec web bundle exec rspec spec/controllers/discussion_topics_controller_spec.rb -e 'discussion_thread_summarizer_enabled js_env' --format documentation` |
| Outcome | Exit code 0; `2 examples, 0 failures` (finished in 6.33 seconds, seed 8007) |
| `QA Status` | `Pass` |
| PR / commit | [PR #56](https://github.com/ejgdr/canvas-lms/pull/56), squash-merged at `efd2722a9b689ca3bf12ca0d91534c0f77fbabd9` |
| Trace to plan | FR-4 — the system must not generate, render, or call out to the summarization model when the feature is disabled; the controller ENV key `discussion_thread_summarizer_enabled` is the plumbing all downstream components (M4 summary block, M5 digest tab) will gate on. The `@context.is_a?(Course)` guard ships with only the Course path exercised in tests; the group-discussion path (where `@context` is a Group) is explicitly outside feature scope per `implementation-research.md` §2 scope boundaries. |

---

## Cycle 3 — Permission audit (issue #3, M1 Foundations)

| Field | Content |
|---|---|
| Slice | [#3](https://github.com/ejgdr/canvas-lms/issues/3) — "[M1] Permission audit: confirm reuse of read and moderate_forum gates." Branch `docs/m1-permission-audit`. |
| Classification | Docs-only (two Ruby `#` comment insertions in `discussion_topic.rb`; one new Markdown file in `doc/`). No executable token added, removed, or changed; `set_policy` block untouched. |
| Tests added or updated | None — see rationale |
| Command | N/A |
| Outcome | N/A |
| `QA Status` | `Skip — justified` (docs-only: pure comments in a model file and a new Markdown audit record; no behavior-changing application code in diff) |
| PR / commit | [PR #58](https://github.com/ejgdr/canvas-lms/pull/58) |
| Trace to plan | FR-4, FR-9, NFR-6 — all acceptance criteria are satisfied by confirming existing gates are present (documented), not by adding new runtime code. No new `given`/`can` blocks or `RoleOverride` entries appear anywhere in the diff. |

---

*Last verified: 2026-05-23 against commit 69d86f45561*
