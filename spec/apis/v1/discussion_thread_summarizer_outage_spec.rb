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
    # Rate limiter: always allow so the model client is reached.
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:check)
      .and_return(:allowed)
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview)
      .and_return(:allowed)
    # Reset circuit state between examples.
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

  # ── Example 1: TransportError → HTTP 200, generation_error incremented ────
  # Drives the real GET route. Generation runs via run_jobs (async path).
  it "TransportError emits generation_error metric and the thread endpoint returns HTTP 200" do
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
      .and_raise(DiscussionThreadSummarizer::TransportError, "connection refused")
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)

    # Capture generation_error calls via spy so we can assert after run_jobs.
    error_increments = 0
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_generation_error) do
      error_increments += 1
    end

    # First GET enqueues the generation job.
    api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)

    # Run the job — TransportError fires; generation_error incremented.
    run_jobs rescue nil

    expect(error_increments).to be >= 1

    # After the job fails the circuit may be open; a subsequent GET must be 200
    # with no error envelope.
    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    expect(json).not_to have_key("error")
    expect(json).not_to have_key("errors")
  end

  # ── Example 2: circuit opens after N failures → skips client ─────────────
  # Opens the circuit directly via record_failure (avoids DJ singleton-dedup
  # complexity when driving N sequential failures through run_jobs).
  it "after N consecutive failures the circuit opens and subsequent calls skip the client" do
    threshold = DiscussionThreadSummarizer::CircuitBreaker::DEFAULT_FAILURE_THRESHOLD.to_i

    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)

    # Drive N failures to open the circuit.
    threshold.times do
      DiscussionThreadSummarizer::CircuitBreaker.record_failure(
        account:    @course.root_account,
        scope_mode: "default"
      )
    end

    expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_open)
      .at_least(:once)

    # Track client invocations — must not increase once circuit is open.
    call_count = 0
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize) do
      call_count += 1
      DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE
    end

    # Circuit is open. GET /thread_summary must return HTTP 200 with status
    # "unavailable" and must NOT invoke the model client.
    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("unavailable")
    expect(call_count).to eq(0),
      "expected model client NOT to be called when circuit is open, " \
      "but got #{call_count} call(s)"
  end

  # ── Example 3: no error envelope (inline unavailable only) ───────────────
  it "unavailable state carries no error envelope — inline status field only" do
    threshold = DiscussionThreadSummarizer::CircuitBreaker::DEFAULT_FAILURE_THRESHOLD.to_i
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)
    threshold.times do
      DiscussionThreadSummarizer::CircuitBreaker.record_failure(
        account:    @course.root_account,
        scope_mode: "default"
      )
    end

    json = api_call(:get, render_path, render_params)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("unavailable")
    expect(json["enabled"]).to be(true)
    expect(json).not_to have_key("error")
    expect(json).not_to have_key("errors")
  end
end
