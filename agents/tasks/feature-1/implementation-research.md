# Implementation Research: Discussion Thread Summarizer

## Reference

This document expands the feature brief at `agents/tasks/feature-1/feature-1.md`. Course discussions accumulate quickly, and by mid-semester a single thread can hold hundreds of replies. The feature adds (a) an on-demand summary block at the top of any discussion thread covering main themes, dominant viewpoints, and open questions, and (b) an instructor-only "Open Questions" digest aggregating unanswered student questions across a course. The feature is gated behind an admin-controlled toggle.

This file focuses only on research, requirements, and a verification plan.

---

## 1. Design considerations

### 1.1 User flows

**Student opens a discussion thread.**
The thread renders as it does today. Above the first reply, a summary block displays in one of three states: (i) cached summary present and current → render summary text; (ii) cached summary stale → render cached text with a "stale" badge and queue a refresh; (iii) no cached summary → render a "Generating summary…" placeholder while the asynchronous job runs and stream the result in when ready. The student can collapse the block, request a regenerate (subject to rate limits), or report an inaccurate summary.

**Instructor opens the course's "Open Questions" digest.**
The digest is reachable from the course's existing discussions index page via a new tab or link visible only to roles with `moderate_forum`-equivalent permissions. The digest lists candidate unanswered questions in reverse age order. Each row links to the source thread, anchored on the original question reply. An instructor can dismiss a question (marks it as "addressed offline") or jump to the thread to reply.

**Admin enables or disables the feature.**
A new feature flag is exposed in the existing account/course feature settings UI. Disabling the flag immediately suppresses the summary block and the digest tab; cached summaries are not deleted but become unreachable.

### 1.2 Data crossing boundaries

The most important boundary is the call from the application to the summarization model. The exact data sent depends on the configured scope mode:

- **Default scope.** The thread's reply text is sent to the model, with author display names replaced by stable per-thread pseudonyms (Author A, Author B…) before the request leaves the application boundary. This avoids passing names to a third-party model.
- **Scope-limited mode.** Only instructor posts and the viewer's own posts are sent. The summary is annotated to reflect the limited scope.
- **Self-hosted mode.** Same payload as default scope but routed to an institution-hosted endpoint; no third-party transit.

Every outbound call is logged with thread id, byte size, scope mode, model identifier, and latency. Raw payloads are not logged.

A second boundary is the cache: summary text is stored against a thread "content version" hash so that meaningful thread changes invalidate it. Summaries do not contain personally identifiable text by construction (because of the pseudonym pass), which simplifies later deletion and export concerns.

### 1.3 UX risks

- **Trust risk.** A confidently wrong summary is worse than no summary. The block must be visibly labeled as machine-generated, must show the time it was generated, and must be reportable in one click.
- **Bias risk.** Summaries may flatten minority viewpoints. The prompt explicitly asks for areas of disagreement; the report flow asks the user to specify "missed a viewpoint" as a reason category.
- **Discovery risk for the digest.** Instructors will not find the new tab unless it is placed in their existing discussions navigation. Avoid hiding it behind a settings page.
- **Notification risk.** The digest must not generate email or push notifications by default — instructors who want it can opt in. Otherwise the feature trains them to ignore it.

### 1.4 Interaction with existing platform concepts

- **Roles and permissions.** The summary block is governed by the same read permission as the thread itself (a user who cannot see the thread cannot see its summary). The instructor digest is gated by an existing forum-moderation permission. No new permission objects are introduced for this first version (v1).
- **Course and account hierarchy.** The feature flag follows the existing inherit-and-override pattern: account default → course override.
- **Discussion variants.** Anonymous discussions, group discussions, and locked discussions all need explicit handling. v1 supports standard threaded discussions and explicitly excludes anonymous discussions (out of scope) to avoid unmasking through summarization.
- **API surface.** Existing discussion REST and GraphQL responses are not changed in shape; the summary is exposed via additive fields and a new endpoint, never as a replacement.

### 1.5 Risk register (top items)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Summary misrepresents student posts | Medium | High | Pseudonymize, label as machine-generated, report flow, scope-limited mode option |
| LLM cost spikes on viral threads | Medium | Medium | Per-thread cache, regeneration rate limiting, content-version invalidation only |
| Privacy concerns block institutional adoption | Medium | High | Scope-limited mode, self-hosted mode, account-level toggle, audit log |
| Summarization service outage | Low | Low | Thread renders without summary; "summary unavailable" non-blocking state |
| Anonymous discussion unmasking | Low | High | Explicitly out of scope for v1; suppressed at the resolver layer |

---

## 2. Functional requirements

In-scope (v1) requirements are stated in `the system shall` form with a Given/When/Then test framing where it sharpens the requirement.

### FR-1 — Generate per-thread summary on demand
The system shall produce a summary of a discussion thread that names the main themes, dominant viewpoints, and open (unresolved) questions present in the thread.

- **Given** a discussion thread with at least five substantive replies and the feature flag enabled
- **When** a user with read access opens the thread for the first time, or clicks "Regenerate summary"
- **Then** the system displays a summary block above the first reply within an acceptable initial render time, asynchronously streaming if generation is not yet complete

### FR-2 — Cache and invalidate summaries on meaningful thread change
The system shall cache a summary against a content-version hash of the thread and shall invalidate that cache only when the thread's reply set changes by more than a configurable threshold.

- **Given** a thread with a current cached summary
- **When** the thread receives new replies whose combined token count exceeds the threshold, or replies are deleted at a rate above the threshold
- **Then** the cached summary is marked stale and a new summary is queued for generation

### FR-3 — Surface unanswered questions to instructors
The system shall provide an instructor-only digest that lists open questions from across all active discussions in a single course, ordered by question age.

- **Given** an instructor with forum-moderation permission in a course with at least one active discussion
- **When** the instructor opens the "Open Questions" digest for that course
- **Then** the system displays each candidate unanswered question with its source thread, age, and a deep link anchored to the question reply

### FR-4 — Honor account- and course-level feature toggles
The system shall not generate, render, or call out to the summarization model when the feature is disabled for the account or course in which the thread lives.

- **Given** a course whose feature flag resolves to off
- **When** any user opens any discussion thread in that course
- **Then** no summary block is rendered, no digest tab is shown, and no outbound model call is initiated

### FR-5 — Honor scope-limited content mode
The system shall, when scope-limited mode is enabled, send only instructor posts and the viewing user's own posts to the summarization model and shall annotate the resulting summary to disclose the limited scope.

- **Given** an account configured for scope-limited summary mode
- **When** a summary is generated for a viewer who is not an instructor
- **Then** the model receives only instructor posts and the viewer's own posts, and the rendered summary includes a visible disclosure that scope was limited

### FR-6 — Accept and record user reports of inaccurate summaries
The system shall let any user who can see a summary submit a structured report against that summary version.

- **Given** a rendered summary
- **When** a user opens the report action
- **Then** the user is presented with a fixed reason picker (inaccurate, missed a viewpoint, harmful content, other) and may add a short free-text comment, and the report is stored against the summary version with the reporter's role recorded

### FR-7 — Rate-limit regeneration
The system shall enforce a per-user, per-thread regeneration rate limit and a per-account daily generation budget.

- **Given** a thread that was summarized within the configured cool-down window
- **When** a user clicks "Regenerate"
- **Then** the system returns the cached summary unless the user holds an override permission, and surfaces a message indicating when regeneration will be available

### FR-8 — Graceful degradation when the summarization service is unavailable
The system shall render the discussion thread normally and shall display an unobtrusive "summary unavailable" state when the summarization service cannot be reached or returns an error.

- **Given** a summarization service that returns errors or times out
- **When** a user opens a thread
- **Then** the thread renders within its normal latency budget, the summary block displays an unavailable state, and the failure is recorded in the application's metrics without surfacing as a user-facing error toast

### Scope boundaries

| In scope (v1) | Out of scope |
|---|---|
| Standard threaded discussions | Anonymous discussions |
| Per-thread summary block on student and instructor views | Cross-course question digests |
| Instructor-only "Open Questions" digest within a single course | Auto-replying to student questions |
| Account- and course-level feature toggle | Sentiment analysis, participation scoring |
| Scope-limited and default content modes | Summarization of private messages |
| Cached summaries with content-version invalidation | Real-time live-updating summaries |
| Quality report flow with structured reasons | Admin review workflow for reports (logged only in v1) |

---

## 3. Non-functional requirements

### NFR-1 — Performance and latency
- Thread initial render must not be blocked by summary generation. The summary block renders independently and asynchronously.
- Summary generation for the median thread should complete within a target end-to-end budget agreed with the maintainers; threads above a configurable size go through a queued path with progress indication.
- Cache reads must be O(1) lookup against the content-version key; no full-thread rescans on the read path.

### NFR-2 — Security, privacy, and education-data handling
- Student-authored content is treated as sensitive. Author display names are replaced with per-thread pseudonyms before any content leaves the application boundary.
- An institutional opt-in toggle is required before any third-party model call is permitted on a tenant; default state on upgrade is off.
- A self-hosted endpoint deployment path is documented; no code path requires a third-party model.
- Outbound calls are recorded in an audit log with thread id, scope mode, model identifier, byte size, and latency. Raw request and response payloads are not persisted.
- Summaries inherit the read permissions of the underlying thread. Deleting a thread or its replies invalidates the cached summary on the same code path that handles thread deletion.

### NFR-3 — Accessibility
- The summary block, the regenerate action, the report action, and the digest list conform to WCAG 2.1 AA: keyboard reachable, focusable in a logical order, labeled for screen readers, with appropriate ARIA live-region semantics for the asynchronous "generating" state.
- Color is not the sole carrier of any state (stale, generating, unavailable).
- Text size and contrast match the existing discussion experience.

### NFR-4 — Observability
- Metrics: generation latency (p50, p95, p99), cache hit rate, error rate by failure mode, daily generation count by account, report submission count by reason category.
- Structured logs around each generation attempt with no PII; correlation id flows from the user request to the background job to the model call.
- A simple internal dashboard surfaces the above so feature owners can monitor a controlled rollout.

### NFR-5 — Reliability and graceful degradation
- The thread experience degrades gracefully under all summarization-service failure modes (timeout, rate limit, error, schema-violating output).
- A circuit breaker around the summarization service prevents cascading retries during an outage.
- A schema validator on model output discards malformed responses before they reach the cache or the user.

### NFR-6 — Deployment and platform compatibility
- Existing discussion REST and GraphQL response shapes are not modified; new fields are additive and nullable.
- The feature flag follows the existing account-then-course inheritance pattern and is documented alongside other feature flags.
- The change does not require new permission objects in v1; it reuses existing read and forum-moderation permissions.

---

## 4. Codebase analysis using the repository analysis agent

This section gives concrete instructions for using the repository analysis agent (`agents/analyze-repo.md`) against the Canvas LMS fork, captures hypotheses about where change will land, records the findings the agent should surface, and tracks open questions that still need a spike.

### 4.1 How to run the agent for this feature

1. **Open the agent spec.** Read `agents/analyze-repo.md` to confirm the agent's expected inputs, outputs, and any environment setup steps. The spec defines how the agent traverses the working clone and how it reports its findings.
2. **Position the working clone.** Ensure the agent runs against a clean checkout of the fork at the branch from which the feature will be developed. Stale branches will produce stale path findings.
3. **Run the queries below in order.** Each query is scoped to one decision the design depends on. Capture the agent's response under "Recorded findings" before moving on, so the trace from question to evidence stays intact.
4. **Record evidence inline.** For each query, paste a short excerpt of the agent's output (paths, symbol names, or a one-line summary) under that query's heading. Avoid full transcripts; the goal is traceability, not bulk.
5. **Tag any unanswered question** as an "Open question" at the bottom of this section so it cannot be lost.

### 4.2 Queries to run

**Q1. Where do discussion threads and replies live in the model layer?**
Goal: confirm the canonical model classes and their associations so the cache-invalidation hooks attach to the right place.

**Q2. Which controllers and GraphQL resolvers serve discussion thread data today?**
Goal: identify the additive surface for exposing summary fields without breaking existing response shapes.

**Q3. What permission method gates read access to a discussion thread, and which method gates forum moderation?**
Goal: confirm the feature can reuse existing permissions rather than introducing new ones.

**Q4. How are new feature flags declared and referenced in the codebase?**
Goal: follow the established account-then-course inheritance pattern for the new toggle.

**Q5. Which background-job pattern do similar asynchronous, course-scoped features use?**
Goal: select the right base class and queue conventions for the summarization job.

**Q6. Where is the new discussion experience rendered in the front-end bundles, and what is the recommended extension point for adding a UI block above the first reply?**
Goal: locate the React mount and confirm an additive insertion point.

**Q7. How do existing features cache derived content keyed against an underlying record version?**
Goal: pattern-match the cache layer against an established convention rather than inventing one.

**Q8. Where are audit-style logs emitted for outbound third-party calls, if any precedent exists?**
Goal: align the LLM-call audit log with existing observability patterns.

### 4.3 Hypotheses about where change will land

These are starting hypotheses, to be confirmed by the agent queries above.

- **Models.** The discussion thread model and the discussion entry model are the natural anchors for content-version computation and cache invalidation hooks.
- **Controllers / API.** Both REST and GraphQL paths exist. New summary fields are exposed additively on existing types; a small new endpoint or mutation handles regenerate and report actions.
- **Services / domain logic.** A new service object encapsulates the summarization workflow (gather → pseudonymize → call model → validate → cache). This service is the only path that talks to the model; everything else goes through it.
- **Background jobs.** Summarization is queued via the same job framework the rest of the codebase uses, so retry, backoff, and observability are inherited.
- **Front-end.** A new React component renders the summary block within the existing discussion topic view; a separate component renders the digest tab on the discussions index.
- **Feature flags.** A single new flag is added following the existing convention; defaults to off.
- **Permissions.** No new permission types; existing read and moderation permissions are reused.

### 4.4 Recorded findings

Agent's actual output during the analysis run:

1) **Discussion threads/replies in model layer**

Canonical classes are:

- `DiscussionTopic` = thread/topic root model, with `has_many :discussion_entries` and scoped root entries via `has_many :root_discussion_entries`.
- `DiscussionEntry` = replies/posts, with `belongs_to :discussion_topic` plus self-referential threading (`parent_entry`, `root_entry`, `discussion_subentries`).

```91:124:app/models/discussion_topic.rb
has_many :discussion_entries, -> { order(:created_at) }, dependent: :destroy, inverse_of: :discussion_topic
has_many :root_discussion_entries, -> { preload(:user).where("discussion_entries.parent_id IS NULL AND discussion_entries.workflow_state<>'deleted'") }, class_name: "DiscussionEntry"
...
has_many :summaries, class_name: "DiscussionTopicSummary"
has_many :insights, class_name: "DiscussionTopicInsight"
```

```37:52:app/models/discussion_entry.rb
has_many :discussion_subentries, -> { order(:created_at) }, class_name: "DiscussionEntry", foreign_key: "parent_id", inverse_of: :parent_entry
...
belongs_to :discussion_topic, inverse_of: :discussion_entries
belongs_to :parent_entry, class_name: "DiscussionEntry", foreign_key: :parent_id, inverse_of: :discussion_subentries
belongs_to :root_entry, class_name: "DiscussionEntry"
```

---

2) **Controllers + GraphQL resolvers serving discussion thread data today**

**Rails controllers (REST/HTML):**
- `DiscussionTopicsController` (`index`, `show`) serves page + JSON topic payload and mounts the `discussion_topics_post` bundle.
- `DiscussionTopicsApiController` serves API thread/topic data (`show`, `view`, `entries`, `replies`, `entry_list`, plus summary/insight endpoints).
- `DiscussionEntriesController` serves entry CRUD (legacy/non-GraphQL path).

**GraphQL surfaces:**
- Node loading: `GraphQLNodeLoader` resolves `"Discussion"` via `DiscussionTopic` with `:read` check.
- Query connection: `Interfaces::DiscussionsConnectionInterface` (used by `CourseType`) returns `discussions_connection`.
- Thread fields: `Types::DiscussionType` (`discussion_entries_connection`, `entry_counts`, etc.) and `Types::DiscussionEntryType`.
- Mutations in `Types::MutationType`: `create_discussion_entry`, `update_discussion_entry`, `update_discussion_entries_read_state`, `update_discussion_topic`, etc.

---

3) **Permission method for read + moderation**

From `DiscussionTopic` policy:

- **Read gate**: effectively `visible_for?(user)` (grants `:read`) and context permission `:read_forum`/`:read_announcements` inside `visible_for?`.
- **Moderation gate**: `context.grants_all_rights?(user, session, :moderate_forum, :read_forum)` (and related checks), plus explicit `can :moderate_forum`.

```1445:1502:app/models/discussion_topic.rb
given { |user| visible_for?(user) }
can :read
...
given { |user, session| context.grants_all_rights?(user, session, :moderate_forum, :read_forum) }
can :moderate_forum
```

---

4) **How feature flags are declared/referenced (account/course inheritance pattern)**

Pattern in this repo:

- Declare in YAML under `config/feature_flags/*.yml` with `applies_to` and `root_opt_in`.
- For course-level features requiring root-account opt-in: use `applies_to: Course` + `root_opt_in: true`.
- Optional companion root-account/shadow flag can control backend provider behavior.

Concrete precedent for discussions:

```2:13:config/feature_flags/discussion_summary.yml
discussion_summary:
  state: allowed
  root_opt_in: true
  applies_to: Course
...
discussion_summary_with_cedar:
  state: hidden
  applies_to: RootAccount
  shadow: true
```

References are then via `course.feature_enabled?(:discussion_summary)` and `Account.site_admin.feature_enabled?(:discussion_insights_with_cedar)` in model/controller code.

---

5) **Async course-scoped background-job pattern to mirror**

This codebase mostly uses **Delayed Job via model methods** (`delay` / `delay_if_production`) rather than `app/jobs` ActiveJob classes.

Strong discussion precedent:
- `DiscussionTopicsApiController#insight_generation` enqueues `insight.generate` with `priority`, `singleton`, and `n_strand` (regional/course-safe throttling).
- `DiscussionTopic::MaterializedView` uses `handle_asynchronously` and singleton dedupe.

```372:377:app/controllers/discussion_topics_api_controller.rb
insight.delay(
  priority: Delayed::HIGH_PRIORITY,
  singleton: "discussion_topic:insight_generation_for_topic:#{@topic.id}",
  n_strand: ["discussion_topic:insight_generation:#{Shard.current.database_server.region}", 1]
).generate
```

Recommendation based on local conventions: use `delay_if_production`/`delay` with `singleton` + `n_strand` keys for course-scoped summarization work.

---

6) **Where new discussion experience is rendered + best insertion point above first reply**

Render path:

- Controller: `DiscussionTopicsController#show` sets `js_bundle :discussion_topics_post`.
- Frontend entrypoint: `ui/features/discussion_topics_post/index.tsx` mounts `DiscussionTopicsPost` into `#discussion-redesign-layout`.
- Orchestration: `DiscussionTopicManager` renders `DiscussionTopicContainer`, then `DiscussionTopicRepliesContainer`.

Best additive insertion point “above first reply”:
- `DiscussionTopicRepliesContainer` wraps root replies in `discussion-root-entry-container` and maps each thread; adding a block before the map places content directly above first root reply.
- Alternative (higher-level): insert between `DiscussionTopicContainer` and `DiscussionTopicRepliesContainer` in `DiscussionTopicManager` if you want it between topic body and replies list.

---

7) **Existing cache/version-keyed derived-content patterns**

Two strong existing patterns:

- **Hash-keyed derived AI content**:
  - `DiscussionTopicSummary` requires `dynamic_content_hash` + `llm_config_version`.
  - `fetch_or_create_summary` dedupes by `(llm_config_version, dynamic_content_hash, parent)`.
  - Insights entries similarly hash content via `DiscussionTopicInsight::Entry.hash_for_dynamic_content`.

- **Record-version freshness check**:
  - `DiscussionTopic::MaterializedView#up_to_date?` checks `updated_at >= discussion_topic.updated_at` before serving cached structure.

So the repo already uses both “content hash key” and “source record timestamp/version” strategies.

---

8) **Audit-style logging precedent for outbound third-party calls**

For LLM/external calls, precedents are mixed but clear:

- **Persisted audit record approach**: `RubricLLMService` writes `LLMResponse` rows containing prompt config/model, dynamic content, raw response, tokens, response time, and root account.
- **Operational observability approach**: discussion summary/insight paths emit `InstStatsd` metrics, `Rails.logger.error`, and `Canvas::Errors.capture_exception(...)` for failures.
- **Structured audit infra precedent** (not LLM-specific): GraphQL mutations use `AuditLogFieldExtension` to write detailed mutation logs to DynamoDB.

If your goal is LLM-call auditability, the closest direct precedent is the `LLMResponse` persistence pattern in `RubricLLMService`; for reliability monitoring, mirror the `Statsd + Canvas::Errors` pattern already used in discussion summary/insights.

### 4.5 Open questions

Track unknowns that still need a spike or stakeholder input.

- Does the existing cache layer expose a content-version primitive, or does this feature need to define one?
- Is there an existing audit-log abstraction for outbound third-party calls, or is this the first such call in the project?
- For the digest, does the codebase already have a convention for "course-scoped instructor-only nav entry," or does this introduce one?
- Are there existing rate-limiting middleware or service helpers that the regenerate action can adopt, rather than building a new limiter?
- What is the existing test fixture story for discussions of meaningful size? Are there generators that can produce a thread of N substantive replies for performance tests?

### 4.6 Session notes

Capture short notes on the run itself: which branch was analyzed, how long the run took, anything the agent struggled with. This subsection is for traceability, not narrative.

---

## 5. Testing and verification plan

### 5.1 Unit-level expectations

The summarization service is the unit with the most behavior to cover. Tests use a stub model client and exercise:

- **Pseudonymization.** Given a fixture thread with named authors, the outbound payload contains only stable per-thread pseudonyms.
- **Scope filter.** Given scope-limited mode, the outbound payload contains only instructor posts and the viewer's own posts; default mode contains all reply text.
- **Output schema validation.** Malformed model output (missing fields, oversized fields, type-mismatched fields) is rejected and never reaches the cache.
- **Cache key.** The same thread state produces the same content-version hash; adding or removing replies above the threshold changes it; trivial edits do not.
- **Rate limiting.** A second regenerate request inside the cool-down window does not trigger an outbound call.
- **Permission gating.** A user without read access on the underlying thread cannot retrieve a summary even by direct id.

The cache invalidation policy and the open-question detector are also tested in isolation against fixture threads.

### 5.2 Integration points

- **Discussion API responses.** Smoke tests confirm that REST and GraphQL responses for an existing discussion are not changed in shape when the feature flag is off, and that summary fields appear additively when it is on.
- **Background job.** A test confirms that opening a thread without a cached summary enqueues a summarization job, and that the job produces a valid cache entry against a stub model.
- **Feature flag inheritance.** Tests confirm account-level off → course-level on resolves to on for that course, and account-level off without override resolves to off.
- **Audit log.** A test confirms that a generation attempt produces exactly one audit entry with the expected fields, regardless of outcome.
- **Outage path.** A test confirms that when the stub model raises a transport error, the thread renders normally, the summary block shows the unavailable state, and the failure is metric-counted.

### 5.3 Manual and exploratory checks

- **Role coverage.** Walk through the feature as: student, observer, TA, teacher, account admin. Confirm each role sees only what they should, and the digest tab is invisible to non-moderators.
- **Edge cases.** Empty thread, single-reply thread, thread with all replies deleted, thread containing very long single reply, group discussion, locked discussion, anonymous discussion (must show no summary block in v1).
- **Regression of nearby flows.** Replying, editing a reply, deleting a reply, grading a graded discussion, marking entries read or unread, subscribing to a thread.
- **Accessibility pass.** Keyboard-only walkthrough of the summary block and digest, screen reader walkthrough, focus order, contrast check on every state (cached, stale, generating, unavailable).
- **Bilingual content sanity check.** Threads in non-English languages produce summaries in the same language and do not lose content.

### 5.4 Acceptance criteria

Acceptance ties back to the functional requirements one for one:

| Functional requirement | Acceptance check |
|---|---|
| FR-1 | Opening a qualifying thread renders a summary block with themes, viewpoints, and open questions; regenerate works |
| FR-2 | Adding replies under threshold leaves the cached summary; crossing the threshold invalidates it |
| FR-3 | Instructor digest lists unanswered questions ordered by age, each linking to its source reply |
| FR-4 | With the flag off at the resolved scope, no block, no tab, and no outbound call occurs |
| FR-5 | Scope-limited mode strips other students' posts and discloses the limited scope in the rendered summary |
| FR-6 | Reporting flow records reason category and reporter role against the summary version |
| FR-7 | Regenerate inside the cool-down returns the cached summary; budget exhaustion is observable |
| FR-8 | Forced summarization-service failure leaves the thread fully usable and is captured in metrics |

### 5.5 Areas where automated coverage is impractical

- **Subjective summary quality.** Automated assertions cannot reliably judge whether a summary captures a thread's main points without becoming a brittle restatement of the prompt. Coverage is provided instead by a fixture set of curated threads with rubric-based human review at each release candidate, and by the production report flow as a continuous signal.
- **Cross-tenant performance under real load.** Replicating production-shaped discussion traffic in CI is impractical. Coverage is provided by a staged rollout behind the feature flag, with an explicit gating metric on p95 generation latency and cache hit rate before broadening the rollout.

---

## 6. Project planning handoff

This section is the primary input to the project-planning agent. It captures milestones, the work items each milestone implies, dependencies between them, and the definition of done that should apply to every story.

### 6.1 Milestones

1. **Foundations.** Feature flag declaration, account- and course-level toggle UI plumbing, permission audit and reuse decisions, baseline observability scaffolding.
2. **Summarization service.** Service object, model-client interface (mockable), pseudonymization, prompt schema, output validator, scope-limited content filter, audit log emission.
3. **Cache and invalidation.** Content-version hashing, cache reads and writes on the thread render path, invalidation hooks on reply create / edit / delete, regenerate rate limiter.
4. **Per-thread summary surface.** Backend additive fields on existing discussion responses, frontend summary block component, regenerate action, asynchronous generating state, unavailable state.
5. **Open questions digest.** Backend aggregation query, frontend tab and list component, navigation entry on the discussions index, dismissal action.
6. **Privacy controls.** Scope-limited mode end-to-end, self-hosted endpoint configuration documentation, audit log dashboard.
7. **Quality feedback loop.** Report action, reason picker, storage against summary version, simple internal admin view of recent reports.
8. **Hardening.** Accessibility pass, performance pass against large threads, observability dashboard polish, controlled rollout playbook.
9. **Stretch — institutional self-hosted model option.** Configuration, deployment notes, conformance test that the same payloads validate against both endpoints.

### 6.2 Dependencies

- Milestone 2 depends on Milestone 1 (feature flag and permission decisions must be in place before any model call is wired).
- Milestone 3 depends on Milestone 2 (cache layer caches what the service produces).
- Milestone 4 depends on Milestones 2 and 3.
- Milestone 5 depends on Milestone 4 for the open-question detector but can be developed in parallel from a UI standpoint once the backend aggregation query is defined.
- Milestone 6 depends on Milestone 2 for the scope filter and on Milestone 1 for the toggle UI.
- Milestone 7 depends on Milestone 4 (something to report against).
- Milestone 8 spans across all preceding milestones and is gated on them.
- Milestone 9 is independent of the user-visible flow and can run alongside Milestone 8.

### 6.3 Suggested story shapes (for the project-planning agent to expand)

For each milestone above, the planning agent should generate stories that cover, at minimum:

- The user-facing change (one story per surface or distinct user action).
- The backend or service work that makes the change possible.
- The tests that prove the requirement (unit, integration, or acceptance, as appropriate).
- The observability work (metric, log, or dashboard line) that lets owners know the new code is healthy.
- The documentation or release-note line that closes the loop.

Stories should reference the corresponding functional requirement (FR-1 through FR-8) so traceability holds end to end.

### 6.4 Definition of done (applied to every story)

- Code change is gated behind the feature flag at the resolved scope.
- Unit tests cover the new logic; integration tests cover the new surface where one exists.
- The corresponding functional requirement's acceptance check passes.
- Audit log and metric lines are emitted where relevant; the observability dashboard is updated.
- Accessibility is checked for any new user-facing element.
- A short release note is written describing the change behind the flag, even when the flag remains off.
- The story carries a link back to the functional requirement it satisfies.

### 6.5 What the project-planning agent must verify

After populating the project board, the planning agent must confirm:

- Every functional requirement (FR-1 through FR-8) is covered by at least one acceptance-bearing story.
- Every milestone has at least one observability story and at least one testing story.
- Dependencies between stories are recorded as project relationships, not only as prose.
- The scope boundary table is reflected as explicit "out of scope" notes on the relevant stories rather than absent from the plan.
