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

# Router-level integration gate for the audit-log one-entry guarantee (#37).
# Drives generation via POST .../thread_summary/regenerate + run_jobs, then
# inspects Rails.logger for the structured audit record emitted in
# SummarizationService#summarize's ensure block.
#
# Mirrors open_questions_digest_spec.rb (#33) style and location (spec/apis/v1/).
RSpec.describe "Discussion thread summarizer audit log (route-level gate, #37)", type: :request do
  before(:once) do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true, course: @course)
    @course.root_account.allow_feature!(:discussion_thread_summarizer)
    @course.enable_feature!(:discussion_thread_summarizer)
    @topic = @course.discussion_topics.create!(
      title:   "Audit gate thread",
      message: "Discuss here",
      user:    @teacher
    )
    @topic.discussion_entries.create!(user: @teacher, message: "Instructor post")
    @topic.discussion_entries.create!(user: @student, message: "Student reply")
  end

  before do
    @user = @teacher
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:check)
      .and_return(:allowed)
    allow(Rails.logger).to receive(:info) { |msg| logged_payloads << msg }
  end

  let(:logged_payloads) { [] }

  let(:regenerate_path) do
    "/api/v1/courses/#{@course.id}/discussion_topics/#{@topic.id}/thread_summary/regenerate"
  end
  let(:regenerate_params) do
    {
      controller: "discussion_topics_api",
      action:     "regenerate_thread_summary",
      format:     "json",
      course_id:  @course.id.to_s,
      topic_id:   @topic.id.to_s
    }
  end

  def audit_entries
    logged_payloads.select { |m| m.is_a?(String) && m.include?("generation_attempt") }
  end

  def trigger_and_run
    api_call(:post, regenerate_path, regenerate_params)
    run_jobs
  end

  # ── Example 1: success path ───────────────────────────────────────────────

  it "successful generation emits exactly one audit record with all required fields" do
    trigger_and_run

    expect(audit_entries.size).to eq(1)
    audit = JSON.parse(audit_entries.first, symbolize_names: true)
    expect(audit[:success]).to be(true)
    expect(audit[:error_category]).to be_nil
    expect(audit[:thread_id]).to eq(@topic.id)
    expect(audit[:scope_mode]).to be_a(String)
    expect(audit[:model_identifier]).to be_a(String)
    expect(audit[:request_byte_size]).to be_a(Integer)
    expect(audit[:latency_ms]).to be_a(Integer)
  end

  # ── Example 2: TransportError ────────────────────────────────────────────

  it "TransportError (stub) emits one record with success: false and error_category 'transport_error'" do
    allow_any_instance_of(DiscussionThreadSummarizer::StubModelClient).to receive(:summarize)
      .and_raise(DiscussionThreadSummarizer::TransportError, "stub transport failure")

    api_call(:post, regenerate_path, regenerate_params)
    # DJ catches the exception from the job; ensure block fires first, emitting audit log.
    run_jobs rescue nil

    expect(audit_entries.size).to eq(1)
    audit = JSON.parse(audit_entries.first, symbolize_names: true)
    expect(audit[:success]).to be(false)
    expect(audit[:error_category]).to eq("transport_error")
  end

  # ── Example 3: PII guard ─────────────────────────────────────────────────

  it "audit record contains no raw entry content or author names" do
    trigger_and_run

    raw = audit_entries.first
    expect(raw).not_to include("Instructor post")
    expect(raw).not_to include("Student reply")
    expect(raw).not_to match(/author_name|entries/)
    [@teacher, @student].each { |u| expect(raw).not_to include(u.short_name) if u.short_name.present? }
  end

  # ── Example 4: flag off ──────────────────────────────────────────────────

  it "flag-off path: route disables cleanly and no audit record is emitted" do
    @course.disable_feature!(:discussion_thread_summarizer)
    trigger_and_run
    expect(audit_entries).to be_empty
  end

  # ── Example 5: scope_mode "limited" ──────────────────────────────────────

  it "records scope_mode 'limited' when discussion_thread_summarizer_scope_limited is enabled" do
    @course.root_account.enable_feature!(:discussion_thread_summarizer_scope_limited)
    trigger_and_run
    audit = JSON.parse(audit_entries.first, symbolize_names: true)
    expect(audit[:scope_mode]).to eq("limited")
  end
end
