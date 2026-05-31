# Discussion Thread Summarizer — REST/GraphQL summary embed

## Release note

When the `discussion_thread_summarizer` course feature is enabled, the Discussion Topic REST `show`/`view` responses and GraphQL `Discussion.summary` field include an optional `summary` object (`text`, `status`, `generated_at`). When the flag is off, response shapes are unchanged.

The dedicated `GET .../thread_summary` endpoint also includes a `regeneration` object (`available`, optional `retry_after_seconds`, optional `reason`) so clients can render regenerate cooldown state. `POST .../thread_summary/regenerate` enqueues manual regeneration when allowed; returns `429` with `retry_after_seconds` on cooldown deny or `quota_exhausted` when the daily budget is spent.

## Surfaces

| Surface | Flag off | Flag on, cached | Flag on, generating | Flag on, not started |
|---------|----------|-----------------|---------------------|---------------------|
| REST `show` | no `summary` key | `summary` object | `{ status: "generating", ... }` | `summary: null` |
| REST `view` | no `summary` key | `summary` object | `{ status: "generating", ... }` | `summary: null` |
| GraphQL `Discussion.summary` | `null` | object | object (`generating`) | `null` |

Status values: `current`, `stale`, `generating`, `unavailable` (rate-limited stale). `generating` is returned when a background job has been enqueued but no cache row exists yet. `null` is returned only when generation has not started (e.g. rate-limited empty probe).

Implementation reuses `DiscussionThreadSummarizer::SummarizationService#lookup_for_render` and `DiscussionThreadSummarizer::TopicSummaryEmbed`.
