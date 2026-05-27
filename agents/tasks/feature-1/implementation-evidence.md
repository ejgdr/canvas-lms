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
| Evidence PR | (pending merge — `docs/cycle-16-evidence-records`) |
| Board status timeline | Todo → Done: 2026-05-27T18:18:04Z (auto-closed by PR #86); QA Status → Pass: 2026-05-27T18:19:19Z (item `PVTI_lAHOBQJOSM4BWez_zgrp9J8`) |

---

*Last verified: 2026-05-27 against squash-merge 1f8256d4682c801efd00365ca89d9e417dd17096*
