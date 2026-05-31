# Discussion Thread Summarizer — observability (M3)

Cycle 20 completes the NFR-4 `cache.*` metric family alongside existing `render.*` (render-state) and `invalidation.*` (write-side) families. These are **parallel telemetry paths**, not aliases: stale summary serve dual-emits `render.stale` and `cache.stale`; invalidation dual-emits `invalidation.fired` and `cache.invalidated` (with `trigger:` `reply_create` / `reply_edit` / `reply_delete`). Stale-to-fresh ratio dashboards are tracked in issue #50.

## Generation latency (M4)

When the `discussion_thread_summarizer` course feature is enabled, completed background generations emit InstStatsd timing on `discussion_thread_summarizer.generation_latency_ms` (tags: `account_id`, `scope_mode`). Attempts and failures increment `discussion_thread_summarizer.generation_attempt` and `discussion_thread_summarizer.generation_error` respectively. Latency measures wall-clock from `@client.summarize` through schema validation only — not cache lookup or rate-limiter probes. Cache hits and rate-limiter short-circuits do not emit generation metrics.
