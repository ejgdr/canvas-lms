# Discussion Thread Summarizer — self-hosted endpoint configuration

This document describes how to point the Discussion Thread Summarizer at an
institution-operated model endpoint. The service uses constructor dependency
injection, so no code path requires a third-party model (NFR-2).

## Current mechanism: injectable `ModelClient`

`SummarizationService` accepts a `client:` keyword argument on `initialize`. The
default is `DiscussionThreadSummarizer::StubModelClient`, which returns a fixed
deterministic response — suitable for local development and CI. To route to an
institution-hosted endpoint, supply a concrete `ModelClient` subclass:

```ruby
# app/services/discussion_thread_summarizer/my_model_client.rb
class DiscussionThreadSummarizer::MyModelClient < DiscussionThreadSummarizer::ModelClient
  def summarize(payload)
    # POST payload to your endpoint; return Hash with :themes, :viewpoints,
    # :open_questions, :scope_mode.
    # Raise DiscussionThreadSummarizer::TransportError on unrecoverable failure.
  end
end
```

Pass the adapter at the job entry point (the only place `SummarizationService` is
instantiated for production use):

```ruby
DiscussionThreadSummarizer::SummarizationService.new(
  client: DiscussionThreadSummarizer::MyModelClient.new
)
```

No Setting record, env var, or feature flag is needed to swap the adapter — the
injection point is the sole production call site.

## Env-var–driven provider selection

Runtime selection via `SUMMARIZER_ENDPOINT_URL` (and companion
`SUMMARIZER_ENDPOINT_TOKEN`) is tracked in issue
[#51](https://github.com/ejgdr/canvas-lms/issues/51). Until that work lands, the
adapter must be wired at the call site as shown above.

## Verifying traffic via the audit log

Every `SummarizationService#summarize` call emits one JSON audit line through
`Rails.logger.info`. The `model_identifier` field records `@client.class.name` —
the Ruby class name of the adapter in use, never the raw endpoint URL.

Filter production logs for lines containing `"generation_attempt"`:

```json
{
  "event": "discussion_thread_summarizer.generation_attempt",
  "thread_id": 12345,
  "scope_mode": "default",
  "model_identifier": "DiscussionThreadSummarizer::MyModelClient",
  "request_byte_size": 1024,
  "latency_ms": 342,
  "success": true,
  "error_category": null
}
```

`model_identifier` lets ops teams confirm which adapter handled each call without
logging sensitive URL or credential values.

## Smoke-test procedure

1. Enable the `discussion_thread_summarizer` feature flag on a test course:
   ```ruby
   course.enable_feature!(:discussion_thread_summarizer)
   ```
2. Instantiate the service with your adapter and enqueue a job:
   ```ruby
   svc = DiscussionThreadSummarizer::SummarizationService.new(
     client: DiscussionThreadSummarizer::MyModelClient.new
   )
   svc.delay.fetch_or_create_summary(discussion_topic: topic, viewer: teacher)
   ```
3. Drain the queue: `Delayed::Worker.new.work_off`
4. Check Rails logs for a line with `"event": "discussion_thread_summarizer.generation_attempt"`.
5. Confirm `"model_identifier"` matches your adapter class and `"success": true`.
6. Verify `discussion_thread_summarizer.generation_attempt` increments in your metrics
   backend (see the observability doc for the Datadog panel query).

If `"success": false`, `"error_category"` identifies the failure class
(`"transport_error"`, `"schema_invalid"`, or `"unknown"`). Confirm your adapter
returns a Hash matching the schema in `model_client.rb`.
