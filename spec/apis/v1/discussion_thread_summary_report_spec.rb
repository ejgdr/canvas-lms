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

# Real-router integration gate for the M7 report submission endpoint (#41/#42).
# Mirrors discussion_thread_summarizer_audit_log_spec.rb style and location.
# Exercises routing, auth, DB persistence, metric emission, and
# "no-summary-side-effect" guarantee.
RSpec.describe "Discussion thread summary report (M7 integration gate)", type: :request do
  before(:once) do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true, course: @course)
    @course.root_account.allow_feature!(:discussion_thread_summarizer)
    @course.enable_feature!(:discussion_thread_summarizer)

    @topic = @course.discussion_topics.create!(
      title:   "Report gate thread",
      message: "Discuss here",
      user:    @teacher
    )
    @topic.discussion_entries.create!(user: @teacher, message: "Instructor post")
    @topic.discussion_entries.create!(user: @student, message: "Student reply")

    content_hash = DiscussionThreadSummarizer::ContentVersionHash.call(@topic)
    @summary = @topic.summaries.create!(
      user:                 @teacher,
      locale:               "en",
      summary:              DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE.to_json,
      dynamic_content_hash: content_hash,
      llm_config_version:   DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION
    )
  end

  before do
    @user = @student
    allow(InstStatsd::Statsd).to receive(:distributed_increment).and_return(nil)
  end

  let(:report_path) do
    "/api/v1/courses/#{@course.id}/discussion_topics/#{@topic.id}/thread_summary/report"
  end

  let(:report_route_params) do
    {
      controller: "discussion_topics_api",
      action:     "report_thread_summary",
      format:     "json",
      course_id:  @course.id.to_s,
      topic_id:   @topic.id.to_s
    }
  end

  def post_report(reason:, comment: nil, user: @student)
    @user = user
    params = {reason:}
    params[:comment] = comment if comment
    api_call(:post, report_path, report_route_params, params)
  end

  # ── Example 1: 201, DB row, user_id hidden ────────────────────────────────

  it "returns 201 and persists the report row with all required fields" do
    expect { post_report(reason: "inaccurate", comment: "Off by a paragraph") }
      .to change(DiscussionTopicSummaryReport, :count).by(1)

    expect(response).to have_http_status(:created)

    report = DiscussionTopicSummaryReport.last
    expect(report.reason).to eq("inaccurate")
    expect(report.comment).to eq("Off by a paragraph")
    expect(report.reporter_role).to eq("student")
    expect(report.user_id).to eq(@student.id)
  end

  it "response JSON does not include user_id" do
    post_report(reason: "other")

    json = response.parsed_body
    expect(json).not_to have_key("user_id")
    expect(json["reason"]).to eq("other")
    expect(json["reporter_role"]).to eq("student")
  end

  # ── Example 2: metric emitted with correct tags ───────────────────────────

  it "emits the report_submitted metric with reason and reporter_role tags" do
    post_report(reason: "missed_viewpoint", user: @teacher)

    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
      "discussion_thread_summarizer.report_submitted",
      hash_including(tags: hash_including(reason: "missed_viewpoint", reporter_role: "teacher"))
    )
  end

  # ── Example 3: report does not mutate the summary ────────────────────────

  it "submitting a report does not change the summary content_hash or enqueue a job" do
    original_hash   = @summary.reload.dynamic_content_hash
    job_count_before = Delayed::Job.count

    post_report(reason: "harmful_content")

    expect(@summary.reload.dynamic_content_hash).to eq(original_hash)
    expect(Delayed::Job.count).to eq(job_count_before)
  end

  # ── Example 4: flag off → 404 ─────────────────────────────────────────────

  it "returns 404 when the feature flag is off" do
    @course.disable_feature!(:discussion_thread_summarizer)

    post_report(reason: "inaccurate")

    expect(response).to have_http_status(:not_found)
  ensure
    @course.enable_feature!(:discussion_thread_summarizer)
  end

  # ── Example 5a: invalid reason → 422 ────────────────────────────────────

  it "returns 422 when reason is not a valid enum value" do
    post_report(reason: "not_a_valid_reason")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(DiscussionTopicSummaryReport.count).to eq(0)
  end

  # ── Example 5b: comment > 500 → 422 ──────────────────────────────────────

  it "returns 422 when comment exceeds 500 characters" do
    post_report(reason: "other", comment: "x" * 501)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(DiscussionTopicSummaryReport.count).to eq(0)
  end

  # ── Example 6: multiple reports against same summary all persist ──────────

  it "allows multiple reports against the same summary version" do
    expect do
      post_report(reason: "inaccurate")
      post_report(reason: "missed_viewpoint")
      post_report(reason: "other")
    end.to change(DiscussionTopicSummaryReport, :count).by(3)

    reports = DiscussionTopicSummaryReport.where(discussion_topic_summary: @summary)
    expect(reports.map(&:reason)).to match_array(%w[inaccurate missed_viewpoint other])
    reports.each { |r| expect(r.discussion_topic_summary_id).to eq(@summary.id) }
  end
end
