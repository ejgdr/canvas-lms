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

## Cycle 4 — Feature-flag inheritance integration tests (issue #5, M1 Foundations)

| Field | Content |
|---|---|
| Slice | [#5](https://github.com/ejgdr/canvas-lms/issues/5) — "[M1] Integration test: feature-flag inheritance (account default → course override)." Branch `test/m1-flag-inheritance-integration`. |
| Classification | Behavior-changing application code — the diff adds RSpec examples to `spec/controllers/discussion_topics_controller_spec.rb` that exercise `feature_enabled?` resolution through `DiscussionTopicsController#show` under four distinct account/course flag-state combinations. New control-flow branches exercised: `allow_feature!` and `set_feature_flag!(STATE_DEFAULT_ON)` at root-account scope, `enable_feature!` and `disable_feature!` at course scope, and `reset_feature!` in the `before` hook. |
| Tests added or updated | `spec/controllers/discussion_topics_controller_spec.rb` — four examples added inside `context "feature-flag inheritance chain"` (inside `describe "GET 'show'"`): (1) Given root account `allow_feature!` and no course flag, GET show sets `discussion_thread_summarizer_enabled: false`. (2) Given root account `allow_feature!` and course `enable_feature!`, GET show sets key to `true`. (3) Given root account `set_feature_flag!(STATE_DEFAULT_ON)` and no course flag, GET show sets key to `true`. (4) Given root account `set_feature_flag!(STATE_DEFAULT_ON)` and course `disable_feature!`, GET show sets key to `false`. |
| Command | `docker compose exec web bundle exec rspec spec/controllers/discussion_topics_controller_spec.rb -e "feature-flag inheritance chain" --format documentation` |
| Outcome | Exit code 0; `4 examples, 0 failures` (finished in 8.52 seconds, seed 49388) |
| `QA Status` | `Pass` |
| PR / commit | [PR #59](https://github.com/ejgdr/canvas-lms/pull/59), squash-merged at `7d33f1254b216c3e49478530ae0a287cfd213664` |
| Trace to plan | FR-4 — the system must not generate, render, or call out to the summarization model when the feature is disabled for the account or course; these four examples are the living regression guard for the `discussion_thread_summarizer` inheritance chain. |

**First-run failure note.** The initial run produced 1 failure on example 4 ("account enables but course overrides to off"). Root cause: `enable_feature!` sets `STATE_ON`, which makes `can_override? = false`, causing the `lookup_feature_flag` loop to break at the account level and ignore the course's `STATE_OFF` flag entirely. Fix: changed both "account ON" examples (3 and 4) to use `set_feature_flag!(:discussion_thread_summarizer, Feature::STATE_DEFAULT_ON)`, which sets `allowed_on` and keeps `can_override? = true`. One retry performed after the fix; retry was not flake-driven (deterministic root cause), so it does not count as a flake retry under the QA agent guardrails. Second run: 4/4 pass.

---

## Cycle 5 — Observability scaffolding (issue #4, M1 Foundations)

| Field | Content |
|---|---|
| Slice | [#4](https://github.com/ejgdr/canvas-lms/issues/4) — "[M1] Observability scaffolding: InstStatsd counters for discussion thread summarizer." Branch `feat/m1-observability-scaffolding`. |
| Classification | Behavior-changing application code — `metrics.rb` introduces six new module methods with live `InstStatsd` calls; each is tested in `metrics_spec.rb`. The metric names and tag schemas are the observable behavior under test. |
| Tests added or updated | `spec/lib/discussion_thread_summarizer/metrics_spec.rb` (new file) — six examples, one per helper: (1) `increment_generation_attempt` emits `discussion_thread_summarizer.generation.attempt` with `account_id` and `scope_mode` tags. (2) `record_generation_latency` emits `discussion_thread_summarizer.generation.latency` via `timing` with `account_id` and `outcome` tags. (3) `increment_cache_hit` emits `discussion_thread_summarizer.cache.hit` with `account_id`. (4) `increment_cache_miss` emits `discussion_thread_summarizer.cache.miss` with `account_id`. (5) `increment_failure` emits `discussion_thread_summarizer.failure` with `account_id` and `reason`. (6) `increment_report_submission` emits `discussion_thread_summarizer.report.submission` with `account_id`, `reason_category`, and `reporter_role`. |
| Command | `docker compose exec web bundle exec rspec spec/lib/discussion_thread_summarizer/metrics_spec.rb --format documentation` |
| Outcome | Exit code 0; `6 examples, 0 failures` (finished in 0.78 seconds, seed 45989) |
| `QA Status` | `Pass` |
| PR / commit | [PR #60](https://github.com/ejgdr/canvas-lms/pull/60), squash-merged at `3f6c0fd1665dd0cb7bfcca0a31c802198f71cdbd` |
| Trace to plan | NFR-4 — metrics are required for generation latency (p50/p95/p99), cache hit rate, error rate by failure mode, daily generation count by account, and report submission count by reason category; these six helpers are the instrumentation layer that satisfies all five observability dimensions. |

**Spec pattern mirrored:** `allow(InstStatsd::Statsd).to receive(:distributed_increment).and_return(nil)` in a shared `before` block; `expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(metric_name, tags: {...})` per example. Source: `spec/lib/pandata_events_spec.rb` and `spec/graphql/mutations/update_discussion_entry_participant_spec.rb`. For the timing helper: `allow(InstStatsd::Statsd).to receive(:timing).and_return(nil)` + `have_received(:timing).with(name, value, tags: {...})`, mirroring `spec/integration/track_memory_and_cpu_spec.rb`.

---

## Cycle 6 — ModelClient interface and StubModelClient (issue #7, M2)

| Field | Content |
|---|---|
| Slice | [#7](https://github.com/ejgdr/canvas-lms/issues/7) — "[M2] Model-client interface with injectable stub." Branch `feat/m2-model-client-interface`. |
| Classification | Behavior-changing application code — `model_client.rb` introduces a runtime `raise NotImplementedError` path; `stub_model_client.rb` introduces observable return behavior. Both are directly exercised by the spec. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/model_client_spec.rb` (new file, 4 examples): (1) `ModelClient#summarize` raises `NotImplementedError` matching `/ModelClient#summarize must be implemented/`. (2) `StubModelClient` is a `ModelClient` subclass. (3) `StubModelClient#summarize` returns `FIXED_RESPONSE` unchanged for any payload. (4) `FIXED_RESPONSE` includes `:themes` (Array), `:viewpoints` (Array), `:open_questions` (Array), `:scope_mode` (String), anchoring the contract shape for future slices. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/model_client_spec.rb --format documentation` |
| Outcome | Exit code 0; `4 examples, 0 failures` (finished in 0.77 seconds, seed 58513) |
| `QA Status` | `Pass` |
| PR / commit | [PR #61](https://github.com/ejgdr/canvas-lms/pull/61), squash-merged at `a06f6118f1de` |
| Trace to plan | FR-1 (generate on demand) and NFR-5 (graceful degradation) — the abstract contract enforces that all model clients raise `TransportError` on failure, enabling uniform rescue in the service and job layers; the stub enables all failure-path tests in issues #13 and #14 without network access. §4.4 finding 8 (RubricLLMService as mockable model-client precedent). |

---

## Cycle 7 — Summarization service scaffold (issue #6, M2)

| Field | Content |
|---|---|
| Slice | [#6](https://github.com/ejgdr/canvas-lms/issues/6) — "[M2] Summarization service scaffold." Branch `feat/m2-summarization-service-scaffold`. |
| Classification | Behavior-changing application code — `summarization_service.rb` introduces a real call chain through `gather → pseudonymize → @client.summarize → validate → result`; all three private stubs are exercised in passing by the spec. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (new file, 3 examples): (1) The injected client receives `#summarize` with `hash_including(topic_id: 42)` (payload derivation). (2) The service returns the client's output unchanged in this skeleton (return-value pass-through). (3) An anonymous `ModelClient` subclass returning a distinct hash can be injected and its output flows through unchanged (dependency injection). |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; `3 examples, 0 failures` (finished in 0.73 seconds, seed 19569) |
| `QA Status` | `Pass` |
| PR / commit | [PR #62](https://github.com/ejgdr/canvas-lms/pull/62), squash-merged at `a9caeb3f7d40` |
| Trace to plan | FR-1 (generate on demand) and NFR-5 (graceful degradation) — the service is the only code path that calls the model client; centralising the call here ensures future error handling (TransportError rescue, metrics, cache) can all be added to one place without touching controllers or jobs. §4.4 finding 8 (AiExperiences::ConversationStartService as the namespaced service layout precedent). |

---

## Cycle 8 — Pseudonymization transform (issue #8, M2)

| Field | Content |
|---|---|
| Slice | [#8](https://github.com/ejgdr/canvas-lms/issues/8) — "[M2] Pseudonymization transform: replace author names with per-thread pseudonyms." Branch `feat/m2-pseudonymizer`. |
| Classification | Behavior-changing application code — `pseudonymizer.rb` introduces a live transform with observable output; `summarization_service.rb` now calls it in the pipeline. Both files' behavior is directly exercised by the specs. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/pseudonymizer_spec.rb` (new, 10 examples): (1) All real names replaced with pseudonyms. (2) Same author → same label (stability). (3) Distinct authors → distinct labels. (4) Body text unchanged. (5) `author_map` pairs real names → labels. (6) Empty input → empty result + empty map. (7) Single repeated author → one map entry. (8) First-seen order (Alice→A, Bob→B, Carol→C). (9) Exact format `"Author X"`. (10) Original entry hashes not mutated. `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified, +1 example): stubs `gather` to inject entries, asserts model client payload contains only pseudonymized `author_name` values. |
| Command (pseudonymizer) | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/pseudonymizer_spec.rb --format documentation` |
| Outcome (pseudonymizer) | Exit code 0; `10 examples, 0 failures` (finished in 1.45 seconds, seed 39280) |
| Command (service) | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome (service) | Exit code 0; `4 examples, 0 failures` (finished in 1.34 seconds, seed 54974) |
| `QA Status` | `Pass` |
| PR / commit | [PR #64](https://github.com/ejgdr/canvas-lms/pull/64), squash-merged at `3d35daafa68b` |
| Trace to plan | FR-5 — honor scope-limited content mode; pseudonymization is the prerequisite that ensures no real author identities reach the model client. The transform is correct regardless of whether `gather` has been updated to load real entries (no-op when `:entries` absent), satisfying the acceptance criterion "raw payloads containing original display names are never logged or persisted" at the service layer. |

---

## Cycle 9 — Scope-limited content filter (issue #9, M2)

| Field | Content |
|---|---|
| Slice | [#9](https://github.com/ejgdr/canvas-lms/issues/9) — "[M2] Scope-limited content filter (instructor + viewer posts only)." Branch `feat/m2-scope-limited-content-filter`. |
| Classification | Behavior-changing application code — `gather` now loads real `DiscussionEntry` records and conditionally filters them; the scope flag and the role-check logic introduce new observable branches. All branches are exercised by the spec. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified) — shared `before` block updated with gather-chain doubles to keep 4 pre-existing examples green; `context "gather pipeline"` block added with 6 new examples: (1) default mode includes all entries. (2) scope-limited excludes non-instructor/non-viewer. (3) scope-limited includes viewer's own entries. (4) viewer-who-is-instructor appears once (no duplication from Set union). (5) scope-limited with no instructor posts → only viewer's entries. (6) `order(:created_at)` is applied before filtering. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; `10 examples, 0 failures` (finished in 0.86 seconds, seed 15403) |
| `QA Status` | `Pass` |
| PR / commit | [PR #66](https://github.com/ejgdr/canvas-lms/pull/66), squash-merged at `1b7fe364de45` |
| Trace to plan | FR-5 — honor scope-limited content mode; the gather filter is the mechanism that ensures non-instructor student content is excluded from the model payload when institutional privacy requirements demand it. The `pluck(:user_id).to_set` role-check mirrors `DiscussionTopic::PromptPresenter#enrollments_by_user` (prompt_presenter.rb:116) but is cheaper: DB-side type filter avoids loading the full enrollment rows that PromptPresenter needs for student/instructor classification. |

---

## Cycle 10 — Output schema validator (issue #10, M2)

| Field | Content |
|---|---|
| Slice | [#10](https://github.com/ejgdr/canvas-lms/issues/10) — "[M2] Output schema validator: reject malformed model responses before caching." Branch `feat/m2-output-schema-validator`. |
| Classification | Behavior-changing application code — `OutputSchemaValidator` introduces live raise paths; `SummarizationService#summarize` gains a rescue block with metric emission. Both paths are directly exercised by specs. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/output_schema_validator_spec.rb` (new, 13 examples): valid pass (nil return + no raise), FIXED_RESPONSE regression, 4× missing key, 2× wrong type at key level, nested element type mismatch, MAX_ARRAY_LENGTH exceeded, MAX_STRING_LENGTH exceeded, MAX_SCOPE_MODE_LENGTH exceeded, non-Hash top-level guard. `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified, +2 examples in `context "schema validation"`): (1) malformed client → `SchemaViolationError` propagates; (2) malformed client → `Metrics.increment_failure` called with `reason: "schema_invalid"` and `account: root_account`. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/output_schema_validator_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; `25 examples, 0 failures` (finished in 1.39 seconds, seed 46290). First run: 1 failure (root_account double missing global_id stub). Second run after fix: 25/25. |
| `QA Status` | `Pass` |
| PR / commit | [PR #68](https://github.com/ejgdr/canvas-lms/pull/68), squash-merged at `32b38f84a55d` |
| Trace to plan | FR-8 (graceful degradation when summarization service unavailable) and NFR-5 (reliability) — the validator is the guard-before-persist pattern cited in the issue body (`DiscussionTopicInsight#validate_llm_response` at discussion_topic_insight.rb:167 as the Canvas precedent). AC #4 (metric emission on rejection) satisfied via service-layer rescue; validator stays a pure raise-on-invalid transform. |

**First-run failure note.** Example "propagates SchemaViolationError when the client returns malformed output" failed because the rescue block called `Metrics.increment_failure(account: root_account)` which internally calls `root_account.global_id`, and the `instance_double("Account")` had no `global_id` stub. Fix: added `global_id: 10_000_000_000_001` to the shared `let(:root_account)`. Not a flake — deterministic missing-stub error.

---

*Last verified: 2026-05-26 against commit 32b38f84a55d*
