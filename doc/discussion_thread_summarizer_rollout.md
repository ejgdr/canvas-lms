# Discussion Thread Summarizer — Observability Dashboard & Controlled Rollout Playbook

This document covers the Datadog panel set for the Discussion Thread Summarizer feature
and the controlled rollout procedure. Dashboards live in Datadog (not in-repo UI) — this
file records the query strings and the process gate for rollout.

> **Process gate:** The dashboard and rollout plan below require **one maintainer sign-off
> before rollout begins.** This PR cannot self-satisfy that gate. The sign-off records that
> the maintainer has reviewed the gate-metric thresholds (§ Gate metrics) and the rollout
> stages (§ Rollout stages) and approves proceeding.

---

## Dashboard panels

Canvas dashboards are maintained in Datadog. Each panel below maps to an already-emitted
`InstStatsd` metric (see `lib/discussion_thread_summarizer/metrics.rb`). **No new metric
pipeline is needed** — every panel reads an existing `distributed_increment` or `timing`
counter.

All `account_id` tag values are cross-shard-safe `global_id` integers (never institution
names or user identifiers).

### 1. Generation latency — p50 / p95 / p99

Metric: `discussion_thread_summarizer.generation_latency_ms`
Tags: `account_id`, `scope_mode`

```
p50:avg:discussion_thread_summarizer.generation_latency_ms{*} by {account_id,scope_mode}
p95:avg:discussion_thread_summarizer.generation_latency_ms{*} by {account_id,scope_mode}
p99:avg:discussion_thread_summarizer.generation_latency_ms{*} by {account_id,scope_mode}
```

Covers only completed model-client calls (not cache hits or rate-limit short-circuits).
p95 budget is **pending maintainer sign-off** — the measured baseline from a ~100-reply
thread test run is recorded in the Cycle 37 implementation-evidence table; a formal SLO
threshold must be confirmed with the team before rollout.

### 2. Cache hit / miss / stale rate

Metrics:
- `discussion_thread_summarizer.cache.hit` (tags: `account_id`)
- `discussion_thread_summarizer.cache.miss` (tags: `account_id`)
- `discussion_thread_summarizer.cache.stale` (tags: `account_id`)

```
sum:discussion_thread_summarizer.cache.hit{*} by {account_id}.as_count()
sum:discussion_thread_summarizer.cache.miss{*} by {account_id}.as_count()
sum:discussion_thread_summarizer.cache.stale{*} by {account_id}.as_count()
```

Target cache hit rate ≥ 80 % under repeated-read soak. Threshold is
**pending maintainer sign-off** (§5.5 gate).

Derived hit-rate panel:

```
(sum:discussion_thread_summarizer.cache.hit{*}.as_count() /
  (sum:discussion_thread_summarizer.cache.hit{*}.as_count() +
   sum:discussion_thread_summarizer.cache.miss{*}.as_count())) * 100
```

### 3. Error rate by failure mode

Metric: `discussion_thread_summarizer.failure` (tags: `account_id`, `reason`)

Valid `reason` values: `quota_exceeded`, `throttled`, `schema_invalid`,
`transport_error`, `unknown`.

```
sum:discussion_thread_summarizer.failure{*} by {account_id,reason}.as_count()
```

### 4. Daily generation count by account and scope mode

Metric: `discussion_thread_summarizer.generation_attempt`
Tags: `account_id`, `scope_mode`

```
sum:discussion_thread_summarizer.generation_attempt{*} by {account_id,scope_mode}.as_count()
```

### 5. Report submission count by reason

Metric: `discussion_thread_summarizer.report_submitted`
Tags: `account_id`, `reason`, `reporter_role`

```
sum:discussion_thread_summarizer.report_submitted{*} by {account_id,reason}.as_count()
```

### 6. Circuit-breaker open / close events over time

Metrics:
- `discussion_thread_summarizer.circuit_open` (tags: `account_id`, `scope_mode`)
- `discussion_thread_summarizer.circuit_closed` (tags: `account_id`, `scope_mode`)

These are **transition counters**, not a current-state gauge — there is no
`circuit_state` metric. Build the panel as open / close events over time per account
and scope mode.

```
sum:discussion_thread_summarizer.circuit_open{*} by {account_id,scope_mode}.as_count()
sum:discussion_thread_summarizer.circuit_closed{*} by {account_id,scope_mode}.as_count()
```

A rising `circuit_open` rate without matching `circuit_closed` events indicates the
downstream model service is degraded and the circuit is staying open. Escalate to
the upstream model team if this persists across two cooldown cycles.

---

## Gate metrics and thresholds

The following five metrics are the explicit §5.5 rollout gates. Thresholds marked
**[pending sign-off]** must be confirmed with the maintainer before rollout begins.

| Gate | Metric | Threshold |
|------|--------|-----------|
| G1 | p95 generation latency | **[pending sign-off]** — measured baseline TBD |
| G2 | Cache hit rate (rolling 1 h) | ≥ 80 % **[pending sign-off]** |
| G3 | Error rate (all failure modes) | < 1 % of generation attempts |
| G4 | Circuit-breaker open events | 0 per rolling 15 min at steady state |
| G5 | Report submission rate | No spike above 2× baseline on rollout day |

---

## Rollout stages

All stages gated on maintainer sign-off (§ Process gate above) before starting Stage 1.

| Stage | Accounts enabled | Hold period | Proceed condition |
|-------|-----------------|-------------|-------------------|
| 1 | 5 % | 48 h | All gates G1–G5 green |
| 2 | 20 % | 48 h | All gates G1–G5 green |
| 3 | 50 % | 72 h | All gates G1–G5 green |
| 4 | 100 % | — | All gates G1–G5 green |

Mechanism: use the Canvas feature flag admin UI to set
`discussion_thread_summarizer` to `on` for sampled root accounts at each stage.

---

## Rollback procedure

**Set the course-level feature flag off.** Summaries become unreachable but are
**not deleted** — rows remain in `discussion_topic_summaries` for recovery.

```ruby
# Rails console — disable for all accounts at once
Account.root_accounts.each do |acct|
  acct.disable_feature!(:discussion_thread_summarizer)
end
```

Or via the admin UI: Settings → Feature Options → Discussion Thread Summarizer → Off.

### Rollback triggers

Rollback immediately if any of the following occur:

- G1 (p95 latency) exceeds 3× the pre-rollout baseline for > 5 minutes.
- G2 (cache hit rate) drops below 50 % for > 15 minutes after Stage 2+.
- G3 (error rate) exceeds 5 % for > 5 minutes.
- G4: circuit breaker opens on > 10 % of accounts simultaneously.
- User-visible data-accuracy complaints spike above 3× daily baseline.

### Escalation / contact path

1. Oncall SRE via PagerDuty — uses the Datadog dashboard above.
2. Feature team lead — review circuit-breaker open events and model-service status.
3. Model service provider — if `transport_error` failures dominate the error panel.

---

## Measurement note — p95 baseline (Cycle 37 #47)

The p95 generation latency for a ~100-reply thread test run is recorded in
`agents/tasks/feature-1/implementation-evidence.md` under "M8 Cycle 37 performance numbers."
The G1 budget threshold is **pending maintainer sign-off** and must be confirmed before
Stage 1 rollout.
