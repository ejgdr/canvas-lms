# Discussion Thread Summarizer — observability (M3)

Cycle 20 completes the NFR-4 `cache.*` metric family alongside existing `render.*` (render-state) and `invalidation.*` (write-side) families. These are **parallel telemetry paths**, not aliases: stale summary serve dual-emits `render.stale` and `cache.stale`; invalidation dual-emits `invalidation.fired` and `cache.invalidated` (with `trigger:` `reply_create` / `reply_edit` / `reply_delete`). Stale-to-fresh ratio dashboards are tracked in issue #50.
