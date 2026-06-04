# Feature-1 Implementation Evidence

This file records completed slice cycles for the Discussion Thread Summarizer feature. Each entry is written only on successful merge plus Done board transition, per the agent spec in `agents/feature-implementation.md`.

## Cycle 1 — Feature flag declaration (M1 Foundations)

**Slice.** Declare the `discussion_thread_summarizer` feature flag in `config/feature_flags/`, plus a companion shadow flag at the root-account scope. This is the M1 root story: every downstream slice in the project plan gates on the flag existing, so it ships first.

**Issue.** [#1](https://github.com/ejgdr/canvas-lms/issues/1) — "[M1] Declare discussion_thread_summarizer feature flag." Linked to FR-4 in `agents/tasks/feature-1/implementation-research.md` (the system must not generate, render, or call out to the summarization model when the feature is disabled). No `Blocked by` dependencies on this item.

**Pull request.** [#54](https://github.com/ejgdr/canvas-lms/pull/54) — `feat(feature-flags): add discussion_thread_summarizer flag`. One file changed, 19 insertions, 0 deletions. The new file `config/feature_flags/discussion_thread_summarizer.yml` mirrors the precedent file `config/feature_flags/discussion_summary.yml` cited in §4.4 of the research package:

- Primary flag: `state: allowed`, `applies_to: Course`, `root_opt_in: true`.
- Companion shadow flag `discussion_thread_summarizer_with_cedar`: `state: hidden`, `applies_to: RootAccount`, `shadow: true`.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-17T03:40:20Z | Todo → In Progress | MCP update on project item id `183104452` |
| 2026-05-17T03:50:29Z | In Progress → Done | MCP update on project item id `183104452` |

**Merge evidence.** PR #54 was squash-merged into `master` at commit `fb2736d9b3abd45e573dc865a52dcb7552eecc4f`. Issue #1 was auto-closed by the `Closes #1` line in the PR body, removing the need for a manual close.

**Local verification.** YAML syntax was validated on the working clone before push. Ruby is not installed on the development host, so the equivalent parse was run with Python's `yaml` module. The file parses successfully and both flag entries are well-formed mappings.

**Trace to plan.** This slice executes the first M1 — Foundations item in `agents/tasks/feature-1/implementation-research.md` §6.1 and the corresponding root story on the project board at https://github.com/users/ejgdr/projects/1. The §4.4 codebase finding — the `discussion_summary.yml` precedent — defined the file path and shape; the only deviations from the precedent are the flag names themselves, deliberately distinct to avoid collision with the upstream `discussion_summary` feature. With the flag now on `master`, every downstream slice (summarization service, cache layer, per-thread UI surface, instructor digest, privacy controls) can reference `course.feature_enabled?(:discussion_thread_summarizer)` and the dependency chain in §6.2 of the research package is unblocked.

---

## Cycle 2 — Toggle UI plumbing (M1 Foundations)

**Slice.** Wire the `discussion_thread_summarizer` feature flag into the account and course feature settings UI by (a) adding `environments` overrides for development and CI to the YAML so developers can exercise the feature without a manual admin toggle, and (b) adding `discussion_thread_summarizer_enabled` to the js_env hash in `DiscussionTopicsController#show` so the resolved flag state is visible to the frontend. No summary block or digest tab is rendered — those are M4 and M5 work.

**Issue.** [#2](https://github.com/ejgdr/canvas-lms/issues/2) — "[M1] Account- and course-level feature toggle UI plumbing." Linked to FR-4 in `agents/tasks/feature-1/implementation-research.md` (the system must not generate, render, or call out to the summarization model when the feature is disabled for the account or course). Dependency on #1 was resolved by Cycle 1.

**Pull request.** [#56](https://github.com/ejgdr/canvas-lms/pull/56) — `feat(feature-flags): wire toggle UI plumbing for discussion_thread_summarizer`. Three files changed, 26 insertions:

- `config/feature_flags/discussion_thread_summarizer.yml` — 5 lines: `environments` block (`development: state: allowed_on`, `ci: state: allowed_on`).
- `app/controllers/discussion_topics_controller.rb` — 1 line: `discussion_thread_summarizer_enabled: @context.is_a?(Course) && @context.feature_enabled?(:discussion_thread_summarizer)` in the `show` js_env hash, following the `discussion_pin_post` precedent adjacent to it.
- `spec/controllers/discussion_topics_controller_spec.rb` — 20 lines: two examples in `describe "GET 'show'"` verifying the on/off ENV values.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-21T22:30:32Z | Todo → In Progress | MCP update on project item id `183104517` |
| 2026-05-21T22:31:07Z | QA Status set to Pending | MCP update on project item id `183104517` |
| 2026-05-21T22:48:20Z | QA Status → Pass | MCP update on project item id `183104517` |
| 2026-05-21T22:49:55Z | In Progress → Done | MCP update on project item id `183104517` |

**Merge evidence.** PR #56 was squash-merged into `master` at commit `efd2722a9b689ca3bf12ca0d91534c0f77fbabd9`. Issue #2 was auto-closed by the `Closes #2` line in the PR body.

**Local verification.** Two RSpec examples in `spec/controllers/discussion_topics_controller_spec.rb` run via `bundle exec rspec spec/controllers/discussion_topics_controller_spec.rb --example "discussion_thread_summarizer_enabled" --format documentation`. Exit code 0, 2 examples, 0 failures (6.58 seconds). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 2.

**Trace to plan.** This slice executes the second M1 — Foundations story in `agents/tasks/feature-1/implementation-research.md` §6.1. The §4.4 codebase finding — the controller ENV pattern for `discussion_pin_post` and the `environments` pattern from `outcomes_feature_flags.yml` — defined both change sites. The `@context.is_a?(Course)` guard is a direct expression of the flag's `applies_to: Course` scope; group discussions, where `@context` is a Group, are explicitly outside feature scope per §2 scope boundaries and return `false` without reaching `feature_enabled?`. With `discussion_thread_summarizer_enabled` now on `master`, every M4 and M5 component can gate its rendering on `ENV.discussion_thread_summarizer_enabled` and the dependency chain in §6.2 is further unblocked.

---

## Cycle 3 — Permission audit (M1 Foundations)

**Slice.** Audit `DiscussionTopic`'s existing permission gates and document that the Discussion Thread Summarizer requires no new permission objects. Two targeted comment insertions confirm the design decision in the model file; a new `doc/` Markdown file serves as the formal audit record and release note (NFR-6).

**Issue.** [#3](https://github.com/ejgdr/canvas-lms/issues/3) — "[M1] Permission audit: confirm reuse of read and moderate_forum gates." Linked to FR-4, FR-9, and NFR-6 in `agents/tasks/feature-1/implementation-research.md`. No `Blocked by` dependencies.

**Pull request.** [#58](https://github.com/ejgdr/canvas-lms/pull/58) — `docs(permissions): audit summarizer gate reuse`. Two files changed, 53 insertions, 0 deletions:

- `app/models/discussion_topic.rb` — 4-line block comment before `set_policy do` pointing to the audit doc; 1-line FR-9 comment above `user_can_see_posts?`. No executable tokens added or removed; `set_policy` block untouched.
- `doc/discussion_thread_summarizer_permissions.md` — new 48-line Markdown file documenting the two reused gates (`:read` via `visible_for?` and `:moderate_forum`), mapping each to the acceptance criteria, and providing the release note text.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-23T01:04:03Z | Todo → In Progress | MCP update on project item id `183104501` |
| 2026-05-23T01:05:00Z | QA Status set to Pending | MCP update on project item id `183104501` |
| 2026-05-23T01:07:17Z | QA Status → Skip — justified | MCP update on project item id `183104501` |
| 2026-05-23T01:08:01Z | In Progress → Done | MCP update on project item id `183104501` |

**Merge evidence.** PR #58 was squash-merged into `master` at commit `dd69253adf5b7229af46068a3db1572a6433fb0e`. Issue #3 was auto-closed by the `Closes #3` line in the PR body.

**Local verification.** Diff is docs-only (Ruby comments and Markdown). QA classification: `Skip — justified`. No test command executed; rationale recorded in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 3.

**Trace to plan.** This slice executes the third M1 — Foundations story in `agents/tasks/feature-1/implementation-research.md` §6.1. The §4.4 codebase evidence — `discussion_topic.rb` lines 1445–1502 for `:read` via `visible_for?` and line 1500 for `:moderate_forum` — confirmed that no new `given`/`can` blocks or `RoleOverride` entries are needed. All four acceptance criteria are satisfied by confirming existing gates are present (documented), not by adding new runtime code. With the audit on `master`, M4 (#24, #26) and M5 (#29, #31) implementers have a written reference they can cite when implementing the actual summary and digest endpoints.

---

## Cycle 4 — Feature-flag inheritance integration tests (M1 Foundations)

**Slice.** Add four RSpec integration examples to `spec/controllers/discussion_topics_controller_spec.rb` covering all account→course inheritance combinations for `discussion_thread_summarizer`. This is the M1 testing story: §5.2 of the research package listed "Feature-flag inheritance" as a required integration point, and issue #5's acceptance criteria mapped directly to the four state combinations.

**Issue.** [#5](https://github.com/ejgdr/canvas-lms/issues/5) — "[M1] Integration test: feature-flag inheritance (account default → course override)." Linked to FR-4 in `agents/tasks/feature-1/implementation-research.md`. Dependencies on #1 (flag declaration) and #2 (controller wiring) were resolved by Cycles 1 and 2.

**Pull request.** [#59](https://github.com/ejgdr/canvas-lms/pull/59) — `test(feature-flags): integration tests for flag inheritance chain`. One file changed, 50 insertions, 0 deletions. The new block `context "feature-flag inheritance chain"` is inserted directly after the existing `context "discussion_thread_summarizer_enabled js_env"` block (Cycle 2 tests) inside `describe "GET 'show'"`:

- Example 1: `allow_feature!` on root account + no course flag → `js_env` false (account allowed/off baseline)
- Example 2: `allow_feature!` on root account + `enable_feature!` on course → `js_env` true (course opts in)
- Example 3: `set_feature_flag!(Feature::STATE_DEFAULT_ON)` on root account + no course flag → `js_env` true (account on, inheritable)
- Example 4: `set_feature_flag!(Feature::STATE_DEFAULT_ON)` on root account + `disable_feature!` on course → `js_env` false (course opts out)

Key implementation note: `enable_feature!` sets `STATE_ON` which makes `can_override? = false`, locking the flag and preventing course override. Tests 3 and 4 instead use `set_feature_flag!(Feature::STATE_DEFAULT_ON)` (`allowed_on`), which keeps `can_override? = true`. This is the correct reading of "account ON" for these acceptance criteria — an account admin enabling the flag without locking it.

A `# TODO (M2/M3)` comment at the top of the context block marks where a no-job-enqueued example should be added once the summarization job code lands (acceptance criterion 5, deferred).

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-25T21:05:00Z | Todo → In Progress | GitHub UI (MCP unavailable on host) |
| 2026-05-25T21:32:00Z | QA Status → Pending | GitHub UI (MCP unavailable on host) |
| 2026-05-25T21:40:00Z | QA Status → Fail | GitHub UI — first run: 3/4, example 4 failed (STATE_ON locks flag, course override silently dropped) |
| 2026-05-25T21:42:00Z | QA Status → Pass | GitHub UI — second run after fix: 4/4 pass |
| 2026-05-25T21:48:00Z | In Progress → Done | GitHub UI (MCP unavailable on host) |

**Merge evidence.** PR #59 was squash-merged into `master` at commit `7d33f1254b216c3e49478530ae0a287cfd213664`. Issue #5 was auto-closed by the `Closes #5` line in the PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/controllers/discussion_topics_controller_spec.rb -e "feature-flag inheritance chain" --format documentation`. Exit code 0, **4 examples, 0 failures** (8.52 seconds, seed 49388). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 4. Initial run produced 1 failure (see QA evidence); root cause diagnosed and test corrected before re-run.

**Trace to plan.** This slice executes the M1 — Foundations testing story for FR-4 in `agents/tasks/feature-1/implementation-research.md` §5.2 and §6.1. The §4.4 codebase finding Q4 confirmed the `discussion_thread_summarizer` flag follows the `root_opt_in: true`, `applies_to: Course` pattern. The tests now establish a living regression guard for the inheritance chain: any future change to the flag YAML or the `feature_enabled?` resolution path that breaks account→course inheritance will surface immediately on these four examples. The deferred TODO comment connects this slice forward to M2/M3, where the no-job-enqueued assertion for criterion 5 will be added once summarization job code exists.

---

## Cycle 5 — Observability scaffolding: InstStatsd metric helpers (M1 Foundations)

**Slice.** Create `lib/discussion_thread_summarizer/metrics.rb` with six thin module-level helpers wrapping InstStatsd, and `spec/lib/discussion_thread_summarizer/metrics_spec.rb` with one example per helper. No caller is wired; M2+ service code will `require` this module without modifying it. This is the M1 observability story: NFR-4 requires generation latency (p50/p95/p99), cache hit rate, error rate by failure mode, daily generation count by account, and report submission count by reason category.

**Issue.** [#4](https://github.com/ejgdr/canvas-lms/issues/4) — "[M1] Observability scaffolding: InstStatsd counters for discussion thread summarizer." Linked to NFR-4 in `agents/tasks/feature-1/implementation-research.md`. No `Blocked by` dependencies on this item.

**Pull request.** [#60](https://github.com/ejgdr/canvas-lms/pull/60) — `feat(observability): add InstStatsd metric helpers for summarizer`. Two files added, 177 insertions, 0 deletions:

- `lib/discussion_thread_summarizer/metrics.rb` — 85 lines: `DiscussionThreadSummarizer::Metrics` module with six `self.` methods. All counters use `distributed_increment` (multi-region safe, matching every discussion summary/insight metric in the API controller). The latency helper uses `InstStatsd::Statsd.timing` directly, mirroring `lib/health_checks.rb`. All six methods tag with `account_id: account.global_id` (cross-shard-safe identifier).
- `spec/lib/discussion_thread_summarizer/metrics_spec.rb` — 92 lines: one `describe` block per helper, each using `allow(InstStatsd::Statsd).to receive(...).and_return(nil)` in a shared `before`, then asserting `have_received` with the exact metric name and tag hash. Pattern mirrors `spec/lib/pandata_events_spec.rb` and `spec/graphql/mutations/update_discussion_entry_participant_spec.rb`.

**Conventions mirrored and deviations noted:**
- Existing `discussion_topic.summary.*` metrics use flat strings with no tags. This module adds tags (`account_id`, `scope_mode`, `outcome`, `reason`, etc.) to match the broader Canvas convention and satisfy NFR-4's "by account" and "by failure mode" slicing requirements. Deviation from the no-tag precedent in the same controller is intentional and noted.
- `global_id` chosen over `id` for `account_id` tag — `id` is only unique within a shard; `global_id` is the correct cross-shard identifier for any metric aggregated across a multi-shard Canvas deployment.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-25T22:02:00Z | Todo → In Progress | GitHub UI (MCP unavailable on host) |
| 2026-05-25T22:05:00Z | QA Status → Pending | GitHub UI (MCP unavailable on host) |
| 2026-05-25T22:06:00Z | QA Status → Pass | GitHub UI (MCP unavailable on host) |
| 2026-05-25T22:10:00Z | In Progress → Done | GitHub UI (MCP unavailable on host) |

**Merge evidence.** PR #60 was squash-merged into `master` at commit `3f6c0fd1665dd0cb7bfcca0a31c802198f71cdbd`. Issue #4 was auto-closed by the `Closes #4` line in the PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/lib/discussion_thread_summarizer/metrics_spec.rb --format documentation`. Exit code 0, **6 examples, 0 failures** (0.78 seconds, seed 45989). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 5.

**Trace to plan.** This slice executes the M1 — Foundations observability story in `agents/tasks/feature-1/implementation-research.md` §6.1 (NFR-4: metrics). The §4.4 codebase finding 8 confirmed the precedent: discussion summary/insight paths use `InstStatsd::Statsd.distributed_increment` and `InstStatsd::Statsd.timing` directly. With `DiscussionThreadSummarizer::Metrics` now on `master`, every M2+ slice that touches generation, caching, failure handling, or report submission can `require` this module and call the appropriate helper without any further observability design decisions. The six metric names (`generation.attempt`, `generation.latency`, `cache.hit`, `cache.miss`, `failure`, `report.submission`) directly map to the NFR-4 requirements and will feed the M8 dashboard without renaming.

---

## Cycle 6 — ModelClient interface and StubModelClient (M2 Summarization service)

**Slice.** Create `app/services/discussion_thread_summarizer/model_client.rb` (abstract base class + `TransportError`) and `app/services/discussion_thread_summarizer/stub_model_client.rb` (deterministic stub), with `spec/services/discussion_thread_summarizer/model_client_spec.rb` (4 examples). No callers wired; the `SummarizationService` orchestrator (issue #6) depends on this interface and lands in Cycle 7.

**Issue.** [#7](https://github.com/ejgdr/canvas-lms/issues/7) — "[M2] Model-client interface with injectable stub." Linked to FR-1 and NFR-5 in `agents/tasks/feature-1/implementation-research.md`. Blocked by issue #6's design (resolved: interface contract defined here, orchestrator in Cycle 7). This slice deliberately honors the one-issue-one-cycle rhythm established in prior cycles; issues #6 and #7 were kept separate rather than bundled.

**Pull request.** [#61](https://github.com/ejgdr/canvas-lms/pull/61) — `feat(summarizer): add ModelClient interface and StubModelClient`. Three files added, 145 insertions, 0 deletions:

- `app/services/discussion_thread_summarizer/model_client.rb` — 48 lines: `DiscussionThreadSummarizer::TransportError` constant at namespace level; `DiscussionThreadSummarizer::ModelClient` abstract base class with `#summarize(payload)` raising `NotImplementedError`. Contract documented: returns a Hash with `:themes`, `:viewpoints`, `:open_questions`, `:scope_mode`.
- `app/services/discussion_thread_summarizer/stub_model_client.rb` — 41 lines: `DiscussionThreadSummarizer::StubModelClient < ModelClient` with `FIXED_RESPONSE` constant and deterministic `#summarize` returning it unchanged.
- `spec/services/discussion_thread_summarizer/model_client_spec.rb` — 56 lines: 4 examples across two `describe` blocks verifying the abstract contract and the stub behavior.

**Design decisions recorded:**

- `TransportError` at namespace level (`DiscussionThreadSummarizer::TransportError`), not class-scoped. Future job and controller code rescues a single domain error without knowing which concrete client raised it. Consistent with `CanvasHttp::Error` and `InstLLM::ServiceQuotaExceededError`. When error subclasses arrive (M2/M8), they sit at the same level; extract to `errors.rb` only when they multiply.
- Layout mirrors `AiExperiences::ConversationStartService` (namespaced directory, one class per file, `initialize` with injected collaborator) rather than `RubricLLMService` (monolithic flat file). `RubricLLMService` informed the payload-in / structured-response-out contract shape but was unsuitable as a layout precedent for a multi-file namespaced service.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-25T23:15:00Z | Todo → In Progress | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9EQ` |
| 2026-05-25T23:15:00Z | QA Status → Pending | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9EQ` |
| 2026-05-25T23:18:00Z | QA Status → Pass | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9EQ` |
| 2026-05-25T23:22:00Z | In Progress → Done | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9EQ` |

**Merge evidence.** PR #61 was squash-merged into `master` at commit `a06f6118f1de`. Issue #7 was auto-closed by the `Closes #7` line in the PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/model_client_spec.rb --format documentation`. Exit code 0, **4 examples, 0 failures** (0.77 seconds, seed 58513). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 6.

**Trace to plan.** This slice executes the M2 model-client story from `agents/tasks/feature-1/implementation-research.md` §6.1 (Summarization service milestone). The §4.4 codebase finding 8 — `RubricLLMService` and `LLMResponse` as the precedent for mockable model-client interfaces — defined the contract shape (payload hash in, structured hash out, raise on failure). With `ModelClient` and `StubModelClient` on `master`, Cycle 7 can wire the `SummarizationService` orchestrator with `client: StubModelClient.new` as its default without any further interface design. The `FIXED_RESPONSE` structure in `StubModelClient` also anchors the response contract for issue #13's unit tests (pseudonymization, scope filter, schema validation) and issue #14's integration test.

---

## Cycle 7 — Summarization service scaffold (M2 Summarization service)

**Slice.** Create `app/services/discussion_thread_summarizer/summarization_service.rb` — the orchestrator that is the only entry point for calling the model client — and `spec/services/discussion_thread_summarizer/summarization_service_spec.rb`. All three private pipeline steps are no-op stubs; each carries a comment naming the future slice that replaces it. No controllers, views, jobs, or cache layers are wired.

**Issue.** [#6](https://github.com/ejgdr/canvas-lms/issues/6) — "[M2] Summarization service scaffold." Linked to FR-1 and NFR-5 in `agents/tasks/feature-1/implementation-research.md`. Blocked by issue #7 (resolved by Cycle 6, PR #61). This cycle honored the one-issue-one-cycle rhythm; issues #6 and #7 were kept separate.

**Pull request.** [#62](https://github.com/ejgdr/canvas-lms/pull/62) — `[M2] Summarization service scaffold (closes #6)`. Two files added, 111 insertions, 0 deletions:

- `app/services/discussion_thread_summarizer/summarization_service.rb` — 62 lines: `DiscussionThreadSummarizer::SummarizationService` with `initialize(client: StubModelClient.new)` and a single public `#summarize(discussion_topic:, viewer:)`. Pipeline: `gather → pseudonymize → @client.summarize → validate → result`.
- `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` — 49 lines: three examples covering payload derivation, return-value pass-through, and DI substitutability using an anonymous `ModelClient` subclass.

**Stub contract notes:**
- `gather(discussion_topic, _viewer)` — yields `{ topic_id: discussion_topic.id }`. `_viewer` unused; real scope-limited content extraction lands in a later M2 slice.
- `pseudonymize(payload)` — pass-through; real author name replacement lands in issue #8.
- `validate(_result)` — returns `nil`. Contract: raise on schema violation; return value is always discarded. Real validator (issue #10) replaces the body with `raise SchemaError, ...` without touching the pipeline.

**Design decisions recorded:**

- Layout mirrors `AiExperiences::ConversationStartService` (namespaced directory, one class per file, kwarg-injected collaborator, single public action method, no `ApplicationService` base class) rather than the monolithic-flat `RubricLLMService`.
- `validate(_result)` returns `nil` (not the result) to make the "raise on bad output; return value is discarded" contract unambiguous for the issue #10 implementer. Requested in user review before any file was written.
- The DI spec example (example 3) uses a genuinely different anonymous subclass — not a second reference to `StubModelClient` — proving that a different output flows unchanged through the service, which is what dependency injection actually demonstrates.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-25T23:43:00Z | Todo → In Progress | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9DY` |
| 2026-05-25T23:43:00Z | QA Status → Pending | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9DY` |
| 2026-05-25T23:44:00Z | QA Status → Pass | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9DY` |
| 2026-05-25T23:50:00Z | In Progress → Done | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9DY` |

**Merge evidence.** PR #62 was squash-merged into `master` at commit `a9caeb3f7d40`. Issue #6 was auto-closed by the `Closes #6` line in the PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation`. Exit code 0, **3 examples, 0 failures** (0.73 seconds, seed 19569). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 7.

**Trace to plan.** This slice executes the M2 summarization-service orchestrator story in `agents/tasks/feature-1/implementation-research.md` §6.1. The §4.4 codebase finding 8 — `RubricLLMService` for the payload-in / structured-response-out contract; `AiExperiences::ConversationStartService` for the namespaced-directory layout — defined both the interface shape and the file organisation. With `SummarizationService` on `master`, every downstream M2 slice (pseudonymization #8, scope filter #9, validator #10, cache layer #11, metrics wiring #12) has the exact method stub it needs to replace, and future slices can replace each stub independently without touching the pipeline ordering.

---

## Cycle 8 — Pseudonymization transform (M2 Summarization service)

**Slice.** Add `DiscussionThreadSummarizer::Pseudonymizer` — the outbound transform that replaces each entry's `:author_name` with a stable per-thread label before any content crosses the application boundary to the model client. Update `SummarizationService#pseudonymize` to call it. The `gather` stub is unchanged; `pseudonymize` gracefully no-ops when `payload[:entries]` is absent, keeping all pre-existing service spec examples green.

**Issue.** [#8](https://github.com/ejgdr/canvas-lms/issues/8) — "[M2] Pseudonymization transform: replace author names with per-thread pseudonyms." Linked to FR-5 in `agents/tasks/feature-1/implementation-research.md`. Blocked by #6 (resolved by Cycle 7).

**Pull request.** [#64](https://github.com/ejgdr/canvas-lms/pull/64) — `[M2] Pseudonymization transform (closes #8)`. Four files changed, 205 insertions, 2 deletions:

- `app/services/discussion_thread_summarizer/pseudonymizer.rb` (new, 62 lines) — `Pseudonymizer.call(entries)` iterates entries in order, assigns first-seen labels ("Author A", "Author B", …), returns `Result = Struct.new(:pseudonymized_entries, :author_map)`. Uses `entry.merge(...)` so original hashes are not mutated.
- `spec/services/discussion_thread_summarizer/pseudonymizer_spec.rb` (new, 97 lines) — 10 unit examples covering: label output, stability, no-collision, body preservation, author_map, empty input, single-repeated-author, first-seen order, exact format, and no-mutation.
- `app/services/discussion_thread_summarizer/summarization_service.rb` (modified) — `pseudonymize` now calls `Pseudonymizer.call(entries)`; `return payload if entries.nil? || entries.empty?` guards the no-op path.
- `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified) — adds a 4th example: stubs `gather` to return a payload with entries, asserts the model client receives only pseudonymized `author_name` values.

**Design decisions recorded:**

- **Ordering rationale.** Order #8 → #9 → #10 derived from the board's blocked-by graph (#9 is blocked by #8 because the scope filter feeds filtered entries into pseudonymize; pseudonymize must exist as a downstream pass). Future cycles should defer to the board when ordering disagrees with a milestone list.
- **`author_map` scoping.** `Pseudonymizer` returns both `pseudonymized_entries` and `author_map`, but `SummarizationService` currently discards the map (`payload.merge(entries: result.pseudonymized_entries)` — map never forwarded). The map is computed-and-dropped to lock in the full output shape now. When M4 introduces UI rendering of summaries that reference pseudonyms, the map will need to be threaded through the service's return value. Until then, the map is intentionally unused but present.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-26T22:22:00Z | Todo → In Progress | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9Ec` |
| 2026-05-26T22:22:00Z | QA Status → Pending | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9Ec` |
| 2026-05-26T22:22:00Z | QA Status → Pass | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9Ec` |
| 2026-05-26T22:26:00Z | In Progress → Done | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9Ec` |

**Merge evidence.** PR #64 was squash-merged into `master` at commit `3d35daafa68b`. Issue #8 was auto-closed by the `Closes #8` line in the PR body.

**Local verification.** Commands and outcomes:
- `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/pseudonymizer_spec.rb --format documentation` — exit code 0, **10 examples, 0 failures** (1.45 seconds, seed 39280).
- `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` — exit code 0, **4 examples, 0 failures** (1.34 seconds, seed 54974). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 8.

**Trace to plan.** This slice executes the M2 pseudonymization story in `agents/tasks/feature-1/implementation-research.md` §6.1 (FR-5: honor scope-limited content mode; pseudonymization is a prerequisite for all modes). The §4.4 codebase finding — `DiscussionEntry belongs_to :user` as the source of display names — defined the entry field to redact (`:author_name`). With `Pseudonymizer` on `master`, Cycle 9 (#9 scope filter) can add its filtering step upstream of pseudonymize without touching the transform itself. The `author_map` output shape also anchors the M4 rendering contract so issue #24 implementers can thread it through without a rework.

---

## Cycle 9 — Scope-limited content filter (M2 Summarization service)

**Slice.** Replace the `gather` stub in `SummarizationService` with real logic that loads `DiscussionEntry` records ordered by creation time and, when a new hidden root-account flag is enabled, filters entries to instructor posts plus the requesting viewer's own posts. Also declares the new `discussion_thread_summarizer_scope_limited` feature flag. The payload shape produced matches the `{ author_name:, body: }` entry structure that Cycle 8's `Pseudonymizer` expects.

**Issue.** [#9](https://github.com/ejgdr/canvas-lms/issues/9) — "[M2] Scope-limited content filter (instructor + viewer posts only)." Linked to FR-5 in `agents/tasks/feature-1/implementation-research.md`. Blocked by #8 (resolved by Cycle 8).

**Issue #9 body — verbatim quote driving the flag decision:**
> "Account.site_admin.feature_enabled? shadow-flag precedent controls provider-level settings — the scope-mode flag follows the same per-account configuration pattern"

This citation establishes that scope mode is a per-account (RootAccount) configuration, not a per-thread attribute or an extension of the existing course-level `discussion_thread_summarizer` flag. A new hidden RootAccount flag is the direct implementation of this specification.

**Pull request.** [#66](https://github.com/ejgdr/canvas-lms/pull/66) — `[M2] Scope-limited content filter (closes #9)`. Three files modified, 148 insertions, 7 deletions:

- `config/feature_flags/discussion_thread_summarizer.yml` — adds `discussion_thread_summarizer_scope_limited` as a third sibling entry: `state: hidden`, `applies_to: RootAccount`, no shadow attribute. The two prior flags (`discussion_thread_summarizer` and `discussion_thread_summarizer_with_cedar`) are unchanged.
- `app/services/discussion_thread_summarizer/summarization_service.rb` — replaces the 3-line gather stub with 28 lines of real logic: loads `discussion_entries.active.order(:created_at).preload(:user).to_a`, reads the scope flag, filters when limited using `|` union of `instructor_user_ids(course)` and `[viewer.id]`, maps to `{ author_name: entry.user&.short_name || "Unknown", body: entry.message || "" }`, emits `scope_mode:` at payload level. Adds private `instructor_user_ids(course)` helper (~7 lines).
- `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` — adds shared gather-chain stubs to the outer `before` block (keeping the 4 pre-existing examples green), then a new `context "gather pipeline"` block with 6 examples.

**No `ContentGatherer` extraction.** The real `gather` + helper totals ~30 lines — within the threshold stated in the task brief. No extraction needed.

**Design decisions recorded:**

- **Why the flag landed in this slice rather than a separate declaration PR.** The `discussion_thread_summarizer_scope_limited` flag is a prerequisite for exercising the scope filter in tests: without it, the `feature_enabled?` call always returns `false` and the filter branch is dead code in the test environment. Bundling flag declaration and consumer in the same slice keeps the cycle cohesive — one PR, one merged unit, one evidence row — rather than creating a dead-config PR followed by a separate consumer PR with no passing tests.
- **`pluck`-over-`select` optimization rationale.** The canonical precedent is `DiscussionTopic::PromptPresenter#enrollments_by_user` (`app/models/discussion_topic/prompt_presenter.rb` lines 116–124), which loads `course.enrollments.active.select(:user_id, :type)` and groups types per user because it needs to classify each user as instructor or student. This slice only needs to know which user_ids are instructors after the DB already performs the type filter, so `.where(type: %w[TeacherEnrollment TaEnrollment]).pluck(:user_id).to_set` is the cheaper canonical shape: no Ruby-side grouping, no full enrollment row hydration, direct Set lookup in the filter.

**Scope confirmation.** The new `discussion_thread_summarizer_scope_limited` flag has no relationship to the Cedar routing flag beyond sharing the same YAML file. It is consumed only by `SummarizationService#gather` in this slice. The two prior flags and the project identity (Discussion Thread Summarizer) are unchanged.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-26T22:56:00Z | Todo → In Progress | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9FE` |
| 2026-05-26T22:56:00Z | QA Status → Pending | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9FE` |
| 2026-05-26T22:56:00Z | QA Status → Pass | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9FE` |
| 2026-05-26T22:59:00Z | In Progress → Done | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9FE` |

**Merge evidence.** PR #66 was squash-merged into `master` at commit `1b7fe364de45`. Issue #9 was auto-closed by the `Closes #9` line in the PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation`. Exit code 0, **10 examples, 0 failures** (0.86 seconds, seed 15403). Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 9.

**Trace to plan.** This slice executes the M2 scope-limited content filter story in `agents/tasks/feature-1/implementation-research.md` §6.1 (FR-5: honor scope-limited content mode). The §4.4 codebase finding — `context.grants_right?(user, session, :moderate_forum)` as the existing instructor-role check pattern — informed the role-check approach, but `PromptPresenter#enrollments_by_user` was chosen as the direct precedent since it is the only existing Canvas service that classifies users as instructors/students for discussion content purposes. With real `gather` on `master`, the full M2 pipeline (`gather → pseudonymize → client.summarize → validate`) now produces real content for both scope modes; issues #10 (validate), #11 (cache), and #12 (metrics wiring) can all be implemented without revisiting this step.

---

## Cycle 10 — Output schema validator (M2 Summarization service)

**Slice.** Add `DiscussionThreadSummarizer::OutputSchemaValidator` — a pure raise-on-invalid schema guard that inspects model responses before they can reach the cache. Also declares `DiscussionThreadSummarizer::SchemaViolationError` at namespace level. Updates `SummarizationService#summarize` to rescue `SchemaViolationError`, emit the `schema_invalid` failure metric, and re-raise — satisfying AC #4 (observability on rejection) while keeping the validator itself a pure transform with no cross-cutting concerns.

**Issue.** [#10](https://github.com/ejgdr/canvas-lms/issues/10) — "[M2] Output schema validator: reject malformed model responses before caching." Linked to FR-8 and NFR-5 in `agents/tasks/feature-1/implementation-research.md`. Blocked by #6 (resolved by Cycle 6).

**Issue #10 body — verbatim acceptance criteria driving key decisions:**
> "A response missing the `themes`, `viewpoints`, or `open_questions` fields is rejected and never written to cache"
> "A response with any field exceeding the configured max-length is rejected"
> "A response with a type-mismatched field (e.g. array where string expected) is rejected"
> "Rejected responses increment `discussion_thread_summarizer.schema_validation_failure` metric"

The fourth AC ("increment metric") was honoured in this slice rather than deferred to issue #12. Rationale: the `Metrics.increment_failure(reason: "schema_invalid", account:)` helper scaffolded in Cycle 5 is exactly the call site this AC activates; issue #12 covers per-generation audit log persistence, a different observability surface. Metric emission was placed in the service rescue block (not the validator) so the validator stays a pure raise-on-invalid transform and the account is already in scope.

`:scope_mode` is validated in addition to the three keys named in the AC, because the `ModelClient` contract in `model_client.rb` lines 39–40 documents it as a required fourth field. The AC covers minimum correctness, not exhaustive coverage.

**Pull request.** [#68](https://github.com/ejgdr/canvas-lms/pull/68) — `[M2] Output schema validator (closes #10)`. Four files changed, 250 insertions, 5 deletions:

- `app/services/discussion_thread_summarizer/output_schema_validator.rb` (new, 90 lines) — `SchemaViolationError = Class.new(StandardError)` at namespace level; `OutputSchemaValidator.call(result)` checks: result is a Hash, each of three array keys exists + is Array + ≤20 items + each element is String ≤500 chars; `:scope_mode` exists + is String ≤50 chars. Raises `SchemaViolationError` with descriptive message; returns `nil` on pass.
- `spec/services/discussion_thread_summarizer/output_schema_validator_spec.rb` (new, 110 lines) — 13 unit examples covering all validator branches including all three size-limit constants.
- `app/services/discussion_thread_summarizer/summarization_service.rb` (modified) — `summarize` gains `account = discussion_topic.context.root_account` and a `begin/rescue SchemaViolationError` block that calls `Metrics.increment_failure` and re-raises. `validate` replaces the 2-line stub with `OutputSchemaValidator.call(result)`.
- `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified) — adds `global_id: 10_000_000_000_001` to the shared `root_account` double (required by the Metrics call path); adds 2 wiring examples in a `context "schema validation"` block.

**Canvas validation precedent.** `DiscussionTopicInsight#validate_llm_response` (`app/models/discussion_topic_insight.rb` lines 167–199) — plain Ruby, raises `ArgumentError` with descriptive messages, checks `is_a?` type then required fields then value constraints. This is the closest existing Canvas precedent for gem-free LLM response validation. Mirrored the guard-before-persist pattern; raised `SchemaViolationError` instead of `ArgumentError` to match namespace conventions.

**Design decisions recorded:**

- **AC #4 wired here, not deferred to #12.** Validator stays pure (raise-on-invalid only); cross-cutting observability lives at the service boundary where the account is already in scope. This mirrors how Cycle 5's `Metrics` module was designed to be called from contextual code paths, not from low-level transforms.
- **All three MAX constants are under test.** `MAX_ARRAY_LENGTH`, `MAX_STRING_LENGTH`, and `MAX_SCOPE_MODE_LENGTH` each have a dedicated failing-case example. Constraints defined without tests are not enforced — a future refactor that removes a check would pass CI silently.
- **First-run fix.** One failure on first run: `root_account` double lacked `global_id` stub. Adding `global_id: 10_000_000_000_001` to the shared `let` resolved it; `global_id` is a real `Account` method (Switchman gem) so `instance_double` accepts it.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-26T23:31:00Z | Todo → In Progress | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9GY` |
| 2026-05-26T23:31:00Z | QA Status → Pending | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9GY` |
| 2026-05-26T23:31:00Z | QA Status → Pass | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9GY` |
| 2026-05-26T23:34:00Z | In Progress → Done | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9GY` |

**Merge evidence.** PR #68 was squash-merged into `master` at commit `32b38f84a55d`. Issue #10 was auto-closed by the `Closes #10` line in the PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/output_schema_validator_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation`. Exit code 0, **25 examples, 0 failures** (1.39 seconds, seed 46290). First run had 1 failure (see design decisions); second run after fix: 25/25. Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 10.

**Trace to plan.** This slice executes the M2 schema validation story in `agents/tasks/feature-1/implementation-research.md` §6.1 (FR-8: graceful degradation; NFR-5: reliability). With `OutputSchemaValidator` on `master`, the full pipeline from `gather` through `validate` is now real end-to-end: any malformed model response raises before reaching the caller, emits a metric, and is never written to cache. Issue #13 (unit tests for the full pipeline) and issue #14 (integration test) can now be written against a complete service.

---

## Cycle 11 — Audit log emission (M2 Summarization service)

**Slice.** Add a per-generation-attempt audit log record to `SummarizationService#summarize`. Every call — successful or not — emits exactly one structured JSON line via `Rails.logger.info`. Fields captured: `event`, `thread_id`, `scope_mode`, `model_identifier`, `request_byte_size`, `latency_ms`, `success`, `error_category`. Raw payload and author names are never logged. Two private helpers added: `emit_audit_log(**fields)` (the emitter) and `error_category_for(exception)` (maps exception type to category string).

**Issue.** [#12](https://github.com/ejgdr/canvas-lms/issues/12) — "[M2] Audit log emission: LLMResponse-style record per generation attempt." Linked to NFR-2 (observability) in `agents/tasks/feature-1/implementation-research.md`. Blocked by #6, #9, #10 — all resolved.

**Issue #12 body — verbatim acceptance criteria driving key decisions:**
> "Every generation attempt, regardless of outcome, produces exactly one audit record."
> "A failed generation attempt produces one record with success: false."
> "The record must not contain raw model response text or raw post content."
> "Fields: thread_id, scope_mode, model_identifier, byte_size, latency_ms, success/failure."
> "The feature-flag-off path need not produce an audit record (service never called)."

**Key design decision — LLMResponse rejected as audit store.** Three blocking schema constraints make `LLMResponse` unsuitable without a migration (forbidden by scope cap):
1. `associated_assignment` FK with `null: false` — no assignment exists in a discussion thread context.
2. `raw_response` with `null: false` — conflicts directly with AC #3 (no raw response text).
3. `user` FK with `null: false` — semantically wrong for a service-level audit where the "actor" is the service, not a specific user.
Conclusion: "LLMResponse-style" in the issue title was interpreted as field-shape and contract (structured metadata, one record per attempt, success/failure outcome), not literal row persistence. DB persistence is deferred to a future slice when a discussion-summarizer-specific audit table can be designed without the above constraints. `DiscussionTopicInsight` was also evaluated and rejected — it models workflow state (cached result), not generation-attempt audit.

**Key design decision — `Process.clock_gettime(Process::CLOCK_MONOTONIC)` over `Benchmark.measure#real`.**
Precedents: `app/models/lti/asset.rb:81,93` and `app/services/rubric_llm_service.rb:236`. The monotonic clock is immune to wall-clock adjustments (NTP steps, leap seconds, DST transitions). This matters operationally because `latency_ms` is consumed downstream by alerting thresholds — a wall-clock step during a summarize call would produce a false-positive threshold breach or an implausibly negative latency. Monotonic eliminates that class of ops incident.

**Key design decision — Option A (`$!` global) for success-state detection.**
`outcome = "success"` initialization with explicit mutation on rescue branches is incorrect for unanticipated exceptions: the exception propagates past both rescues, `ensure` runs, and `$!` is nil only on the success path. Using `propagating = $!` in the `ensure` block reads the truth from the VM directly — nil on success, the exception object on any failure path. The `error_category_for` helper then maps exception type to category string in one place. The existing `rescue SchemaViolationError` branch is preserved for its own responsibility (emit the Metrics counter) and no longer mutates audit state. An unexpected `StandardError` correctly produces `success: false, error_category: "unknown"`.

**Audit log strategy — log-line over DB row.** `Rails.logger.info` with a JSON-encoded hash is durable (log rotation + aggregation infrastructure is already in place for Canvas production) and requires no schema changes. Each log line is a flat JSON object easily parsed by Datadog/Splunk. AC #1 ("exactly one record per attempt") is satisfied by the `ensure` block which runs once per invocation. Future slice: if DB persistence is needed (e.g. for admin reporting), a discussion-summarizer-specific table with correct nullable FKs can be added and the `emit_audit_log` emitter updated to call `create!` in addition to (or instead of) the log line.

**Pull request.** [#70](https://github.com/ejgdr/canvas-lms/pull/70) — `[M2] Audit log emission per generation attempt (closes #12)`. Two files changed, 129 insertions, 9 deletions:

- `app/services/discussion_thread_summarizer/summarization_service.rb` (modified) — `summarize` restructured: `t0` captured before client call, `ensure` block added with `emit_audit_log` using `$!` for success detection. Two new private methods: `emit_audit_log(**fields)` and `error_category_for(exception)`. `rescue DiscussionThreadSummarizer::SchemaViolationError` preserved for Metrics emission.
- `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (modified) — shared `before` block gains `DiscussionThreadSummarizer::OutputSchemaValidator` autoload trigger (prevents `NameError` on `SchemaViolationError` when the audit-log context runs first) and `allow(Rails.logger).to receive(:info)` suppressor. Adds `context "audit log emission"` with 6 examples (see below). `let(:malformed_client)` hoisted to outer describe scope so both `schema validation` and `audit log emission` contexts can share it.

**Board status timeline.**

| Timestamp (UTC) | Transition | Source |
|---|---|---|
| 2026-05-27T01:48:00Z | In Progress | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9Hw` |
| 2026-05-27T01:50:00Z | Done | PR #70 auto-close |
| 2026-05-27T01:50:00Z | QA Status → Pass | GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9Hw` |

**Merge evidence.** PR #70 was squash-merged into `master` at commit `f10558c656d7`. Issue #12 closed by PR body.

**Local verification.** Command: `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation`. Exit code 0, **18 examples, 0 failures** (1.17 seconds, seed 47643). First run had 1 failure (autoload race — `SchemaViolationError` not yet loaded when `raise_error(SchemaViolationError)` argument evaluated); fixed by adding `DiscussionThreadSummarizer::OutputSchemaValidator` to shared `before`. Second run: 18/18. Full record in `agents/tasks/feature-1/qa-lab-evidence.md` Cycle 11.

**Trace to plan.** This slice satisfies NFR-2 (observability: every outbound call is logged with thread id, byte size, scope mode, model identifier, and latency; raw payloads are not logged) from `agents/tasks/feature-1/implementation-research.md` §1.2. The `ensure`-based emission guarantees AC #1 regardless of pipeline outcome. AC #5 (flag-off path need not produce record) is already satisfied: the service is never called when the feature flag is off (caller responsibility), so `ensure` never runs.

---
## Cycle 12 — Async summarization background job (issue #11, M2)

| Field | Content |
|---|---|
| Slice | [#11](https://github.com/ejgdr/canvas-lms/issues/11) — "[M2] Async summarization background job (delay with singleton + n_strand)." Branch `feat/m2-async-summarization-job`. |
| Classification | Behavior-changing application code — `SummarizationService.enqueue_for` is a new public class method that schedules `#summarize` via Delayed Job with singleton + n_strand keys. Four new spec examples exercise the dispatch contract. |
| Files changed | `app/services/discussion_thread_summarizer/summarization_service.rb` (+12 lines, additive only); `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (+57 lines, new `.enqueue_for` describe block). No new files. |
| Async entrypoint | `SummarizationService.enqueue_for(discussion_topic:, viewer:)` — class method on `SummarizationService`. Constructs an instance via `new` and calls `.delay(...).summarize(...)`, mirroring the `insight_generation` pattern at `discussion_topics_api_controller.rb:372–377`. |
| Delayed Job options | `priority: Delayed::HIGH_PRIORITY` (matches precedent); `singleton: "discussion_thread_summarizer:generation_for_topic:#{discussion_topic.id}"`; `n_strand: ["discussion_thread_summarizer:generation:#{Shard.current.database_server.region}", 1]`. |
| handle_asynchronously vs delay decision | `delay` on instance chosen. `handle_asynchronously` is for always-async methods (MaterializedView pattern); `delay` is for caller-chosen async dispatch (controller pattern). Our `enqueue_for` is the explicit async entry point — `delay` is correct. |
| Delayed Job spec convention | `expect_any_instance_of(described_class).to receive(:delay).with(hash_including(...)).and_return(proxy)` — set expectation before action, consistent with `discussion_topics_api_controller_spec.rb:824`. Block-form `allow_any_instance_of` used for key-capture examples. |
| Shard.current.database_server.region | Evaluated at enqueue time in tests; value is `nil` or an empty string in the test environment. Singleton key and n_strand string are constructed dynamically in both production and specs, matching the precedent. No stubbing needed. |
| Extract decision | Inline. The class method is 5 lines, well within the 30-line threshold. |
| Tests added | 4 examples in new `describe ".enqueue_for"` block: (1) dispatches with HIGH_PRIORITY, correct singleton, correct n_strand; (2) chains #summarize on the proxy with correct kwargs; (3) singleton key includes topic id (same topic → same key); (4) distinct topics → distinct keys. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; **22 examples, 0 failures** (finished in 1.39 seconds, seed 44441). First run: all green. |
| Pull request | [PR #72](https://github.com/ejgdr/canvas-lms/pull/72) — squash-merged at `5d71ab9c955ecd407470cfcf9b2f83f94ed850f6` on 2026-05-27T02:25:14Z |
| Evidence PR | [PR #73](https://github.com/ejgdr/canvas-lms/pull/73) — squash-merged at `cd8e1f435b64981a0f7a3aa9c2659a3d3264ac88` on 2026-05-27T02:26:40Z |
| Board status timeline | Todo → In Progress (implicit from In Progress → Done); In Progress → Done at 2026-05-27T02:27:XXZ (GraphQL update on item `PVTI_lAHOBQJOSM4BWez_zgrp9HE`) |
| QA Status transition | Pending → Pass at 2026-05-27T02:27:XXZ (GraphQL update on item `PVTI_lAHOBQJOSM4BWez_zgrp9HE`) |

---

## Cycle 13 — Cross-cutting pipeline seam unit tests (issue #13, M2)

| Field | Content |
|---|---|
| Slice | [#13](https://github.com/ejgdr/canvas-lms/issues/13) — "[M2] Unit tests: summarization service (pseudonymization, scope filter, schema validation, ...)." Branch `test/m2-summarization-service-consolidation-unit-tests`. |
| Classification | Behavior-changing (spec-only) — 4 new examples exercise cross-cutting seams; `transport_client` hoisted to outer scope. No production code changes. |
| Files changed | `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (+117 lines, -8 lines). |
| AC coverage | AC1 (pseudonyms in payload): already covered by Cycle 8; seam version adds value. AC2 (scope filter): already covered by Cycle 9; seam version adds value. AC3 (malformed response, no cache write): schema violation covered; "no cache write" is M3 (DiscussionTopicSummary not yet implemented — deferred to slice #16). AC4 (DiscussionTopicSummary write): M3 scope — requires production code not yet present; deferred. AC5 (no network calls): satisfied by StubModelClient throughout. |
| Async bridge test | Deferred to slice #14 — `instance_double` objects cannot be YAML-marshaled into Delayed::Job records, so `run_job`/`run_jobs` cannot drive the pipeline from `enqueue_for` in a unit test context. |
| Tests added | 4 examples in new `context "cross-cutting pipeline seams"`: (1) scope-limited filter + pseudonymize + validate in one `summarize` call; (2) scope-limited + malformed client: `Metrics.increment_failure` and audit `success: false` fire together; (3) transport error: `Metrics.increment_failure` NOT emitted (first explicit negative assertion); (4) idempotence: repeated calls with identical inputs produce identical client payloads. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; **26 examples, 0 failures** (finished in 1.35 seconds, seed 30855). First run: all green. |
| Pull request | [PR #75](https://github.com/ejgdr/canvas-lms/pull/75) — squash-merged at `756c7d4422c7f7b49585c318282d47c564a6d7c8` on 2026-05-27T02:38:45Z |
| Evidence PR | [PR #76](https://github.com/ejgdr/canvas-lms/pull/76) — squash-merged at `9f9583f38a47e5ca27c2c75eaa9736c8b4be85b4` on 2026-05-27T02:40:33Z |
| Board status timeline | In Progress → Done at 2026-05-27T02:41Z (GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9IQ`) |
| QA Status transition | Pending → Pass at 2026-05-27T02:41Z (GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9IQ`) |

---

## Cycle 14 — Async pipeline integration tests (issue #14, M2)

| Field | Content |
|---|---|
| Slice | [#14](https://github.com/ejgdr/canvas-lms/issues/14) — "[M2] Integration test: background job enqueues on thread open and produces valid output." Branch `test/m2-async-integration`. |
| Classification | Behavior-changing (spec-only) — new spec file with 3 integration examples using real AR fixtures and Delayed::Testing. No production code changes. |
| Files added | `spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb` (113 lines, new file). |
| Precedent | `spec/services/accessibility/integration/bulk_close_issues_service_spec.rb` — service-level integration spec in an `integration/` subdirectory using real AR + `run_jobs`. |
| Reading A vs B | Reading A: "thread open" simulated by direct `enqueue_for` call; no controller wiring. Controller trigger is M4 scope. |
| AC2 tripwire | `DiscussionTopicSummary` record with `dynamic_content_hash` — service does not yet write cache records; deferred to M3 slice #16. |
| AC4 | No real HTTP calls — structural via `StubModelClient.new` (default `@client`). |
| Delayed Job helpers | `Delayed::Job.where(singleton: key).count` for queue-state assertions; `run_jobs` (→ `Delayed::Testing.drain`) for execution. |
| Tests added | 3 examples: (1) `enqueue_for` creates exactly one job with correct singleton key; (2) second `enqueue_for` for same topic is a no-op (real DB singleton dedup); (3) job runs end-to-end: audit log `success: true`, `Metrics.increment_failure` not called. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb --format documentation` |
| Outcome | Exit code 0; **3 examples, 0 failures** (14.23 seconds, seed 16860). First run: 1 failure — `Delayed::Worker` emits non-JSON `[STAT]` lines through `Rails.logger.info` during job execution; `logged_payloads.last` was one of those, not the audit record. Fix: filter `logged_payloads` for entry containing `"generation_attempt"` string before parsing JSON. Second run: 3/3. |
| Pull request | [PR #78](https://github.com/ejgdr/canvas-lms/pull/78) — squash-merged at `3464a8953cb1002113c6145b01c640740bf25797` on 2026-05-27T03:19:09Z |
| Evidence PR | [PR #79](https://github.com/ejgdr/canvas-lms/pull/79) — squash-merged at `f8673075497cbabcdfcf543c6286e5a3c85c2e66` on 2026-05-27T03:20:51Z |
| Board status timeline | In Progress → Done at 2026-05-27T03:21Z (GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9JE`) |
| QA Status transition | Pending → Pass at 2026-05-27T03:21Z (GraphQL mutation on item `PVTI_lAHOBQJOSM4BWez_zgrp9JE`) |

---

---

## Cycle 15 — Content-version hash for cache keying (issue #15, M3)

| Field | Content |
|---|---|
| Slice | [#15](https://github.com/ejgdr/canvas-lms/issues/15) — "[M3] Content-version hash computation for cache keying." Branch `feat/m3-content-version-hash`. |
| Classification | New application code — `DiscussionThreadSummarizer::ContentVersionHash.call(topic)` is a new pure utility class. No changes to any existing file. |
| Files added | `app/services/discussion_thread_summarizer/content_version_hash.rb` (56 lines, new file); `spec/services/discussion_thread_summarizer/content_version_hash_spec.rb` (114 lines, new file). |
| Algorithm | `Digest::SHA256.hexdigest(tuples.to_json)` → 64-char lowercase hex string. Mirrors `DiscussionTopicInsight::Entry.hash_for_dynamic_content` (`app/models/discussion_topic_insight/entry.rb:43–50`): same digest function, same `.to_json` serialization, same uppercase-symbol hash structure. |
| Input set | Sorted-by-id array of `{id:, message:}` tuples for all non-deleted entries (`discussion_entries.active.order(:id).pluck(:id, :message)`). No user identity (avoids per-viewer cache fragmentation). `.active` scope: `where.not(workflow_state: "deleted")` confirmed at `app/models/discussion_entry.rb:456`. |
| Output | 64-char hex; fits `DiscussionTopicSummary.dynamic_content_hash` (varchar 255, limit confirmed in `db/migrate/20101210192618_init_canvas_db.rb:2269`) and `DiscussionTopicInsight::Entry.dynamic_content_hash` (varchar 64). |
| Empty topic | `Digest::SHA256.hexdigest("[]")` — deterministic non-nil hash. No ArgumentError for empty topics; ArgumentError raised only for nil input. |
| Threshold note | Issue #15 body describes a future token-count threshold so minor edits don't bust the cache. This slice delivers the deterministic hash primitive; threshold filtering is deferred to #16/#17. |
| Spec style | DB-backed (uses `course_model` + `discussion_topic.discussion_entries.create!`) to exercise the `.active` scope for real, matching Canvas model-spec convention. |
| Tests added | 9 examples: (1) 64-char hex format; (2) determinism (same state → equal hashes); (3) empty topic returns stable non-nil hash; (4) two different topics → different hashes; (5) new entry added → hash changes; (6) soft-delete excluded → hash changes; (7) soft-deleted only entry → hash equals empty-topic hash; (8) message edit → hash changes; (9) nil raises ArgumentError. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/content_version_hash_spec.rb --format documentation` |
| Outcome | Exit code 0; **9 examples, 0 failures** (finished in 7.82 seconds, seed 28253). First run: all green. |
| Pull request | [PR #81](https://github.com/ejgdr/canvas-lms/pull/81) — squash-merged at `dfa1bd32b0406005cb2086d161e7e96e44d16121` on 2026-05-27T17:35:18Z |
| Evidence PR | [PR #82](https://github.com/ejgdr/canvas-lms/pull/82) — squash-merged at `b8d672e0c43cbc49dbc788c4798ddfb5c74f666d` on 2026-05-27T17:39:33Z |
| Board status timeline | Todo → Done: 2026-05-27T17:35:18Z (auto-closed by PR #81 merge); QA Status → Pass: 2026-05-27T17:38:26Z (GraphQL update on item `PVTI_lAHOBQJOSM4BWez_zgrp9Jk`) |
| QA Status transition | Pending → Pass at 2026-05-27T17:38:26Z |

---

---

## Cycle 16 — Cache read/write in summarization pipeline (issue #16, M3)

| Field | Content |
|---|---|
| Slice | [#16](https://github.com/ejgdr/canvas-lms/issues/16) — "[M3] Cache read/write in summarization pipeline (fetch_or_create_summary)." Branch `feat/m3-cache-read-write`. |
| Issue split | Original #16 mixed pipeline + render-path ACs. Before implementation, #16 body was narrowed to pipeline-only; render ACs moved to [#84](https://github.com/ejgdr/canvas-lms/issues/84). Cycle 16 closes #16 only — **not** #84. |
| Classification | Behavior-changing application code — `SummarizationService#fetch_or_create_summary`, `LLM_CONFIG_VERSION`, `CacheResult`, private lookup/persist helpers; `enqueue_for` dispatches cache-aware path. |
| Files changed | `app/services/discussion_thread_summarizer/summarization_service.rb` (+67 lines); `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (+129 lines, 9 DB-backed cache examples in separate top-level describe); `spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb` (+12 lines, AC2 assertion). Net **+201 / -7** (under 250 tripwire). |
| Constants / types | `LLM_CONFIG_VERSION = "thread-summarizer-v1"`; `CacheResult = Struct.new(:status, :record, :result, keyword_init: true)` |
| 4-tuple WHERE rationale | Lookup uses `(llm_config_version, dynamic_content_hash, parent_id, locale)` on `discussion_topic.summaries`. Cycle 15's `ContentVersionHash` is locale-agnostic, so `locale` is a **separate column** in the WHERE — departing from issue #16's original 3-tuple wording, documented in the re-scoped issue body. |
| Cache key | Stores `ContentVersionHash.call(topic)` directly in `dynamic_content_hash` (tuple approach A). Precedent: `DiscussionTopicsApiController#fetch_or_create_summary` at `app/controllers/discussion_topics_api_controller.rb:1348–1368`. |
| scope_limited follow-up | Backlog [#85](https://github.com/ejgdr/canvas-lms/issues/85) — cache lookup comment in `#find_cached_summary` references this URL. Flag is `state: hidden` on RootAccount with no dev/ci override; safe while flag remains off. |
| `#summarize` visibility | Stays **public** for existing unit tests; `fetch_or_create_summary` is the cache-aware production path. Converge to private `#summarize` in a future cleanup cycle — not Cycle 16. |
| Tests added | 9 cache examples + 1 integration AC2 assertion; `enqueue_for` spec updated for `fetch_or_create_summary`. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/summarization_service_spec.rb spec/services/discussion_thread_summarizer/integration/async_summarization_spec.rb --format documentation` |
| Outcome | Exit code 0; **38 examples, 0 failures** (finished in 13.63 seconds, seed 60703). First run after fixes: all green. |
| Pull request | [PR #86](https://github.com/ejgdr/canvas-lms/pull/86) — squash-merged at `1f8256d4682c801efd00365ca89d9e417dd17096` on 2026-05-27T18:18:04Z |
| Evidence PR | [PR #87](https://github.com/ejgdr/canvas-lms/pull/87) — squash-merged at `e4f6e793b8e4d062c3ab547e80754444c72c350c` on 2026-05-27T18:20:11Z |
| Board status timeline | Todo → Done: 2026-05-27T18:18:04Z (auto-closed by PR #86); QA Status → Pass: 2026-05-27T18:19:19Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9J8`) |

---

## Cycle 17 — Cache invalidation hooks + meaningful-change threshold (issue #17, M3)

**Pre-implementation prerequisites (completed before branch):**

| Step | Result |
|---|---|
| [#84](https://github.com/ejgdr/canvas-lms/issues/84) state | Was **Closed** unintentionally after Cycle 16; **reopened** 2026-05-27 (`state_reason: reopened`). Cycle 17 confirmed #84 **Open** at start of cycle. |
| [#17](https://github.com/ejgdr/canvas-lms/issues/17) re-scope | Issue body updated with unambiguous threshold/rekey language: edits below word-delta threshold rekey without regeneration; creates and soft-deletes always meaningful. |

**Procedural — re-scope summary (Checkpoint 1 approved):**

- **Threshold applies to edits only.** Word delta = `|HtmlTextHelper.strip_tags(after).split.size − HtmlTextHelper.strip_tags(before).split.size|` compared to `Setting.get("discussion_thread_summarizer_meaningful_change_word_threshold", "5").to_i`.
- **Creates and soft-deletes** (`workflow_state → "deleted"`) are always meaningful regardless of entry size.
- **5-word threshold** is a tokenizer-free proxy (≈ 7 tokens for English); word count aligns with `DiscussionEntry#message_word_count` precedent.
- **Mechanism (a) + (e):** meaningful events emit `invalidation.fired` and leave rows as hash orphans (stale-aware lookup contract for #84); below-threshold edits `update_all` rekey `dynamic_content_hash` to post-edit `ContentVersionHash` without regeneration.
- **[#85](https://github.com/ejgdr/canvas-lms/issues/85)** stays **Backlog** — viewer-agnostic invalidation does not fix cross-viewer wrongness from scope-limited cache keys.

| Field | Content |
|---|---|
| Slice | [#17](https://github.com/ejgdr/canvas-lms/issues/17) — "[M3] Cache invalidation hooks + meaningful-change threshold." Branch `feat/m3-invalidation-hooks`. |
| Classification | Behavior-changing application code — write-side invalidation hooks on `DiscussionEntry`; new `CacheInvalidation` service; two metrics helpers. |
| Files changed | `app/services/discussion_thread_summarizer/cache_invalidation.rb` (new, 106 lines); `app/models/discussion_entry.rb` (+35 lines hooks); `lib/discussion_thread_summarizer/metrics.rb` (+17 lines); `spec/services/discussion_thread_summarizer/cache_invalidation_spec.rb` (new, 162 lines, 10 examples); `spec/lib/discussion_thread_summarizer/metrics_spec.rb` (+20 lines, 2 examples). Net **+339 / −1** — **surfaces 250-line tripwire overage** (rekey comment + 10 spec examples). |
| Tripwires | No `ContentVersionHash` edits; no `#fetch_or_create_summary` / cache tuple changes; no new flags; no rate limiting (#18); no render-path / #84 work; no audit DB persistence; no migration. PR closes **#17 only**. |
| Tests added | 10 cache-invalidation examples (create/edit above/edit below/delete, unrelated touch, flag off, rekey hit, soft-delete path, no client/job on rekey, multi-locale rekey) + 2 metrics examples. |
| Command | `docker compose exec web bundle exec rspec spec/services/discussion_thread_summarizer/cache_invalidation_spec.rb spec/lib/discussion_thread_summarizer/metrics_spec.rb --format documentation` |
| Outcome | Exit code 0; **18 examples, 0 failures** (8.13 seconds, seed 43247). |
| Pull request | [PR #89](https://github.com/ejgdr/canvas-lms/pull/89) — squash-merged at `3db30731b6ece2d75408ad331c6ec0a84fac00e4` on 2026-05-27T19:40:49Z |
| Evidence PR | [PR #90](https://github.com/ejgdr/canvas-lms/pull/90) — squash-merged at `4a6bf152ad8c485ae11477e409ba997bcabdbecf` on 2026-05-27T19:48:28Z |
| Board status timeline | Todo → Done: 2026-05-27T19:40:51Z (auto-closed by PR #89); QA Status → Pass: 2026-05-27T19:42:19Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9Kc`) |

---

## Cycle 18 — Regeneration rate limiter (issue #18, M3)

**Pre-implementation prerequisites (completed before branch):**

| Step | Result |
|---|---|
| InstLLMHelper Redis-down posture | At `app/helpers/inst_llm_helper.rb:41`: `raise "InstLLMHelper rate limiting requires Redis to be enabled for the Canvas instance. You may remove the 'rate_limit' option from the LLMConfig to disable rate limiting." unless Canvas.redis_enabled?` — **denies** (fail-closed `raise`, not allow-with-warn). **Cycle 18 matches — fail-closed raise when `!Canvas.redis_enabled?`.** |
| [#18](https://github.com/ejgdr/canvas-lms/issues/18) re-scope | Issue body updated: pipeline-only deny contract (`:rate_limited`, `record: nil`, `result: nil` + `rate_limit.cooldown_denied` or `quota_denied` metric). User-visible stale/rate-limited rendering → **#84**. Admin/instructor override → **#23** (Cycle 18 has no admin bypass). |

**Procedural — design locked at Checkpoint 1:**

- **Storage:** `Canvas.redis` only — cooldown `SET key 1 NX EX <seconds>`; daily quota `INCR` on UTC day-bucketed key `%Y%m%d` with `DECR` rollback on deny.
- **Settings:** `discussion_thread_summarizer_user_thread_cooldown_seconds` default `"600"` (10 minutes, per issue body "e.g. 10 minutes"); `discussion_thread_summarizer_account_daily_quota` default `"100"` (conservative initial cap; upward tuning expected after observed account-level usage).
- **Application point:** `SummarizationService#fetch_or_create_summary` cache-miss path, immediately before `#summarize`.
- **Check ordering:** Cooldown first; if cooldown denies, quota `INCR` does not run — only `rate_limit.cooldown_denied` fires.
- **Contract change (only post–Cycle-16):** `CacheResult.status` enum extended with `:rate_limited` (`record: nil`, `result: nil` on deny). `#fetch_or_create_summary(discussion_topic:, viewer:, locale:)` kwargs **unchanged**.
- **Rekey invariant (Cycle 17):** `CacheInvalidation` has no reference to `RegenerationRateLimiter`; rekey never consumes budget. Proved by spec example **"does not touch Redis during CacheInvalidation rekey"** — `expect(Canvas.redis).not_to have_received(:set)` and `not_to have_received(:incr)` (no limiter Redis ops; `decr`/`expire` likewise absent).

**Diff overage acknowledgment:** +347 combined lines (impl 121 + spec 226). Over the 250 soft cap by ~39%. Spec overrun on `regeneration_rate_limiter_spec.rb` (177 vs estimated 110) and `summarization_service_spec.rb` integration examples (49 vs estimated 25). Surfaced per cycle convention rather than absorbed silently. Cycle 19 should either accept a recalibrated budget or apply stricter pre-write spec discipline.

| Field | Content |
|---|---|
| Slice | [#18](https://github.com/ejgdr/canvas-lms/issues/18) — "[M3] Regeneration rate limiter." Branch `feat/m3-rate-limiter`. |
| Classification | Behavior-changing application code — new `RegenerationRateLimiter`; gate on cache-miss path; three `rate_limit.*` metrics. |
| Files changed | `app/services/discussion_thread_summarizer/regeneration_rate_limiter.rb` (new, 78 lines); `app/services/discussion_thread_summarizer/summarization_service.rb` (+19 lines gate + comment); `lib/discussion_thread_summarizer/metrics.rb` (+24 lines); `spec/services/discussion_thread_summarizer/regeneration_rate_limiter_spec.rb` (new, 177 lines, 10 unit + 1 documented skip); `spec/services/discussion_thread_summarizer/summarization_service_spec.rb` (+49 lines, 3 integration). Net **+347** — **diff cap surfaced** (see acknowledgment above). |
| Tripwires | No `ContentVersionHash` edits; no `CacheInvalidation` edits; no cache tuple / kwargs changes; no new flags; no migration (Redis-only); no #84 render-path; no admin bypass; no audit DB; PR closes **#18 only**. |
| Spec-idiom fix | `Time.zone.utc(...)` corrected to `Time.utc(...)` after four spec runs (Rails idiom — `Time.zone` is a `TimeZone` object, not a `Time` constructor). |
| Tests added | 10 limiter unit examples + 1 skip (SET NX atomicity); 3 `fetch_or_create_summary` `:rate_limited` integration examples; rekey-bypass + cooldown-before-quota + rollback-parity examples. |
| Command | `docker compose run --rm web bin/rspec spec/services/discussion_thread_summarizer/regeneration_rate_limiter_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb --format documentation` |
| Outcome | Exit code 0; **50 examples, 0 failures, 1 skipped** (15.09 s seed 1; also verified seeds 13659, 511). |
| Pull request | [PR #92](https://github.com/ejgdr/canvas-lms/pull/92) — squash-merged at `aed2b119be5eb1c895b0c6cc6dad64fd1c5e8011` on 2026-05-27T21:00:03Z |
| Evidence PR | [PR #93](https://github.com/ejgdr/canvas-lms/pull/93) — squash-merged at `15979bc24244ac5a46e04c78ea9af372827a1843` on 2026-05-27T21:01:14Z |
| Board status timeline | Done: 2026-05-27T21:00:05Z (auto-closed by PR #92); QA Status → Pass: 2026-05-27T21:00:16Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9LM`) |

*Last verified (Cycle 18 row): 2026-05-27 against squash-merge `aed2b119be5eb1c895b0c6cc6dad64fd1c5e8011`*

---

## Cycle 19 — Render-path lookup + GET endpoint (issue #84, M3)

**Pre-implementation prerequisites (completed before branch):**

| Step | Result |
|---|---|
| [#84](https://github.com/ejgdr/canvas-lms/issues/84) re-scope | Issue body narrowed to API/lookup layer only: `SummarizationService#lookup_for_render`, `RenderResult` / `RenderState`, `RegenerationRateLimiter.preview`, GET `thread_summary`, six render metrics. React/UI → [#95](https://github.com/ejgdr/canvas-lms/issues/95). Optional index → [#96](https://github.com/ejgdr/canvas-lms/issues/96) backlog. |
| [#95](https://github.com/ejgdr/canvas-lms/issues/95) filed | `[M4] Thread summary UI` — summary block, stale badge, generating placeholder, polling/refresh, collapse, regenerate, i18n, a11n. Blocked on #84 JSON contract. Reciprocal links in #84 body. |
| [#96](https://github.com/ejgdr/canvas-lms/issues/96) filed | Backlog optional composite index on `discussion_topic_summaries` for `lookup_for_render` if profiling shows pain. |

**Procedural — design locked at Checkpoint 1:**

- **`RegenerationRateLimiter.preview`** — only Cycle 19 contract change to the Cycle 18-locked class. READ-ONLY probe; mirrors `.check` cooldown-before-quota ordering via `EXISTS` on cooldown key and `GET` on quota counter. No `SET`, `INCR`, `DECR`, or `EXPIRE`. Render path uses `.preview`; job miss path uses `.check` authoritatively; preview-allow / job-deny race is acceptable (one-cycle delay).
- **`RenderResult` / `RenderState`** — separate from `CacheResult` / `CacheResult.status`. Pipeline enum stays `:hit | :miss | :rate_limited` only. Render enum: `:current`, `:stale`, `:generating`, `:rate_limited_stale`, `:rate_limited_empty`, `:disabled`.
- **GET endpoint:** `GET /api/v1/courses/:course_id/discussion_topics/:topic_id/thread_summary` on `DiscussionTopicsApiController#thread_summary`. JSON keyed by `RenderState`; `:disabled` → HTTP 200 `{ "status": "disabled", "enabled": false, "enqueued": false }` (not 404).
- **Stale lookup:** `where(llm_config_version:, parent_id: nil, locale:).order(created_at: :desc).first` — no `dynamic_content_hash` in WHERE; compare row hash to `ContentVersionHash.call(topic)` after fetch.
- **Hash race acceptance:** `ContentVersionHash.call(topic)` after row fetch; concurrent edits can flip `:current` ↔ `:stale` for one request; self-corrects on next render. Precedent: legacy summary `obsolete` flag at `discussion_topics_api_controller.rb:135` (`find_summary`).
- **Singleton-key / locale:** `enqueue_for` singleton is `discussion_thread_summarizer:generation_for_topic:#{discussion_topic.id}` — **topic-id only, not locale**. Multi-locale render requests for the same topic collapse to one delayed job; whichever locale wins the race gets the generated row. Observation (not a bug) — matches Cycle 12 `insight_generation` pattern. [#95](https://github.com/ejgdr/canvas-lms/issues/95) and [#21](https://github.com/ejgdr/canvas-lms/issues/21) must handle in UI (locale-specific polling or accepted constraint).
- **Spec-organization learning:** Use top-level `describe DiscussionThreadSummarizer::SummarizationService, "#lookup_for_render"` when referencing `described_class::LLM_CONFIG_VERSION`. Nesting under string-describe `"#fetch_or_create_summary"` makes `described_class` a String → `TypeError: nil is not a class/module`.
- **M3 milestone closure:** Cycle 19 closes [#84](https://github.com/ejgdr/canvas-lms/issues/84), the last consumer of M3 cache + invalidation + rate-limit + render-lookup contracts. M3 complete across cycles 15–19 / issues #15, #16, #17, #18, #84.

**Diff overage acknowledgment:** +481 combined lines (impl ~194 + spec ~287). Over raised cap 350 by ~37% (~131 lines). Fourth consecutive cycle over cap (15, 16, 17, 18, 19). Surfaced per surface-don't-absorb convention. Intentional spec coverage: 3 `.preview` + 7 `#lookup_for_render` + 3 controller + 1 integration (`:generating` → enqueue → job → `:current`). **M4 recalibration recommended:** (a) accept cap ~500 with soft 350, or (b) split cycles into impl-only and spec-only PRs.

| Field | Content |
|---|---|
| Slice | [#84](https://github.com/ejgdr/canvas-lms/issues/84) — "[M3] Thread render-path API: stale-aware lookup + render states." Branch `feat/m3-render-lookup`. |
| Classification | Behavior-changing application code — render lookup service, limiter preview, six render metrics, GET API. No React/JS. |
| Files changed | `regeneration_rate_limiter.rb` (+20 preview); `summarization_service.rb` (+92 RenderResult/RenderState/`lookup_for_render`); `metrics.rb` (+48 six helpers); `discussion_topics_api_controller.rb` (+33 `thread_summary`); `config/routes.rb` (+1); specs (+226 across 4 files). Net **+481**. |
| Tripwires | No `ContentVersionHash` / `CacheInvalidation` edits; no `.check` / `#fetch_or_create_summary` / `CacheResult` changes; no new flags; no migration; no React; no admin bypass; no audit DB; PR closes **#84 only** (not #95, #96, #85, #23). Diff cap **surfaced** (481 vs 350). |
| Tests added | 3 `.preview`; 7 `lookup_for_render`; 3 `thread_summary` controller; 1 integration `render_lookup_spec.rb`. |
| Command | `docker compose run --rm web bin/rspec` on limiter, summarization_service, controller, integration specs |
| Outcome | Exit code 0; **141 examples, 0 failures, 3 pending** (~1m15s, seed 1). |
| Pull request | [PR #97](https://github.com/ejgdr/canvas-lms/pull/97) — squash-merged at `92e6d7dde058bab1050a6226ec3509996c324752` on 2026-05-27T23:11:25Z |
| Evidence PR | [PR #98](https://github.com/ejgdr/canvas-lms/pull/98) — squash-merged at `c7e1fca2a0d370e9a147c4e877090a98e680bc97` on 2026-05-27T23:13:16Z |
| Board status timeline | Issue closed: 2026-05-27T23:11:26Z (PR #97 `closes #84`); Status → Done: 2026-05-27T23:12:12Z (project item add + explicit field, item `PVTI_lAHOBQJOSM4BWez_zgt_o0A`); QA Status → Pass: 2026-05-27T23:12:39Z (GraphQL update on item `192914240`) |

*Last verified (Cycle 19 row): 2026-05-27 against squash-merge `92e6d7dde058bab1050a6226ec3509996c324752`*

---

## Cycle 20 — Cache observability metrics (issue #20, M3 close-out)

**Pre-implementation prerequisites (completed before branch):**

| Step | Result |
|---|---|
| [#20](https://github.com/ejgdr/canvas-lms/issues/20) re-scope | Gap-fill close-out: AC `cache_hit`/`cache_miss` → shipped `cache.hit`/`cache.miss`; add `cache.stale` + `cache.invalidated`; flag gate; release note. Stale:fresh ratio → **#50**. Three parallel families documented (`cache.*`, `render.*`, `invalidation.*`). |

**Procedural — Checkpoint 1 decisions (Q1-A, Q2-B, Q3-A, Q4-A, Q5-A):**

- **Q1-A:** AC underscore names document dot-metric emits; no rename of shipped strings.
- **Q2-B:** `cache.stale` on both `:stale` and `:rate_limited_stale` (both serve orphan-hash content).
- **Q3-A:** `cache.invalidated` with `trigger:` `reply_*` alongside `invalidation.fired` (`cause:` create/edit/delete).
- **Q4-A:** Dual-emit — keep `render.stale` / `render.rate_limited_stale`; add `cache.stale` (not a replacement).
- **Q5-A:** Defense-in-depth flag gate on `#fetch_or_create_summary`.

**Three parallel metric families (intentional, not aliases):**

| Family | Purpose | Examples |
|--------|---------|----------|
| `cache.*` | NFR-4 cache effectiveness | `cache.hit`, `cache.miss`, `cache.stale`, `cache.invalidated` |
| `render.*` | Render-state dashboards (Cycle 19) | `render.current`, `render.stale`, `render.generating`, … |
| `invalidation.*` | Write-side invalidation (Cycle 17) | `invalidation.fired`, `invalidation.skipped_below_threshold` |

Dual-emit on overlap is intentional (e.g. stale serve → `render.stale` + `cache.stale`; invalidation → `invalidation.fired` + `cache.invalidated`).

**Flag-gate return shape (no `CacheResult.status` extension):**

When flag off, `#fetch_or_create_summary` returns `CacheResult.new(status: :rate_limited, record: nil, result: nil)` without calling the limiter, model, or cache/rate-limit metrics. `:rate_limited` is used only as the closest frozen enum value that blocks regeneration — **not** a real rate-limit deny.

**Diff vs cap:** +94 combined (impl ~38 + spec ~53 + doc 3). **Under** 200 soft / 250 hard — first cycle under cap after Cycles 17–19 overages.

| Field | Content |
|---|---|
| Slice | [#20](https://github.com/ejgdr/canvas-lms/issues/20) — observability gap-fill. Branch `feat/m3-cache-observability`. |
| Files changed | `metrics.rb` (+22); `summarization_service.rb` (+13); `cache_invalidation.rb` (+3); `doc/discussion_thread_summarizer_observability.md` (+3); specs (+53). |
| Tripwires | No renames of shipped metrics; no `ContentVersionHash` / limiter / render API changes; no `CacheResult` enum extension; PR closes **#20 only**. |
| Tests added | 2 metrics unit + 1 flag gate + 2 lookup cache.stale + 2 invalidation cache.invalidated (7 new assertions in 6 examples). |
| Command | `docker compose run --rm web bin/rspec` on metrics, cache_invalidation, summarization_service specs |
| Outcome | **66 examples, 0 failures** (~21.12 s, seed 1). |
| Pull request | [PR #100](https://github.com/ejgdr/canvas-lms/pull/100) — squash-merged at `758f583b07e572e165f8f8f66792c83a36956420` on 2026-05-27T23:35:18Z |
| Evidence PR | [PR #101](https://github.com/ejgdr/canvas-lms/pull/101) — squash-merged at `f09febf6e0e905ef664e998be2abf000d99700c2` on 2026-05-27T23:37:04Z |
| Board status timeline | Issue closed: 2026-05-27T23:35:20Z; Status → Done: 2026-05-27T23:35:21Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9NY` / `183104726`); QA Pass: 2026-05-27T23:36:03Z |

**M3 milestone (Cycle 20 row):** Cycle 20 closes [#20](https://github.com/ejgdr/canvas-lms/issues/20) observability gap-fill. Formal test umbrella [#19](https://github.com/ejgdr/canvas-lms/issues/19) closed in Cycle 21.

*Last verified (Cycle 20 row): 2026-05-27 against squash-merge `758f583b07e572e165f8f8f66792c83a36956420`*

---

## Cycle 21 — M3 unit-test consolidation (issue #19)

**Pre-implementation prerequisites (completed before branch):**

| Step | Result |
|---|---|
| [#19](https://github.com/ejgdr/canvas-lms/issues/19) re-scope (Lens A) | AC bullet 2 updated: word-delta invalidation/rekey semantics (#17), not threshold-aware `ContentVersionHash`. AC coverage table added to issue body. |
| [#95](https://github.com/ejgdr/canvas-lms/issues/95) label hygiene | `milestone:M3` removed; `milestone:M4` applied (title already `[M4]`). No body change. |
| Lens B follow-up | **Skipped** — bullet 2 treated as pre-implementation speculative wording; shipped behavior stands. |

**M3 milestone scope audit (final, `label:milestone:M3`):**

| # | Title | State after Cycle 21 |
|---|-------|----------------------|
| 15 | Content-version hash | Closed |
| 16 | Cache read/write | Closed |
| 17 | Invalidation hooks | Closed |
| 18 | Rate limiter | Closed |
| 19 | Unit tests (this cycle) | **Closed** |
| 20 | Observability metrics | Closed |
| 84 | Render-path API | Closed |
| 85 | `scope_mode` cache key (backlog) | Open — blocked on scope-limited rollout |
| 96 | Index backlog (optional perf) | Open — P3 |
| 95 | Thread summary UI | Open — relabeled **M4** (was mislabeled M3) |

**10 issues** with `milestone:M3` label at audit time → **7 closed** after Cycle 21; **3 remain** (#85, #96 backlog; #95 now M4).

**AC bullet-2 re-scope rationale (Lens A):** Original AC implied reply-count threshold suppresses hash changes. Cycles 15 + 17 shipped: `ContentVersionHash` hashes the full active entry set (any add/edit/delete changes hash); the 5-word `Setting` governs invalidation-vs-rekey on **edits** only. Tests assert shipped semantics; no production change.

**Spec idiom catalog (M4 reference):**

| Idiom | Source |
|-------|--------|
| `Time.utc(2026, …)` + `travel N.seconds` | `regeneration_rate_limiter_spec.rb:80-109` |
| Top-level `describe Class, "#method"` for constant lookup | Cycle 19 `summarization_service_spec.rb` fix |
| `allow(Canvas).to receive(:redis_enabled?).and_return(true)` | `regeneration_rate_limiter_spec.rb:29`; `inst_llm_helper_spec.rb` |
| `course.enable_feature!(:discussion_thread_summarizer)` | All DB-backed summarizer specs |
| `StubModelClient.new` — no network | Entire summarizer spec tree |
| Redis `set` nx/ex + `incr` stubs for E2E cooldown | `m3_invariants_spec.rb`; limiter spec `:41-48` |

**Diff vs cap:** +179 lines (1 new file). **Under** 200 soft / 250 hard.

| Field | Content |
|---|---|
| Slice | [#19](https://github.com/ejgdr/canvas-lms/issues/19) — test consolidation. Branch `feat/m3-test-consolidation`. |
| Files changed | `spec/services/discussion_thread_summarizer/m3_invariants_spec.rb` (+179). |
| Tripwires | No production code, controllers, flags, migrations; no spec moves/renames; PR closes **#19 only**. |
| Tests added | 6 examples in `m3_invariants_spec.rb` (AC index comment + hash / threshold / cooldown E2E). |
| Command | `bin/rspec spec/services/discussion_thread_summarizer/m3_invariants_spec.rb` — 6 examples, 0 failures, seed 40363, ~6.27 s |
| Regression | `bin/rspec spec/services/discussion_thread_summarizer/ spec/lib/discussion_thread_summarizer/` — 127 examples, 0 failures, 1 pending, seed 8371, ~44.94 s |
| Pull request | [PR #103](https://github.com/ejgdr/canvas-lms/pull/103) — squash-merged at `1d535bafdca18a58c6103029e9904313430f4c81` on 2026-05-28T00:10:09Z |
| Evidence PR | [PR #104](https://github.com/ejgdr/canvas-lms/pull/104) — squash-merged at `fc87532e1a6f4b38f18852e7341e1898ef6a3b98` |
| Board status timeline | Issue closed: 2026-05-28T00:10:10Z; Status → Done: 2026-05-28T00:10:12Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9M8` / `183104719`); QA Pass: 2026-05-28T00:10:42Z |

**M3 milestone closure marker:** M3 implementation + render API + observability + test consolidation: **complete**. M3 labels remaining: [#85](https://github.com/ejgdr/canvas-lms/issues/85) (backlog), [#96](https://github.com/ejgdr/canvas-lms/issues/96) (backlog). [#95](https://github.com/ejgdr/canvas-lms/issues/95) relabeled to M4. Phase 1 M3 deliverables done; M4 next (#95 React/UI).

*Last verified (Cycle 21 row): 2026-05-28 against squash-merge `1d535bafdca18a58c6103029e9904313430f4c81`*

---

## Cycle 22 — M4 thread summary UI (issue #95)

**Pre-implementation prerequisites (completed before branch):**

| Step | Result |
|---|---|
| [#95](https://github.com/ejgdr/canvas-lms/issues/95) re-scope | Cycle 22 slice: `GET thread_summary` only, visual states, 5s/30s polling, basic a11y/i18n. Manual refresh → #23; collapse → follow-up; #21 embed, #24 gate, #27 metrics, #46 WCAG out. |
| [#22](https://github.com/ejgdr/canvas-lms/issues/22) closed as duplicate | Comment references re-scoped #95 body; `ThreadSummaryBlock` lives in #95. |
| M4 audit re-run (`label:milestone:M4`) | 8 issues; no new filings since Checkpoint 1. |

**M4 milestone scope audit (final, `label:milestone:M4`):**

| # | Title | State after Cycle 22 |
|---|-------|------------------------|
| 95 | Thread summary UI (this cycle) | **Closed** |
| 22 | SummaryBlock component (duplicate) | **Closed** (duplicate of #95, prerequisite) |
| 24 | Must-post-before-replies gate | Open — **next** (with #26) |
| 26 | Permission gating unit tests | Open — **next** (with #24) |
| 23 | Regenerate + manual refresh UX | Open |
| 21 | REST/GraphQL additive fields | Open |
| 25 | Integration test response shapes | Open |
| 27 | Generation latency metrics | Open |

**8 issues** at audit time → **2 closed** after Cycle 22 (#95, #22 duplicate); **6 remain**. Sequencing: **#24 + #26** → **#23** → **#21** → **#25** → **#27**.

**#95 re-scope summary (deferred items):**

| Deferred | Target |
|----------|--------|
| Manual refresh button | [#23](https://github.com/ejgdr/canvas-lms/issues/23) |
| Regenerate action + cooldown UX | [#23](https://github.com/ejgdr/canvas-lms/issues/23) |
| Collapse UX | follow-up |
| REST/GraphQL embed on topic payload | [#21](https://github.com/ejgdr/canvas-lms/issues/21) |
| Must-post-before-replies enforcement | [#24](https://github.com/ejgdr/canvas-lms/issues/24) |
| Latency telemetry | [#27](https://github.com/ejgdr/canvas-lms/issues/27) |
| Full WCAG audit | [#46](https://github.com/ejgdr/canvas-lms/issues/46) |

**JS spec-idiom catalog (M4 — first cycle contribution):**

- **MSW path matchers** — string path `/api/v1/courses/:courseId/discussion_topics/:topicId/thread_summary` (query params ignored by MSW); mirror `DiscussionSummary2.test.tsx` `setupServer` + `http.get` + `HttpResponse.json`.
- **Partial fake timers** — `vi.useFakeTimers({toFake: ['setInterval', 'clearInterval']})` so `doFetchApi`/MSW stay real; `vi.useRealTimers()` in `afterEach`.
- **`act()` around timer advances** — `vi.advanceTimersByTimeAsync(5000)` wrapped in `act()` for generating → current poll transitions.
- **`fakeENV`** — `ENV.discussion_thread_summarizer_enabled`, `context_type`, `context_id`, `discussion_topic_id`, `LOCALE` per container test precedent.
- **`data-testid` over `getByText`** — stable queries across i18n strings (`thread-summary-generating`, `thread-summary-stale-alert`, etc.).
- **`pollIntervalForStatus()` extraction** — exported from `useThreadSummary.ts` for hook unit tests (5s / 30s / null) without full RTL timer churn.
- **AbortController + `clearInterval` cleanup contract** — both fire on unmount and dependency changes; documented in hook header comment; canonical pattern for future M4 hooks.

**Polling intervals:** 5s for `:generating`; 30s for `:stale` and `:rate_limited_stale`; none for `:current`, `:disabled`, `:rate_limited_empty`. Conservative vs aggressive polling to limit API load while background regeneration may still complete; stale states may refresh server-side without user action.

**Diff vs cap:** +623 insertions (7 files). **Over** 500 hard / 400 soft (~25% over hard cap). **282 of 623** are MSW/RTL test code (`ThreadSummaryBlock.test.tsx` ~205, `formatThreadSummary.test.ts` ~37, `useThreadSummary.test.ts` ~40) — realistic per-example overhead for visual + interaction + polling coverage; surfaced in PR #106 body, not absorbed silently.

| Field | Content |
|---|---|
| Slice | [#95](https://github.com/ejgdr/canvas-lms/issues/95) — `ThreadSummaryBlock`. Branch `feat/m4-thread-summary-ui`. |
| Files added | `ThreadSummaryBlock.tsx`, `useThreadSummary.ts`, `formatThreadSummary.ts`; tests under `__tests__/`; `DiscussionTopicRepliesContainer.tsx` (+2). |
| Tripwires | No Ruby/backend; frozen JSON contract; existing `discussion_thread_summarizer` js_env only; no metrics/deps; no legacy `DiscussionSummary`; no refresh/regenerate/collapse; PR closes **#95 only**. |
| Tests | 12 examples in `ThreadSummaryBlock/` (seed `1779928118029`); regression `discussion_topics_post/` 776 passed, 3 skipped. |
| Pull request | [PR #106](https://github.com/ejgdr/canvas-lms/pull/106) — squash-merged at `186a92f5e4231065a29f187e805d128eb30b6dcf` on 2026-05-28T01:02:03Z |
| Board status timeline | Issue closed: 2026-05-28T01:02:05Z (`closes #95`); project item add: 2026-05-28T01:02:28Z; Status → Done: 2026-05-28T01:02:43Z (item `PVTI_lAHOBQJOSM4BWez_zgt__hA` / `192937488`); QA Pass: 2026-05-28T01:02:59Z |

*Last verified (Cycle 22 row): 2026-05-28 against squash-merge `186a92f5e4231065a29f187e805d128eb30b6dcf`*

---

*Last verified: 2026-05-28 against squash-merge 186a92f5e4231065a29f187e805d128eb30b6dcf*

---

## Cycle 22 completion record

| Step | PR | Merge SHA | Timestamp (UTC) |
|------|----|-----------|-----------------|
| Implementation | [#106](https://github.com/ejgdr/canvas-lms/pull/106) | `186a92f5e4231065a29f187e805d128eb30b6dcf` | 2026-05-28T01:02:03Z |
| Issue #95 closed | `closes #95` on PR #106 | — | 2026-05-28T01:02:05Z |
| Board: Status → Done | GraphQL item `192937488` | — | 2026-05-28T01:02:43Z |
| Board: QA Status → Pass | GraphQL item `192937488` | — | 2026-05-28T01:02:59Z |
| Evidence records | [#107](https://github.com/ejgdr/canvas-lms/pull/107) | `f2cd7a220c01d3b51900eafd9515833228d606be` | 2026-05-28T01:03:49Z |
| Spec (targeted) | 12/12 pass, seed `1779928118029` | — | Cycle 22 impl QA |
| Spec (regression) | 776 passed, 3 skipped | — | Cycle 22 impl QA |
| Evidence completion | [#108](https://github.com/ejgdr/canvas-lms/pull/108) | (squash-merge SHA) | (squash-merge timestamp) |

*Last verified: 2026-05-28 against squash-merge f2cd7a220c01d3b51900eafd9515833228d606be (evidence records); impl row remains `186a92f5e4231065a29f187e805d128eb30b6dcf`.*

---

## Cycle 23 completion record

| Step | PR / issue | Board / note | Timestamp (UTC) |
|------|------------|--------------|-----------------|
| Evidence PR | [#110](https://github.com/ejgdr/canvas-lms/pull/110) | Cycle 23 evidence row reviewed and approved | 2026-05-29 |
| Issue #24 | [#24](https://github.com/ejgdr/canvas-lms/issues/24) | Project item `PVTI_lAHOBQJOSM4BWez_zgrp9Ps` now shows Status = Done and QA Status = Pass | 2026-05-29T23:55:30Z |
| Issue #26 | [#26](https://github.com/ejgdr/canvas-lms/issues/26) | Project item `PVTI_lAHOBQJOSM4BWez_zgrp9Rs` now shows Status = Done and QA Status = Pass | 2026-05-29T23:55:30Z |
| Issue trace | [#24 comment](https://github.com/ejgdr/canvas-lms/issues/24#issuecomment-4580744740); [#26 comment](https://github.com/ejgdr/canvas-lms/issues/26#issuecomment-4580745179) | Both comments point back to PR #109 | 2026-05-29T23:55:30Z |
| Completion PR | pending | This doc records the board transitions and closure trail for Cycle 23 | 2026-05-29T23:55:30Z |

*Last verified (Cycle 23 completion row): 2026-05-29T23:55:30Z against implementation SHA `9bde31884ce686ac45634e36a62ea4591ad4008d` and evidence PR #110*

---

## Cycle 23 implementation evidence

| Step | PR | SHA / notes | Timestamp (UTC) |
|------|----|-------------|-----------------|
| Implementation | [#109](https://github.com/ejgdr/canvas-lms/pull/109) | `9bde31884ce686ac45634e36a62ea4591ad4008d` | 2026-05-29 |
| Contract decision | D3 recorded in PR body | 403 / `require_initial_post` is the accepted gate contract; AC "returns null" satisfied in spirit by no content, no job | 2026-05-29 |
| Controller gate proof | [spec/controllers/discussion_topics_api_controller_spec.rb](../../../spec/controllers/discussion_topics_api_controller_spec.rb#L1413) | 4 cases: generating/no summary; 403 blocked must-post; forbidden no-read; generating when gate satisfied | 2026-05-29 |
| GraphQL guard | [spec/graphql/types/discussion_type_spec.rb](../../../spec/graphql/types/discussion_type_spec.rb#L194) | participant `summaryEnabled` remains a preference flag in shared examples for course + group discussions | 2026-05-29 |
| Full-file runs | `spec/controllers/discussion_topics_api_controller_spec.rb`; `spec/graphql/types/discussion_type_spec.rb` | 83 examples, 0 failures, 2 pending; 137 examples, 0 failures | 2026-05-29 |
| RuboCop | changed Ruby specs | 2 files inspected, no offenses detected | 2026-05-29 |
| Diff size | branch diff vs `master` | 2 files changed, 59 insertions(+), 3 deletions(-) | 2026-05-29 |

*Last verified (Cycle 23 row): 2026-05-29 against branch SHA `9bde31884ce686ac45634e36a62ea4591ad4008d`*

---

## Cycle 24 — Additive summary fields on DiscussionTopic REST + GraphQL (issue #21)

| Field | Content |
|---|---|
| Cycle | 24 |
| Issue | [#21](https://github.com/ejgdr/canvas-lms/issues/21) — additive summary fields on DiscussionTopic REST + GraphQL |
| Implementation PR | [#112](https://github.com/ejgdr/canvas-lms/pull/112), branch `feat/m4-topic-summary-embed`, squash-merge SHA `132427903290b7c65b81a947daa2965e0f0c4ed9` (2026-05-30T20:06:56Z) |
| Evidence PR | [#113](https://github.com/ejgdr/canvas-lms/pull/113), branch `docs/cycle-24-evidence-records`, squash-merge SHA `23d4e9bcf1af5c0ec78c62716c015d8eb1550456` (2026-05-30T20:11:52Z) |
| Completion PR | pending — closure SHA threads on squash-merge of this cycle's completion PR |
| Issue closure | [#21](https://github.com/ejgdr/canvas-lms/issues/21) closed by #112 (`closes #21`, 2026-05-30T20:06:57Z) |
| What shipped | `DiscussionThreadSummarizer::TopicSummaryEmbed`; REST `show` + `view` additive `summary` object; GraphQL `Discussion.summary` + `DiscussionThreadSummary` type + `DiscussionThreadSummaryStatus` enum; [API doc](../../../doc/discussion_thread_summarizer_api_embed.md) |
| Contract decision | `status` ∈ {`current`, `stale`, `generating`, `unavailable`}; `summary` is `null` only when no cache row exists **and** generation has not started (`rate_limited_empty` → `null`). `:generating` returns an object with `status: "generating"`, `text: nil`, `generated_at: nil`. |
| Diff size | **465 lines** (+464 / −1); **196 lines** in controller spec alone — over 250 hard cap; justified as cohesive additive REST + GraphQL + type + module + tests unit (Cycle 17 precedent) |
| Test evidence | **16 examples, 0 failures**, seed `63338` (~18.14 s). Matrix: {show, view, GraphQL} × {flag off + shape stability, cached current/stale, generating object, not started (`rate_limited_empty` → null)} |
| Reproduce command | `docker compose exec web bundle exec rspec spec/controllers/discussion_topics_api_controller_spec.rb -e "thread summary embed" spec/graphql/types/discussion_type_spec.rb -e "thread summary embed"` |
| QA lab | [qa-lab-evidence.md Cycle 24 row](./qa-lab-evidence.md#cycle-24--additive-summary-fields-issue-21) — `Pass`; board QA Status → Pass applied on completion (item `183104736`) |
| Board (completion) | Project item `PVTI_lAHOBQJOSM4BWez_zgrp9OA` / `183104736`: Status → Done (`98236657`); QA Status → Pass (`875199fe`) via GraphQL after completion PR merge |

*Last verified (Cycle 24 row): 2026-05-30T20:12:00Z against implementation squash-merge `132427903290b7c65b81a947daa2965e0f0c4ed9`; evidence squash-merge `23d4e9bcf1af5c0ec78c62716c015d8eb1550456`*

---

## Cycle 25 — Integration tests for additive summary response shapes (issue #25)

| Field | Content |
|---|---|
| Cycle | 25 |
| Issue | [#25](https://github.com/ejgdr/canvas-lms/issues/25) — REST/GraphQL response shape integration tests |
| Implementation PR | [#115](https://github.com/ejgdr/canvas-lms/pull/115), branch `feat/m4-summary-shape-integration-tests`, squash-merge SHA `2bb202a6191261d82971bc464b87d4efdf5f115a` (2026-05-31T04:55:21Z) |
| Evidence PR | [#116](https://github.com/ejgdr/canvas-lms/pull/116), branch `docs/cycle-25-evidence-records`, squash-merge SHA `884e4a16d8d0600772b8771c61909a6cfbd832a5` (2026-05-31T04:56:00Z) |
| Completion PR | pending — closure SHA threads on squash-merge of this cycle's completion PR |
| Issue closure | [#25](https://github.com/ejgdr/canvas-lms/issues/25) closed by #115 (`closes #25`, 2026-05-31T04:55:21Z) |
| What shipped | `spec/apis/v1/discussion_thread_summary_shape_spec.rb` — smoke integration via `api_call` (REST show) and `CanvasSchema.execute` (GraphQL `Discussion.summary`) |
| Integration value | Full request stack (routing, Bearer token auth, `Api::V1::DiscussionTopics` serialization) vs #21 controller/`GraphQLTypeTester` unit matrix; no production code |
| Diff size | **201 lines** (spec-only); under 250 cap |
| Test evidence | **8 examples, 0 failures**, seed `33354` (~9.05 s). Matrix: REST + GraphQL × {flag off + shape stability, cached current, not started (`rate_limited_empty` → null)} |
| Reproduce command | `docker compose run --rm web bin/rspec spec/apis/v1/discussion_thread_summary_shape_spec.rb --format documentation` |
| QA lab | [qa-lab-evidence.md Cycle 25 row](./qa-lab-evidence.md#cycle-25--integration-test-summary-response-shapes-issue-25) — `Pass`; board QA Status → Pass applied before impl merge (item `PVTI_lAHOBQJOSM4BWez_zgrp9Qk`) |
| Board (completion) | Project item `PVTI_lAHOBQJOSM4BWez_zgrp9Qk`: Status → Done (`98236657`); QA Status → Pass (`875199fe`) via GraphQL after completion PR merge |

*Last verified (Cycle 25 row): 2026-05-31T04:56:00Z against implementation squash-merge `2bb202a6191261d82971bc464b87d4efdf5f115a`; evidence squash-merge `884e4a16d8d0600772b8771c61909a6cfbd832a5`*

---

## Cycle 26 — Generation latency metrics (issue #27)

| Field | Content |
|---|---|
| Cycle | 26 |
| Issue | [#27](https://github.com/ejgdr/canvas-lms/issues/27) — generation latency metrics (p50/p95/p99) |
| Implementation PR | [#118](https://github.com/ejgdr/canvas-lms/pull/118), branch `feat/m4-generation-latency-metrics`, squash-merge SHA `f1d9a391efe892dcfff6b99d964cf7443b7e128e` (2026-05-31T05:12:14Z) |
| Evidence PR | [#119](https://github.com/ejgdr/canvas-lms/pull/119), branch `docs/cycle-26-evidence-records`, squash-merge SHA `ad7c296ba4e98ce2ef5b1f162269f89d469a5f79` (2026-05-31T05:12:43Z) |
| Completion PR | pending — closure SHA threads on squash-merge of this cycle's completion PR |
| Issue closure | [#27](https://github.com/ejgdr/canvas-lms/issues/27) closed by #118 (`closes #27`, 2026-05-31T05:12:14Z) |
| What shipped | Wired `Metrics.increment_generation_attempt`, `record_generation_latency_ms`, `increment_generation_error` in `SummarizationService#fetch_or_create_summary` / `#summarize`; release note in [observability doc](../../../doc/discussion_thread_summarizer_observability.md) |
| Measurement boundary | Latency wraps `@client.summarize` + `validate` only (monotonic `t0` after gather/pseudonymize). Excludes cache lookup and rate-limiter probes. |
| Metric names | `discussion_thread_summarizer.generation_attempt`, `.generation_latency_ms`, `.generation_error` — tags `account_id`, `scope_mode` (no PII) |
| Diff size | **132 lines** (+132 / −16); under 250 cap |
| Test evidence | **15 examples, 0 failures** (11 metrics + 4 service integration, seed `62572`, ~4.49 s service subset) |
| Reproduce command | `docker compose run --rm web bin/rspec spec/lib/discussion_thread_summarizer/metrics_spec.rb spec/services/discussion_thread_summarizer/summarization_service_spec.rb -e "generation latency metrics"` |
| QA lab | [qa-lab-evidence.md Cycle 26 row](./qa-lab-evidence.md#cycle-26--generation-latency-metrics-issue-27) — `Pass`; board QA Status → Pass applied before impl merge (item `PVTI_lAHOBQJOSM4BWez_zgrp9Sw`) |
| Board (completion) | Project item `PVTI_lAHOBQJOSM4BWez_zgrp9Sw`: Status → Done (`98236657`); QA Status → Pass (`875199fe`) via GraphQL after completion PR merge |

*Last verified (Cycle 26 row): 2026-05-31T05:12:43Z against implementation squash-merge `f1d9a391efe892dcfff6b99d964cf7443b7e128e`; evidence squash-merge `ad7c296ba4e98ce2ef5b1f162269f89d469a5f79`*

---

## Cycle 27 — Regenerate + cooldown UX + backend regenerate endpoint (issues #23, #121)

| Field | Content |
|---|---|
| Cycle | 27 |
| Issues | [#23](https://github.com/ejgdr/canvas-lms/issues/23) — frontend regenerate button + cooldown UX; [#121](https://github.com/ejgdr/canvas-lms/issues/121) — backend `POST .../thread_summary/regenerate` (filed to trace endpoint gap after #18/#84) |
| Implementation PR | [#122](https://github.com/ejgdr/canvas-lms/pull/122), branch `feat/m4-regenerate-cooldown-ux`, squash-merge SHA `640992dc379987df3721f7443d3dbf5cec3d6c2e` (2026-05-31T05:37:48Z) |
| Evidence PR | [#123](https://github.com/ejgdr/canvas-lms/pull/123), branch `docs/cycle-27-evidence-records`, squash-merge SHA `3467ac3a8a42359e3e5d92626c4c2498bca67eed` (2026-05-31T05:40:38Z) |
| Completion PR | pending — branch `docs/cycle-27-completion-records` |
| Issue closure | [#23](https://github.com/ejgdr/canvas-lms/issues/23) and [#121](https://github.com/ejgdr/canvas-lms/issues/121) closed by #122 (`closes #23`, `closes #121`, 2026-05-31T05:37:49Z) |
| Paired-issue rationale | Regenerate route assumed by #23 (FR-7) but absent on `master` after #18 (rate limiter) and #84 (GET render path). Rather than unwind the branch, #121 filed + both closed in one cycle — mirroring Cycle 23 **#24 + #26** paired precedent. |
| What shipped (frontend) | `ThreadSummaryBlock` regenerate button; `aria-disabled` cooldown state (focusable); inline quota-exhaustion `Alert` (no toast); `formatRegenerationCooldown` pure helper; `useThreadSummary` regenerate + polling reuse |
| What shipped (backend) | `POST .../thread_summary/regenerate`; `SummarizationService#request_regenerate`; `RegenerationRateLimiter.cooldown_remaining_seconds`; additive `regeneration` metadata on `GET .../thread_summary`; release note in [api embed doc](../../../doc/discussion_thread_summarizer_api_embed.md) |
| Diff size | **631 lines** (+631 / −18); over 250 soft cap — justified as cohesive FR-7 feature + paired backend (Cycle 17/23 precedent) |
| Test evidence | **14 JS + 11 Ruby, 0 failures** (JS seed `1780205921983`; Ruby seed `17098`) |
| Reproduce command (JS) | `docker compose run --rm web yarn test ui/features/discussion_topics_post/react/components/ThreadSummaryBlock/__tests__/formatRegenerationCooldown.test.ts ui/features/discussion_topics_post/react/components/ThreadSummaryBlock/__tests__/ThreadSummaryBlock.test.tsx --run` |
| Reproduce command (Ruby) | `docker compose run --rm web bin/rspec spec/controllers/discussion_topics_api_controller_spec.rb -e "thread_summary (Discussion Thread Summarizer)" -e "regenerate_thread_summary"` |
| QA lab | [qa-lab-evidence.md Cycle 27 row](./qa-lab-evidence.md#cycle-27--regenerate--cooldown-ux--backend-endpoint-issues-23-121) — `Pass`; board QA Status → Pass applied on completion (items `#23` / `#121`) |
| Board (completion) | #23 item `PVTI_lAHOBQJOSM4BWez_zgrp9O8` / `183104751`; #121 item `PVTI_lAHOBQJOSM4BWez_zguR8Dg` / `194113592`: Status → Done (`98236657`); QA Status → Pass (`875199fe`) via GraphQL after completion PR merge |
| M4 milestone | **Complete** — all nine M4-labeled issues closed (#21–#27, #95, #22 duplicate, #121) |

*Last verified (Cycle 27 row): 2026-05-31T05:40:38Z against implementation squash-merge `640992dc379987df3721f7443d3dbf5cec3d6c2e`; evidence squash-merge `3467ac3a8a42359e3e5d92626c4c2498bca67eed`*

---

## Cycle 27 completion record

| Step | PR / issue | Board / note | Timestamp (UTC) |
|------|------------|--------------|-----------------|
| Implementation | [#122](https://github.com/ejgdr/canvas-lms/pull/122) | Squash-merge `640992dc379987df3721f7443d3dbf5cec3d6c2e`; closes #23 + #121 | 2026-05-31T05:37:48Z |
| Backend issue filed | [#121](https://github.com/ejgdr/canvas-lms/issues/121) | Paired with #23 for endpoint traceability (Cycle 23 #24+#26 precedent) | 2026-05-31T05:32:52Z |
| Evidence PR | [#123](https://github.com/ejgdr/canvas-lms/pull/123) | Cycle 27 evidence row for both #23 and #121 | 2026-05-31T05:40:38Z |
| Issue #23 | [#23](https://github.com/ejgdr/canvas-lms/issues/23) | Project item `PVTI_lAHOBQJOSM4BWez_zgrp9O8`: Status = Done; QA Status = Pass | 2026-05-31T05:40:49Z |
| Issue #121 | [#121](https://github.com/ejgdr/canvas-lms/issues/121) | Project item `PVTI_lAHOBQJOSM4BWez_zguR8Dg`: Status = Done; QA Status = Pass | 2026-05-31T05:40:50Z |
| M4 milestone | All M4 issues | Nine issues closed — per-thread summary surface complete | 2026-05-31T05:37:49Z |
| Completion PR | pending | This doc records board transitions and closure trail for Cycle 27 | 2026-05-31T05:41:00Z |

*Last verified (Cycle 27 completion row): pending completion PR merge*

## M5

User-scoped open-question dismissals landed in PR #125 on the existing feature flag, with moderator-only access and InstStatsd tags matching the summarizer pipeline.

| Cycle | Issue | PR | Flag | QA | Reproduce |
|---|---|---|---|---|---|
| 28 | [#28](https://github.com/ejgdr/canvas-lms/issues/28) | [#125](https://github.com/ejgdr/canvas-lms/pull/125) | `discussion_thread_summarizer` | Pass | `docker compose exec web bundle exec rspec spec/models/discussion_entry_open_questions_spec.rb spec/controllers/discussion_topics_api_controller_spec.rb` |
| 28 | [#29](https://github.com/ejgdr/canvas-lms/issues/29) | [#125](https://github.com/ejgdr/canvas-lms/pull/125) | `discussion_thread_summarizer` | Pass | `docker compose exec web bundle exec rspec spec/models/discussion_entry_open_questions_spec.rb spec/controllers/discussion_topics_api_controller_spec.rb` |
| 28 | [#34](https://github.com/ejgdr/canvas-lms/issues/34) | [#125](https://github.com/ejgdr/canvas-lms/pull/125) | `discussion_thread_summarizer` | Pass | `docker compose exec web bundle exec rspec spec/models/discussion_entry_open_questions_spec.rb spec/controllers/discussion_topics_api_controller_spec.rb` |
| 29 | [#30](https://github.com/ejgdr/canvas-lms/issues/30) | [#126](https://github.com/ejgdr/canvas-lms/pull/126) | `discussion_thread_summarizer` | Pass | `docker compose run --rm web yarn test ui/features/discussion_topics_index/react/components/__tests__/OpenQuestionsDigest.test.tsx --run` |
| 29 | [#31](https://github.com/ejgdr/canvas-lms/issues/31) | [#126](https://github.com/ejgdr/canvas-lms/pull/126) | `discussion_thread_summarizer` | Pass | `docker compose run --rm web yarn test ui/features/discussion_topics_index/react/components/__tests__/OpenQuestionsDigest.test.tsx --run` |
| 29 | [#32](https://github.com/ejgdr/canvas-lms/issues/32) | [#126](https://github.com/ejgdr/canvas-lms/pull/126) | `discussion_thread_summarizer` | Pass | `docker compose run --rm web yarn test ui/features/discussion_topics_index/react/components/__tests__/OpenQuestionsDigest.test.tsx --run` |
| 30 | [#33](https://github.com/ejgdr/canvas-lms/issues/33) | [#127](https://github.com/ejgdr/canvas-lms/pull/127) | `discussion_thread_summarizer` | Pass | `docker compose run --rm web bin/rspec spec/apis/v1/open_questions_digest_spec.rb --format documentation` |

M5 (Open Questions digest) complete — #28/#29/#34 (PR #125), #30/#31/#32 (PR #126), #33 (PR #127). Milestone closed.
