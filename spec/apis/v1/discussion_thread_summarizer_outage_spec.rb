# frozen_string_literal: true

#
# Copyright (C) 2026 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require_relative "../api_spec_helper"

# Full-stack outage-path integration gate for M8 (#49).
# Drives the real thread_summary render route (GET) via api_call.
# Injects a stub client that raises TransportError to trigger failure recording.
# Asserts degraded-but-not-500 behavior and circuit-open short-circuiting.
#
# Contracts encoded here (Cycle 37 #50 depends on them):
#   - Single transient failure (circuit still closed): render returns :generating.
#   - N consecutive failures: circuit opens; subsequent render returns :unavailable.
#   - An existing current/stale cached row is always served — open circuit blocks
#     generation, not reads.
#   - Open circuit never produces an HTTP error or error envelope in the JSON body.
RSpec.describe "Discussion thread summarizer outage path (M8 gate, #49)", type: :request do
  # ── Route recognition guard ──────────────────────────────────────────────────
  # Guards against a future route reorder silently re-breaking this gate.
  # Mirrors the pattern from open_questions_digest_spec.rb (#33).
  it "thread_summary route resolves to the correct action" do
    course_with_teacher(active_all: true)
    recognized = Rails.application.routes.recognize_path(
      "/api/v1/courses/#{@course.id}/discussion_topics/1/thread_summary",
      method: :get
    )
    expect(recognized[:action]).to eq("thread_summary")
    expect(recognized[:controller]).to eq("discussion_topics_api")
  end

  # ── AR fixtures (shared for remaining examples) ───────────────────────────
  before(:once) do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true, course: @course)
    @course.root_account.allow_feature!(:discussion_thread_summarizer)
    @course.enable_feature!(:discussion_thread_summarizer)
    @topic = @course.discussion_topics.create!(
      title:   "Outage gate thread",
      message: "Discuss here",
      user:    @teacher
    )
    @topic.discussion_entries.create!(user: @teacher, message: "Teacher post")
    @topic.discussion_entries.create!(user: @student, message: "Student reply")
  end

  before do
    @user = @teacher
    # Force-load SchemaViolationError so error_category_for in summarize#ensure
    # can reference it without a NameError (mirrors summarization_service_spec.rb).
    DiscussionThreadSummarizer::OutputSchemaValidator
    # Rate limiter: always allow so requests reach the model client / circuit check.
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:check)
      .and_return(:allowed)
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview)
      .and_return(:allowed)
    # Reset circuit state between examples (real Redis).
    DiscussionThreadSummarizer::CircuitBreaker.reset!(account: @course.root_account)
    # Suppress audit log noise.
    allow(Rails.logger).to receive(:info)
  end

  let(:render_path) do
    "/api/v1/courses/#{@course.id}/discussion_topics/#{@topic.id}/thread_summary"
  end
  let(:render_params) do
    {
      controller: "discussion_topics_api",
      action:     "thread_summary",
      format:     "json",
      course_id:  @course.id.to_s,
      topic_id:   @topic.id.to_s
    }
  end

  # Helper: drive one generation failure through the real async path.
  # enqueue_for → run_jobs (raises TransportError) → failed_at set on the job.
  # After failure, the singleton is released (failed_at IS NULL check in DJ),
  # so the next call can enqueue a new job.
  def drive_one_failure
    DiscussionThreadSummarizer::SummarizationService.enqueue_for(
      discussion_topic: @topic,
      viewer:           @teacher
    )
    run_jobs rescue nil
  end

  # ── Example 1: single TransportError — circuit still closed ───────────────
  # One failure does NOT open the circuit (threshold default = 5). The render
  # path returns :generating (job enqueued, no cached row). The generation_error
  # metric fires from the job, and the thread endpoint always returns HTTP 200.
  it "single TransportError: GET returns HTTP 200 with status 'generating', generation_error metric fires" do
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
      .and_raise(DiscussionThreadSummarizer::TransportError, "connection refused")
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)

    error_increments = 0
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_generation_error) do
      error_increments += 1
    end

    # GET enqueues the generation job (circuit closed, no cached row → :generating).
    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    # Single failure: circuit stays closed; no cached row → :generating.
    expect(json["status"]).to eq("generating")
    expect(json).not_to have_key("error")
    expect(json).not_to have_key("errors")

    # Run the job — TransportError fires; generation_error incremented.
    run_jobs rescue nil
    expect(error_increments).to be >= 1
  end

  # ── Example 2: N consecutive failures → circuit opens → client skipped ────
  # Drives N real TransportError raises through enqueue_for + run_jobs (real
  # async path). After the Nth failure record_failure opens the circuit. The
  # subsequent GET short-circuits in lookup_for_render without calling the
  # client at all.
  it "after N consecutive failures the circuit opens and subsequent GET skips the client" do
    threshold = DiscussionThreadSummarizer::CircuitBreaker::DEFAULT_FAILURE_THRESHOLD.to_i

    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)

    # Count all client invocations during the failure-driving phase.
    failure_calls = 0
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize) do
      failure_calls += 1
      raise DiscussionThreadSummarizer::TransportError, "service down"
    end

    # Drive N real failures through the async path.
    threshold.times { drive_one_failure }

    expect(failure_calls).to eq(threshold)
    expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_open)
      .at_least(:once)

    # Override stub: any post-open call would indicate the breaker didn't fire.
    post_open_calls = 0
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize) do
      post_open_calls += 1
      DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE
    end

    # Circuit is open. GET must short-circuit: HTTP 200, unavailable, no client call.
    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("unavailable")
    expect(json).not_to have_key("error")
    expect(json).not_to have_key("errors")
    expect(post_open_calls).to eq(0),
      "model client must not be called when circuit is open (got #{post_open_calls} call(s))"
  end

  # ── Example 3: open circuit serves existing cached row unchanged ──────────
  # Verifies Fix 1 AC: "the thread renders normally while the circuit is open."
  # An existing :current summary must be served even when the breaker is open.
  it "open circuit serves an existing current cached row without calling the client" do
    # Seed a cached summary row for @topic by running one successful generation.
    DiscussionThreadSummarizer::SummarizationService.enqueue_for(
      discussion_topic: @topic,
      viewer:           @teacher
    )
    run_jobs
    expect(@topic.summaries.count).to eq(1)

    # Drive failures through a separate "burner" topic so fetch_or_create_summary
    # always misses the cache (no row for the burner) and reaches the client.
    # The circuit is per-account, so burner failures open the breaker for @topic too.
    burner = @course.discussion_topics.create!(
      title: "Burner topic for circuit test",
      message: "Failure driver",
      user: @teacher
    )
    burner.discussion_entries.create!(user: @teacher, message: "Burner entry")

    threshold = DiscussionThreadSummarizer::CircuitBreaker::DEFAULT_FAILURE_THRESHOLD.to_i
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
      .and_raise(DiscussionThreadSummarizer::TransportError, "service down")

    threshold.times do
      DiscussionThreadSummarizer::SummarizationService.enqueue_for(
        discussion_topic: burner,
        viewer:           @teacher
      )
      run_jobs rescue nil
    end

    expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_open).at_least(:once)

    # Track any post-open client calls — there must be none.
    client_calls = 0
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize) do
      client_calls += 1
      DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE
    end

    # GET for @topic must serve the cached row (status :current) despite the open circuit.
    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("current")
    expect(json["summary"]).not_to be_nil
    expect(client_calls).to eq(0),
      "model client must not be called when serving a cached row (got #{client_calls} call(s))"
  end

  # ── Half-open recovery ───────────────────────────────────────────────────────
  # Drives N real failures, lets the cooldown elapse, then verifies the recovery
  # path: probe acquired by generation → client called → circuit closed.
  # Also verifies: render does not consume the probe; exactly one generation
  # attempt reaches the client per half-open window.
  context "half-open recovery" do
    let(:account) { @course.root_account }

    before do
      # 1-second cooldown so the half-open window is reachable without a long sleep.
      # Pass-through for all other Setting.get calls so the job infrastructure works.
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get)
        .with(DiscussionThreadSummarizer::CircuitBreaker::COOLDOWN_SETTING_KEY, anything)
        .and_return("1")

      threshold = DiscussionThreadSummarizer::CircuitBreaker::DEFAULT_FAILURE_THRESHOLD.to_i
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)
      allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
        .and_raise(DiscussionThreadSummarizer::TransportError, "service down")
      threshold.times { drive_one_failure }
      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_open).at_least(:once)

      # Wait for the 1-second Redis TTL on cooldown_key to expire.
      sleep(1.5)
      expect(DiscussionThreadSummarizer::CircuitBreaker.state(account:)).to eq(:half_open)
    end

    it "closes the circuit and emits circuit_closed after a successful probe" do
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_closed)
      allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
        .and_return(DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE)

      DiscussionThreadSummarizer::SummarizationService.enqueue_for(
        discussion_topic: @topic,
        viewer: @teacher
      )
      run_jobs

      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_closed)
        .with(account:, scope_mode: anything)
      expect(DiscussionThreadSummarizer::CircuitBreaker.state(account:)).to eq(:closed)
      expect(@topic.summaries.reload.count).to be >= 1
    end

    it "render does not consume the probe; the subsequent generation job still reaches the client" do
      client_calls = 0
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_closed)
      allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize) do
        client_calls += 1
        DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE
      end

      # Render must not consume the probe.
      api_call(:get, render_path, render_params)
      expect(response).to have_http_status(:ok)
      expect(DiscussionThreadSummarizer::CircuitBreaker.state(account:)).to eq(:half_open),
        "render must not consume the probe — circuit must remain half-open"

      # Generation job (enqueued by render) acquires the probe and reaches the client.
      run_jobs
      expect(client_calls).to eq(1),
        "generation job must reach the client (probe not consumed by render)"
      expect(DiscussionThreadSummarizer::CircuitBreaker.state(account:)).to eq(:closed)
    end

    it "only one generation attempt per window reaches the client; loser returns :unavailable" do
      # Hold the probe, simulating a concurrent winner that beat us to it.
      expect(DiscussionThreadSummarizer::CircuitBreaker.try_acquire_probe(account:)).to be(true)

      client_calls = 0
      allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize) do
        client_calls += 1
        DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE
      end

      # Second attempt (probe already held) must short-circuit without calling the client.
      result = DiscussionThreadSummarizer::SummarizationService.new.fetch_or_create_summary(
        discussion_topic: @topic,
        viewer: @teacher
      )
      expect(result.status).to eq(:unavailable)
      expect(client_calls).to eq(0), "loser must not call the client — probe already held"
    end

    it "failed probe re-opens the circuit; subsequent render returns :unavailable" do
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)
      allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
        .and_raise(DiscussionThreadSummarizer::TransportError, "still down")

      # Drive one probe attempt that fails — circuit must re-open.
      DiscussionThreadSummarizer::SummarizationService.enqueue_for(
        discussion_topic: @topic,
        viewer: @teacher
      )
      run_jobs rescue nil

      expect(DiscussionThreadSummarizer::CircuitBreaker.state(account:)).to eq(:open),
        "failed half-open probe must re-open the circuit"
      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_open)
        .at_least(:once)

      # Subsequent render with no cached row must return :unavailable, not :generating.
      json = api_call(:get, render_path, render_params)
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("unavailable")
    end
  end

  # ── Example 4: no error envelope (inline unavailable status only) ─────────
  it "unavailable state carries no error envelope — inline status field only" do
    threshold = DiscussionThreadSummarizer::CircuitBreaker::DEFAULT_FAILURE_THRESHOLD.to_i
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
      .and_raise(DiscussionThreadSummarizer::TransportError, "service down")
    threshold.times { drive_one_failure }

    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("unavailable")
    expect(json["enabled"]).to be(true)
    expect(json).not_to have_key("error")
    expect(json).not_to have_key("errors")
  end
end
