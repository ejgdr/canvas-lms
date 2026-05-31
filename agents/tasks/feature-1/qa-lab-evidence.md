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

## Cycle 11 — Audit log emission (issue #12, M2)

| Field | Content |
|---|---|
| Slice | [#12](https://github.com/ejgdr/canvas-lms/issues/12) — "[M2] Audit log emission: LLMResponse-style record per generation attempt." Branch `feat/m2-audit-log-emission`. |
| Classification | Behavior-changing application code — `SummarizationService#summarize` gains an `ensure` block that emits an audit log on every invocation. Six new spec examples directly exercise the emit path under success, schema violation, transport error, unexpected exception, single-record invariant, and PII-guard conditions. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified) — shared `before` block updated with autoload trigger and logger stub; `let(:malformed_client)` hoisted to outer scope; `context "audit log emission"` added with 6 examples: (1) success → `success: true`, all 7 fields present; (2) schema violation → `success: false, error_category: "schema_invalid"`, re-raises; (3) transport error → `success: false, error_category: "transport_error"`, re-raises; (4) unexpected `StandardError` → `success: false, error_category: "unknown"`, re-raises; (5) exactly one logger call per attempt; (6) no raw entry content or author names in logged record. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; **18 examples, 0 failures** (finished in 1.17 seconds, seed 47643). First run: 1 failure (autoload race on `SchemaViolationError`). Second run after fix: 18/18. |
| `QA Status` | `Pass` |
| PR / commit | [PR #70](https://github.com/ejgdr/canvas-lms/pull/70), squash-merged at `f10558c656d7` |
| Trace to plan | NFR-2 (observability) — every outbound model call is logged with thread id, byte size, scope mode, model identifier, and latency. Raw payloads and author names are never logged. AC #1 (exactly one record per attempt regardless of outcome) guaranteed by `ensure`; AC #2 (`success: false` on any failure) guaranteed by `$!` global in `ensure`. |

**First-run failure note.** Example "schema violation emits audit record…" failed with `NameError: uninitialized constant DiscussionThreadSummarizer::SchemaViolationError`. Root cause: RSpec evaluates `raise_error(SomeClass)` as an argument before the block runs, so the constant must already be loaded. Zeitwerk hadn't lazy-loaded `output_schema_validator.rb` yet because the audit-log "schema violation" example ran before any example that called `OutputSchemaValidator.call`. Fix: added `DiscussionThreadSummarizer::OutputSchemaValidator` reference to the shared `before` block to force autoload before any example evaluates the constant. Not a flake — deterministic load-order dependency.

---

## Cycle 12 — Async summarization background job (issue #11, M2)

| Field | Content |
|---|---|
| Slice | [#11](https://github.com/ejgdr/canvas-lms/issues/11) — "[M2] Async summarization background job (delay with singleton + n_strand)." Branch `feat/m2-async-summarization-job`. |
| Classification | Behavior-changing application code — `SummarizationService.enqueue_for` introduces a new public class method that exercises `Delayed::HIGH_PRIORITY`, a topic-scoped singleton key, and an n_strand region key. All four new spec examples are directly behaviour-covering. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified, +4 examples in `describe ".enqueue_for"`): (1) Dispatches with `HIGH_PRIORITY`, singleton `"discussion_thread_summarizer:generation_for_topic:42"`, n_strand containing the region; (2) chains `.summarize` on the delay proxy with `discussion_topic:` and `viewer:` kwargs; (3) singleton key encodes `topic.id` (same topic → same key); (4) distinct topic ids → distinct singleton keys. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; `22 examples, 0 failures` (finished in 1.39 seconds, seed 44441) |
| `QA Status` | `Pass` |
| PR / commit | [PR #72](https://github.com/ejgdr/canvas-lms/pull/72), squash-merged at `5d71ab9c955ecd407470cfcf9b2f83f94ed850f6` |
| Trace to plan | FR-1 (generate on demand, not blocking the request) — `enqueue_for` is the async dispatch point. The singleton key per `discussion_topic.id` prevents duplicate jobs for the same thread, satisfying the concurrency-safety requirement. `HIGH_PRIORITY` matches the `insight_generation` precedent, keeping summary jobs in the same queue tier as insight generation. |
| Board transitions | In Progress → Done at 2026-05-27T02:27Z; QA Status Pending → Pass at 2026-05-27T02:27Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9HE`) |

---

## Cycle 13 — Cross-cutting pipeline seam unit tests (issue #13, M2)

| Field | Content |
|---|---|
| Slice | [#13](https://github.com/ejgdr/canvas-lms/issues/13) — "[M2] Unit tests: summarization service (pseudonymization, scope filter, schema validation, ...)." Branch `test/m2-summarization-service-consolidation-unit-tests`. |
| Classification | Behavior-changing (spec-only) — 4 new examples directly covering cross-cutting seam behaviors. `transport_client` hoisted from inner context to outer scope. No production code changes. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified, +4 examples in `context "cross-cutting pipeline seams"`): (1) Scope-limited filter + pseudonymize + validate fire together in one `summarize` call; client receives only teacher+viewer entries with pseudonymized names. (2) Scope-limited + malformed client: `Metrics.increment_failure` and audit `success: false, error_category: "schema_invalid"` both fire in same call. (3) Transport error: `Metrics.increment_failure` NOT emitted — first explicit negative assertion for this path. (4) Idempotence: repeated `summarize` calls with identical inputs produce identical payloads to client. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; `26 examples, 0 failures` (finished in 1.35 seconds, seed 30855). First run: all green. |
| `QA Status` | `Pass` |
| PR / commit | [PR #75](https://github.com/ejgdr/canvas-lms/pull/75), squash-merged at `756c7d4422c7f7b49585c318282d47c564a6d7c8` |
| Trace to plan | FR-1 (generate on demand) and FR-5 (scope-limited mode) — the seam tests are the living regression guard for the combined filter → pseudonymize → validate path. AC3 cache-write tail and AC4 deferred to M3 (slice #16); no production code required for the 4 examples added here. |
| Board transitions | In Progress → Done at 2026-05-27T02:41Z; QA Status Pending → Pass at 2026-05-27T02:41Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9IQ`) |

---

## Cycle 14 — Async pipeline integration tests (issue #14, M2)

| Field | Content |
|---|---|
| Slice | [#14](https://github.com/ejgdr/canvas-lms/issues/14) — "[M2] Integration test: background job enqueues on thread open and produces valid output." Branch `test/m2-async-integration`. |
| Classification | Behavior-changing (spec-only) — new spec file with 3 integration examples using real AR fixtures. No production code changes. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb` (new, 3 examples): (1) `enqueue_for` creates exactly one Delayed::Job with correct singleton key; (2) second `enqueue_for` for same topic is a no-op — real DB singleton dedup; (3) job runs end-to-end: audit log `success: true`, `Metrics.increment_failure` not called. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb --format documentation` |
| Outcome | Exit code 0; `3 examples, 0 failures` (14.23 seconds, seed 16860). First run: 1 failure (Delayed::Worker non-JSON log line captured as last entry). Fixed by filtering for `"generation_attempt"`. Second run: 3/3. |
| `QA Status` | `Pass` |
| PR / commit | [PR #78](https://github.com/ejgdr/canvas-lms/pull/78), squash-merged at `3464a8953cb1002113c6145b01c640740bf25797` |
| Trace to plan | FR-1 (generate on demand) — the integration test is the living proof that the M2 async pipeline is end-to-end functional: enqueue_for → Delayed Job → SummarizationService#summarize → StubModelClient → audit log. AC2 (DiscussionTopicSummary record) deferred to M3 slice #16. |
| Board transitions | In Progress → Done at 2026-05-27T03:21Z; QA Status Pending → Pass at 2026-05-27T03:21Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9JE`) |

---

---

## Cycle 15 — Content-version hash for cache keying (issue #15, M3)

| Field | Content |
|---|---|
| Slice | [#15](https://github.com/ejgdr/canvas-lms/issues/15) — "[M3] Content-version hash computation for cache keying." Branch `feat/m3-content-version-hash`. |
| Classification | New application code — new pure utility class `DiscussionThreadSummarizer::ContentVersionHash`. No changes to any existing file. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/content_version_hash_spec.rb` (new, 9 DB-backed examples): (1) 64-char hex format; (2) determinism — same topic state twice → equal hashes; (3) empty topic → deterministic non-nil hash; (4) two different topics → different hashes; (5) new entry added → hash changes; (6) soft-delete excluded from active scope → hash changes; (7) soft-deleting only entry → hash equals empty-topic hash; (8) message edit via `update_column` → hash changes; (9) nil topic → `ArgumentError`. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/content_version_hash_spec.rb --format documentation` |
| Outcome | Exit code 0; **9 examples, 0 failures** (finished in 7.82 seconds, seed 28253). First run: all green. |
| `QA Status` | `Pass` |
| PR / commit | [PR #81](https://github.com/ejgdr/canvas-lms/pull/81), squash-merged at `dfa1bd32b0406005cb2086d161e7e96e44d16121` |
| Trace to plan | FR-2 (cache and invalidate summaries on meaningful thread change) — `ContentVersionHash` is the deterministic key that #16 (cache write) and #17 (invalidation) will consume. The hash changes on entry add, soft-delete, or message edit; it is stable for identical topic state across process restarts (Digest::SHA256, not Object#hash). No user identity → no per-viewer cache fragmentation. |
| Board transitions | Todo → Done: 2026-05-27T17:35:18Z (auto-closed by PR #81 merge); QA Status Pending → Pass: 2026-05-27T17:38:26Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9Jk`) |

---

---

## Cycle 16 — Cache read/write in summarization pipeline (issue #16, M3)

| Field | Content |
|---|---|
| Slice | [#16](https://github.com/ejgdr/canvas-lms/issues/16) — pipeline-only cache read/write (render-path ACs in [#84](https://github.com/ejgdr/canvas-lms/issues/84)). |
| Tests added or updated | 9 DB-backed examples in `describe "DiscussionThreadSummarizer::SummarizationService#fetch_or_create_summary"` (hit, miss, miss-then-hit, two-topic isolation, locale-distinct, hash equality, result parity, cache.hit, cache.miss); integration example 3 asserts one `DiscussionTopicSummary` with expected hash after `run_jobs`. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb --format documentation` |
| Outcome | Exit code 0; **38 examples, 0 failures** (13.63 seconds, seed 60703). |
| `QA Status` | `Pass` |
| PR / commit | [PR #86](https://github.com/ejgdr/canvas-lms/pull/86), squash-merged at `1f8256d4682c801efd00365ca89d9e417dd17096` |
| Notes | 4-tuple WHERE (locale separate from hash). scope_limited backlog [#85](https://github.com/ejgdr/canvas-lms/issues/85). `#summarize` public convergence deferred. |
| Board transitions | Done 2026-05-27T18:18:04Z; QA Pass 2026-05-27T18:19:19Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9J8`) |

---

## Cycle 17 — Cache invalidation hooks + meaningful-change threshold (issue #17, M3)

| Field | Content |
|---|---|
| Slice | [#17](https://github.com/ejgdr/canvas-lms/issues/17) — "[M3] Cache invalidation hooks + meaningful-change threshold." Branch `feat/m3-invalidation-hooks`. |
| Classification | Behavior-changing application code — `CacheInvalidation` service + `DiscussionEntry` after_create/after_save hooks + invalidation metrics. |
| Hygiene | *Last verified* stamp in both evidence files references Cycle 16 impl SHA `1f8256d4682c801efd00365ca89d9e417dd17096`. #84 reopened (was Closed unintentionally post–Cycle 16). |
| Tests added or updated | `spec/services/discussion_thread_summarizer/cache_invalidation_spec.rb` (new, 10 examples): create → `invalidation.fired` cause create; above-threshold edit → fired cause edit, stale hash preserved; below-threshold edit → `skipped_below_threshold` + rekey; soft-delete → fired cause delete; editor_id-only → no invalidation metrics; flag off → no metrics/rekey; below-threshold rekey → `fetch_or_create_summary` :hit; soft-delete on `destroy`; rekey → no `summarize`/job; multi-locale rekey. `spec/lib/discussion_thread_summarizer/metrics_spec.rb` (+2 invalidation metric examples). |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/cache_invalidation_spec.rb spec/lib/discussion_thread_summarizer/metrics_spec.rb --format documentation` |
| Outcome | Exit code 0; **18 examples, 0 failures** (8.13 seconds, seed 43247). |
| `QA Status` | `Pass` |
| PR / commit | [PR #89](https://github.com/ejgdr/canvas-lms/pull/89), squash-merged at `3db30731b6ece2d75408ad331c6ec0a84fac00e4` |
| Trace to plan | FR-2 — invalidate summaries on meaningful thread change; below-threshold edits rekey without regeneration per re-scoped #17 AC. |
| Board transitions | Done 2026-05-27T19:40:51Z; QA Pass 2026-05-27T19:42:19Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9Kc`) |

---

## Cycle 18 — Regeneration rate limiter (issue #18, M3)

| Field | Content |
|---|---|
| Slice | [#18](https://github.com/ejgdr/canvas-lms/issues/18) — "[M3] Regeneration rate limiter." Branch `feat/m3-rate-limiter`. |
| Classification | Behavior-changing application code — `RegenerationRateLimiter.check` + `fetch_or_create_summary` miss-path gate + three `rate_limit.*` metrics. |
| Hygiene | *Last verified* stamp for Cycle 18 row references impl merge `aed2b119be5eb1c895b0c6cc6dad64fd1c5e8011`. [#18](https://github.com/ejgdr/canvas-lms/issues/18) re-scoped pipeline-only before branch; InstLLMHelper fail-closed posture matched at `inst_llm_helper.rb:41`. |
| Tests added or updated | `spec/services/discussion_thread_summarizer/regeneration_rate_limiter_spec.rb` (new, 10 unit + 1 skip): cooldown deny; two threads / two users allowed; quota deny + DECR rollback; cooldown TTL via `travel_to`; UTC day boundary; rekey → no Redis `set`/`incr`; flag off; cooldown-before-quota (no INCR on cooldown deny); rollback parity; Redis-disabled raise. `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (+3): `:rate_limited` on cooldown/quota deny without `summarize`; `rate_limit.allowed` before summarize. |
| Command | `docker compose run --rm web bin/rspec spec/services/discussion_thread_summarizer/regeneration_rate_limiter_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; **50 examples, 0 failures, 1 skipped** (15.09 s, seed 1; also seeds 13659, 511). |
| `QA Status` | `Pass` |
| PR / commit | [PR #92](https://github.com/ejgdr/canvas-lms/pull/92), squash-merged at `aed2b119be5eb1c895b0c6cc6dad64fd1c5e8011` |
| Trace to plan | FR-7 — rate-limit regeneration; pipeline deny contract (`:rate_limited`) for #84 render-path to consume; rekey path (Cycle 17) must not consume budget. |
| Board transitions | Done 2026-05-27T21:00:05Z; QA Pass 2026-05-27T21:00:16Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9LM`) |
| Spec-idiom note | `Time.utc` required instead of `Time.zone.utc` for `travel_to` anchors (fixed after initial failures). |

*Last verified (Cycle 18 row): 2026-05-27 against squash-merge `aed2b119be5eb1c895b0c6cc6dad64fd1c5e8011`*

---

## Cycle 19 — Render-path lookup + GET endpoint (issue #84, M3)

| Field | Content |
|---|---|
| Slice | [#84](https://github.com/ejgdr/canvas-lms/issues/84) — "[M3] Thread render-path API: stale-aware lookup + render states." Branch `feat/m3-render-lookup`. |
| Classification | Behavior-changing application code — `lookup_for_render`, `RegenerationRateLimiter.preview`, GET `thread_summary`, render metrics. |
| Hygiene | *Last verified* for Cycle 18 row confirmed at `aed2b119be5eb1c895b0c6cc6dad64fd1c5e8011` (no backfill needed). Pre-branch: #84 re-scoped API-only; #95 UI + #96 index backlog filed. |
| Tests added or updated | `regeneration_rate_limiter_spec.rb` (+3 `.preview`); `summarization_service_spec.rb` (+7 `lookup_for_render` in top-level `describe`); `discussion_topics_api_controller_spec.rb` (+3 `thread_summary`); `integration/render_lookup_spec.rb` (new, 1 example: `:generating` → enqueue → job → `:current`). |
| Command | `docker compose run --rm web bin/rspec spec/services/discussion_thread_summarizer/regeneration_rate_limiter_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb spec/controllers/discussion_topics_api_controller_spec.rb spec/services/discussion_thread_summarizer/integration/render_lookup_spec.rb --seed 1` |
| Outcome | Exit code 0; **141 examples, 0 failures, 3 pending** (~1m15s, seed 1). |
| `QA Status` | `Pass` |
| PR / commit | [PR #97](https://github.com/ejgdr/canvas-lms/pull/97), squash-merged at `92e6d7dde058bab1050a6226ec3509996c324752` |
| Trace to plan | FR-1 render API contract; completes M3 (#15–#18 + #84). Blocks #95 UI unblocked post-merge. |
| Board transitions | Closed 2026-05-27T23:11:26Z; Done 2026-05-27T23:12:12Z; QA Pass 2026-05-27T23:12:39Z (item `PVTI_lAHOBQJOSM4BWez_zgt_o0A` / id `192914240`) |
| Spec-idiom note | `lookup_for_render` specs must use `describe DiscussionThreadSummarizer::SummarizationService` — not nested string-describe — so `described_class::LLM_CONFIG_VERSION` resolves. |
| Singleton-key note | `enqueue_for` singleton topic-id only; multi-locale requests collapse to one job — handoff to #95 / #21. |

*Last verified (Cycle 19 row): 2026-05-27 against squash-merge `92e6d7dde058bab1050a6226ec3509996c324752`*

---

## Cycle 20 — Cache observability metrics (issue #20, M3 close-out)

| Field | Content |
|---|---|
| Slice | [#20](https://github.com/ejgdr/canvas-lms/issues/20) — M3 observability gap-fill. Branch `feat/m3-cache-observability`. |
| Tests added or updated | `metrics_spec.rb` (+2): `cache.stale`, `cache.invalidated`. `summarization_service_spec.rb` (+3): flag-off pipeline gate; lookup `:stale` / `:rate_limited_stale` → `cache.stale`. `cache_invalidation_spec.rb` (+2): `reply_create`, `reply_delete` triggers. |
| Command | `docker compose run --rm web bin/rspec spec/lib/discussion_thread_summarizer/metrics_spec.rb spec/services/discussion_thread_summarizer/cache_invalidation_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb --seed 1` |
| Outcome | **66 examples, 0 failures** (~21.12 s, seed 1). |
| `QA Status` | `Pass` |
| PR / commit | [PR #100](https://github.com/ejgdr/canvas-lms/pull/100), squash-merged at `758f583b07e572e165f8f8f66792c83a36956420` |
| Board transitions | Closed 2026-05-27T23:35:20Z; Done 2026-05-27T23:35:21Z; QA Pass 2026-05-27T23:36:03Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9NY`) |
| Flag-gate note | Returns `:rate_limited` without limiter/metrics when flag off — documented in implementation evidence (no enum extension). |

*Last verified (Cycle 20 row): 2026-05-27 against squash-merge `758f583b07e572e165f8f8f66792c83a36956420`*

---

## Cycle 21 — M3 unit-test consolidation (issue #19)

| Field | Content |
|---|---|
| Slice | [#19](https://github.com/ejgdr/canvas-lms/issues/19) — test consolidation. Branch `feat/m3-test-consolidation`. |
| Classification | Test-only — `m3_invariants_spec.rb` (6 examples). No production code. |
| Hygiene | Lens A re-scope on #19 before branch; #95 `milestone:M3` → `milestone:M4`. |
| Tests added | `spec/services/discussion_thread_summarizer/m3_invariants_spec.rb` (new, 179 lines): AC index comment; hash stability; word-delta invalidation/rekey; cooldown E2E with Redis stubs; post-TTL summarize. |
| Command (targeted) | `docker compose run --rm web bin/rspec spec/services/discussion_thread_summarizer/m3_invariants_spec.rb` |
| Outcome (targeted) | **6 examples, 0 failures** (~6.27 s, seed 40363). |
| Command (regression) | `docker compose run --rm web bin/rspec spec/services/discussion_thread_summarizer/ spec/lib/discussion_thread_summarizer/` |
| Outcome (regression) | **127 examples, 0 failures, 1 pending** (~44.94 s, seed 8371). |
| `QA Status` | `Pass` |
| PR / commit | [PR #103](https://github.com/ejgdr/canvas-lms/pull/103), squash-merged at `1d535bafdca18a58c6103029e9904313430f4c81` |
| Board transitions | Closed 2026-05-28T00:10:10Z; Done 2026-05-28T00:10:12Z; QA Pass 2026-05-28T00:10:42Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9M8` / `183104719`) |
| AC bullet-2 note | Lens A: pre-implementation wording; shipped hash is full entry-set; threshold is invalidation/rekey only. |

*Last verified (Cycle 21 row): 2026-05-28 against squash-merge `1d535bafdca18a58c6103029e9904313430f4c81`*

---

## Cycle 22 — M4 thread summary UI (issue #95)

| Field | Content |
|---|---|
| Slice | [#95](https://github.com/ejgdr/canvas-lms/issues/95) — `ThreadSummaryBlock`. Branch `feat/m4-thread-summary-ui`. |
| Classification | New React UI — `GET thread_summary` consumer with polling hook; no backend changes. |
| Hygiene | #95 re-scoped; #22 closed duplicate before branch; M4 audit unchanged (8 issues). |
| Tests added | `ThreadSummaryBlock.test.tsx` (7 RTL+MSW), `formatThreadSummary.test.ts` (2), `useThreadSummary.test.ts` (3 poll-interval). |
| Command (targeted) | `yarn test ui/features/discussion_topics_post/react/components/ThreadSummaryBlock` |
| Outcome (targeted) | **12 examples, 0 failures** (~10.6 s, seed `1779928118029`). |
| Command (regression) | `yarn test ui/features/discussion_topics_post/` |
| Outcome (regression) | **776 passed, 3 skipped** (~366.9 s). |
| `QA Status` | `Pass` |
| PR / commit | [PR #106](https://github.com/ejgdr/canvas-lms/pull/106), squash-merged at `186a92f5e4231065a29f187e805d128eb30b6dcf` |
| Board transitions | Closed 2026-05-28T01:02:05Z; Done 2026-05-28T01:02:43Z; QA Pass 2026-05-28T01:02:59Z (item `PVTI_lAHOBQJOSM4BWez_zgt__hA` / `192937488`) |
| Diff cap | **623 vs 500 hard** — overage surfaced; 282 lines test overhead. |

*Last verified (Cycle 22 row): 2026-05-28 against squash-merge `186a92f5e4231065a29f187e805d128eb30b6dcf`*

---

## Cycle 24 — Additive summary fields (issue #21)

| Field | Content |
|---|---|
| Slice | [#21](https://github.com/ejgdr/canvas-lms/issues/21) — additive `summary` on DiscussionTopic REST `show`/`view` and GraphQL `Discussion.summary`. Branch `feat/m4-topic-summary-embed`. |
| Classification | Behavior-changing application code — Ruby REST/GraphQL embed wiring + controller/GraphQL specs. |
| Tests added / extended | `spec/controllers/discussion_topics_api_controller_spec.rb` (`thread summary embed on show`, `thread summary embed on view`); `spec/graphql/types/discussion_type_spec.rb` (`thread summary embed`). |
| Command (targeted) | `docker compose exec web bundle exec rspec spec/controllers/discussion_topics_api_controller_spec.rb -e "thread summary embed" spec/graphql/types/discussion_type_spec.rb -e "thread summary embed"` |
| Outcome (targeted) | **16 examples, 0 failures** (~18.14 s, seed `63338`). |
| Matrix covered | REST show/view + GraphQL: flag off (omit key / null + shape stability); cached `current`/`stale`; `generating` object; not started (`rate_limited_empty` → null, no job). |
| `QA Status` | `Pass` (recorded here; board field update deferred to Cycle 24 completion PR) |
| PR / commit | [PR #112](https://github.com/ejgdr/canvas-lms/pull/112), squash-merged at `132427903290b7c65b81a947daa2965e0f0c4ed9` on 2026-05-30T20:06:56Z |
| Trace to plan | FR embed on topic payload; reuses `discussion_thread_summarizer` flag and `SummarizationService#lookup_for_render`. |

*Last verified (Cycle 24 row): 2026-05-30T20:07:30Z against squash-merge `132427903290b7c65b81a947daa2965e0f0c4ed9`*

---

## Cycle 25 — Integration test: summary response shapes (issue #25)

| Field | Content |
|---|---|
| Slice | [#25](https://github.com/ejgdr/canvas-lms/issues/25) — smoke integration tests for additive `summary` on REST `show` and GraphQL `Discussion.summary`. Branch `feat/m4-summary-shape-integration-tests`. |
| Classification | Test-only slice — extends coverage through `api_call` + `CanvasSchema.execute` integration paths. |
| Tests added / extended | `spec/apis/v1/discussion_thread_summary_shape_spec.rb` (8 examples: REST GET show + GraphQL `Discussion.summary`). |
| Command (targeted) | `docker compose run --rm web bin/rspec spec/apis/v1/discussion_thread_summary_shape_spec.rb --format documentation` |
| Outcome (targeted) | **8 examples, 0 failures** (~9.05 s, seed `33354`). |
| Matrix covered | REST + GraphQL: flag off (omit key / null + shape stability); cached `current`; not started (`rate_limited_empty` → null). |
| `QA Status` | `Pass` (board field updated via GraphQL before impl merge) |
| PR / commit | [PR #115](https://github.com/ejgdr/canvas-lms/pull/115), squash-merged at `2bb202a6191261d82971bc464b87d4efdf5f115a` on 2026-05-31T04:55:21Z |
| Trace to plan | FR-4 toggle honor; M4 testing story; depends on #21 embed surfaces. |

*Last verified (Cycle 25 row): 2026-05-31T04:55:21Z against squash-merge `2bb202a6191261d82971bc464b87d4efdf5f115a`*

---

## Cycle 26 — Generation latency metrics (issue #27)

| Field | Content |
|---|---|
| Slice | [#27](https://github.com/ejgdr/canvas-lms/issues/27) — InstStatsd generation metrics from async summarization job. Branch `feat/m4-generation-latency-metrics`. |
| Classification | Behavior-changing application code — observability wiring in `SummarizationService` + `Metrics` helper rename/align to issue AC. |
| Tests added / extended | `spec/lib/discussion_thread_summarizer/metrics_spec.rb` (3 generation helpers); `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (`generation latency metrics (#27)`, 4 examples). |
| Command (targeted) | `docker compose run --rm web bin/rspec spec/lib/discussion_thread_summarizer/metrics_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb -e "generation latency metrics"` |
| Outcome (targeted) | **15 examples, 0 failures** (11 metrics file + 4 service subset, seed `62572`, ~4.49 s service block). |
| Matrix covered | Completed cache-miss job → attempt + latency; cache hit → no generation metrics; rate limit deny → no generation metrics; schema failure → error without latency. |
| `QA Status` | `Pass` (board field updated via GraphQL before impl merge) |
| PR / commit | [PR #118](https://github.com/ejgdr/canvas-lms/pull/118), squash-merged at `f1d9a391efe892dcfff6b99d964cf7443b7e128e` on 2026-05-31T05:12:14Z |
| Trace to plan | NFR-4 latency metrics; M4 observability; blocks #50 dashboard aggregation. |

*Last verified (Cycle 26 row): 2026-05-31T05:12:14Z against squash-merge `f1d9a391efe892dcfff6b99d964cf7443b7e128e`*

---

## Cycle 27 — Regenerate + cooldown UX + backend endpoint (issues #23, #121)

| Field | Content |
|---|---|
| Slice | [#23](https://github.com/ejgdr/canvas-lms/issues/23) frontend regenerate UX + [#121](https://github.com/ejgdr/canvas-lms/issues/121) backend `POST .../thread_summary/regenerate`. Branch `feat/m4-regenerate-cooldown-ux`. |
| Classification | Behavior-changing application code — React regenerate button + Ruby regenerate route/service (paired; Cycle 23 #24+#26 precedent). |
| Tests added / extended | `ThreadSummaryBlock.test.tsx` (+4 regenerate/cooldown/quota); `formatRegenerationCooldown.test.ts` (new, 4); `discussion_topics_api_controller_spec.rb` (+5 regeneration metadata + POST regenerate). |
| Command (JS) | `docker compose run --rm web yarn test ui/features/discussion_topics_post/react/components/ThreadSummaryBlock/__tests__/formatRegenerationCooldown.test.ts ui/features/discussion_topics_post/react/components/ThreadSummaryBlock/__tests__/ThreadSummaryBlock.test.tsx --run` |
| Outcome (JS) | **14 examples, 0 failures** (seed `1780205921983`, ~9.25 s). |
| Command (Ruby) | `docker compose run --rm web bin/rspec spec/controllers/discussion_topics_api_controller_spec.rb -e "thread_summary (Discussion Thread Summarizer)" -e "regenerate_thread_summary"` |
| Outcome (Ruby) | **11 examples, 0 failures** (seed `17098`, ~11.6 s). |
| Matrix covered | Regenerate success → generating + poll; cooldown `aria-disabled` + no POST; POST 429 cooldown; quota inline alert; GET `regeneration` metadata; POST enqueue / 429 cooldown / 429 quota. |
| `QA Status` | `Pass` (board field update on completion PR) |
| PR / commit | [PR #122](https://github.com/ejgdr/canvas-lms/pull/122), squash-merged at `640992dc379987df3721f7443d3dbf5cec3d6c2e` on 2026-05-31T05:37:48Z |
| Trace to plan | FR-7 rate-limit regeneration UX; M4 per-thread summary surface (final slice). |

*Last verified (Cycle 27 row): 2026-05-31T05:39:00Z against squash-merge `640992dc379987df3721f7443d3dbf5cec3d6c2e`*

---

*Last verified: 2026-05-28 against squash-merge 186a92f5e4231065a29f187e805d128eb30b6dcf*

---

## Cycle 24 — Additive summary fields (issue #21)

| Field | Content |
|---|---|
| Slice | [#21](https://github.com/ejgdr/canvas-lms/issues/21) — additive `summary` on DiscussionTopic REST `show`/`view` and GraphQL `Discussion.summary`. Branch `feat/m4-topic-summary-embed`. |
| Classification | Behavior-changing application code — Ruby REST/GraphQL embed wiring + controller/GraphQL specs. |
| Tests added / extended | `spec/controllers/discussion_topics_api_controller_spec.rb` (`thread summary embed on show`, `thread summary embed on view`); `spec/graphql/types/discussion_type_spec.rb` (`thread summary embed`). |
| Command (targeted) | `docker compose exec web bundle exec rspec spec/controllers/discussion_topics_api_controller_spec.rb -e "thread summary embed" spec/graphql/types/discussion_type_spec.rb -e "thread summary embed"` |
| Outcome (targeted) | **16 examples, 0 failures** (~18.14 s, seed `63338`). |
| Matrix covered | REST show/view + GraphQL: flag off (omit key / null + shape stability); cached `current`/`stale`; `generating` object; not started (`rate_limited_empty` → null, no job). |
| `QA Status` | `Pass` (recorded here; board field update deferred to Cycle 24 completion PR) |
| PR / commit | [PR #112](https://github.com/ejgdr/canvas-lms/pull/112), squash-merged at `132427903290b7c65b81a947daa2965e0f0c4ed9` on 2026-05-30T20:06:56Z |
| Trace to plan | FR embed on topic payload; reuses `discussion_thread_summarizer` flag and `SummarizationService#lookup_for_render`. |

*Last verified (Cycle 24 row): 2026-05-30T20:07:30Z against squash-merge `132427903290b7c65b81a947daa2965e0f0c4ed9`*
