# M9 Spike Report — Swappable Model Provider Interface (#51)

**Author:** Cycle 38 agent  
**Date:** 2026-06-06  
**Outcome: A** — existing DI + thin adapter + env-var selection is sufficient

---

## Question

Is `SummarizerModelClient` (from #7) swappable as-is for a self-hosted endpoint,
or does it require a new abstraction layer?

---

## Finding: Outcome A

The existing infrastructure is sufficient. No new abstraction layer is needed.
Evidence:

1. **`ModelClient` is already abstract.** `app/services/discussion_thread_summarizer/model_client.rb`
   defines an abstract base class with `#summarize(payload)` — the contract is already
   expressed as a Ruby interface.

2. **`SummarizationService` already uses constructor DI.** `initialize(client: StubModelClient.new)`
   accepts any `ModelClient` subclass. The only production instantiation is in
   `enqueue_for`, which is a single method.

3. **A thin subclass is all that is needed.** `SelfHostedModelClient < ModelClient` POSTs
   to `SUMMARIZER_ENDPOINT_URL` via `Net::HTTP` (not `CanvasHttp` — see "Why Net::HTTP"
   below) and maps the JSON response to the same return shape. No core-service code
   changes on the call path.

4. **Proof of concept confirmed.** Adding `ModelClientFactory.build` (checks
   `ENV["SUMMARIZER_ENDPOINT_URL"]`) and calling it from `enqueue_for` routes traffic
   to the self-hosted adapter via configuration alone. The call path in
   `fetch_or_create_summary → summarize → @client.summarize` is unchanged.

---

## Configuration mechanism

| Mechanism | Role |
|-----------|------|
| `ENV["SUMMARIZER_ENDPOINT_URL"]` | Selects the self-hosted adapter when set |
| `ENV["SUMMARIZER_ENDPOINT_TOKEN"]` | Optional bearer token; omit if network-auth is used |
| `ModelClientFactory.build` | Single selection point called in `enqueue_for` |
| `discussion_thread_summarizer_with_cedar` shadow flag | Separate — routes to Canvas Cedar proxy; independent of self-hosted path |

The selection wires through the existing DI injection point (`SummarizationService.new(client: ...)`),
not a new path. No new feature flag is added for the adapter switch; the operator env var
is the control.

---

## Why Net::HTTP, not CanvasHttp

`CanvasHttp.request` applies SSRF guards (`insecure_host?`) that block private IP
ranges (`10.0.0.0/8`, `192.168.0.0/16`, `127.0.0.1/8`, etc.) — precisely the
addresses an institution would use for a self-hosted endpoint. These guards are
designed to defend against user-supplied URLs, not operator-configured deployment
config. Using `Net::HTTP` directly is the correct approach for a trusted, operator-
configured service endpoint.

---

## Request/response schema differences

The schema is defined by `OutputSchemaValidator` (from #10):

Required keys: `:themes` (Array\<String\>), `:viewpoints` (Array\<String\>),
`:open_questions` (Array\<String\>), `:scope_mode` (String).

A self-hosted endpoint may return **extension fields** (e.g. `confidence_score`,
`provider`). The validator only checks required keys — extensions pass silently.
The conformance suite (#53) records extra fields as test warnings, not failures.

No schema differences are forced — institutions must conform to the required
four-key contract. Non-conforming responses raise `SchemaViolationError` exactly as
they do for the third-party adapter.

---

## model_identifier

The existing `model_identifier` field in the audit log uses `@client.class.name`.
For `SelfHostedModelClient`, this would emit `"DiscussionThreadSummarizer::SelfHostedModelClient"`
— technically correct but not operationally useful (which instance?).

To satisfy NFR-2's requirement that the identifier names the endpoint without
logging the raw URL:

- Added `model_identifier` virtual method to `ModelClient` base (default: `self.class.name`).
- Overridden in `SelfHostedModelClient` to return `"self-hosted:<host><path>"` — strips
  scheme, credentials, query string, and fragment. Operators can identify the endpoint
  from logs without credentials being captured.
- `SummarizationService#summarize` now calls `@client.model_identifier` instead of
  `@client.class.name`.

---

## Estimated work to productionize

Already complete in this cycle:

| Task | Status |
|------|--------|
| `SelfHostedModelClient` with Net::HTTP, timeouts, error mapping | ✅ Cycle 38 |
| `ModelClientFactory` with env-var selection | ✅ Cycle 38 |
| `enqueue_for` wired to factory | ✅ Cycle 38 |
| `model_identifier` override + audit log updated | ✅ Cycle 38 |
| Operator docs (env vars, Docker Compose, k8s, smoke test) | ✅ Cycle 38 |
| Conformance spec (both adapters, same fixtures, schema validator) | ✅ Cycle 38 |

No known follow-up work. The adapter is production-ready modulo the operator's
endpoint implementation — Canvas delivers the client; the institution supplies
the LLM server.

---

## Open question for maintainers (AC4)

No clean **Canvas-internal** precedent for swappable model providers was found
in the codebase. The closest analogues (`InstLLM::ServiceClient`, `RubricLLMService`)
are not swappable via env var — they hardcode a single provider. This spike
establishes the first env-var-driven provider selection point for any Canvas LLM
feature.

**Flag to maintainers:** If a future cycle adds a second provider (e.g. a real
third-party HTTP adapter), `ModelClientFactory.build` should be extended with an
explicit selection key (e.g. `SUMMARIZER_PROVIDER=third_party|self_hosted|stub`),
not a second URL env var. The current two-value branch (URL set vs. not set) is
sufficient for the M9 use case.
