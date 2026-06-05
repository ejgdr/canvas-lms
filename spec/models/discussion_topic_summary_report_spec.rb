# frozen_string_literal: true

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

describe DiscussionTopicSummaryReport do
  subject(:report) { described_class.new(attributes) }

  let(:course) { course_model }
  let(:topic) { discussion_topic_model(context: course) }
  let(:summary) do
    topic.summaries.create!(
      llm_config_version: "thread-summarizer-v1",
      dynamic_content_hash: "abc123",
      summary: "Test summary",
      user: teacher_in_course(course:, active_all: true).user,
      locale: "en"
    )
  end
  let(:student) { student_in_course(course:, active_all: true).user }
  let(:attributes) do
    {
      discussion_topic_summary: summary,
      user: student,
      reason: "inaccurate",
      reporter_role: "student"
    }
  end

  before do
    allow(InstStatsd::Statsd).to receive(:distributed_increment).and_return(nil)
  end

  # ── reason categories ──────────────────────────────────────────────────────

  DiscussionTopicSummaryReport::REASONS.each do |reason|
    it "persists with reason #{reason}" do
      report.reason = reason
      expect(report.save).to be true
      expect(report.reload.reason).to eq(reason)
    end
  end

  # ── reporter_role ──────────────────────────────────────────────────────────

  it "persists with reporter_role student" do
    expect(report.save).to be true
    expect(report.reporter_role).to eq("student")
  end

  it "persists with reporter_role teacher" do
    teacher = teacher_in_course(course:, active_all: true).user
    report.user = teacher
    report.reporter_role = "teacher"
    expect(report.save).to be true
    expect(report.reporter_role).to eq("teacher")
  end

  it "persists with reporter_role admin" do
    report.reporter_role = "admin"
    expect(report.save).to be true
    expect(report.reporter_role).to eq("admin")
  end

  # ── cache isolation ────────────────────────────────────────────────────────

  it "does not change dynamic_content_hash or updated_at on the summary" do
    original_hash       = summary.dynamic_content_hash
    original_updated_at = summary.updated_at

    report.save!

    summary.reload
    expect(summary.dynamic_content_hash).to eq(original_hash)
    expect(summary.updated_at).to eq(original_updated_at)
  end

  # ── comment validation ─────────────────────────────────────────────────────

  it "rejects a comment exceeding 500 characters" do
    report.comment = "a" * 501
    expect(report).not_to be_valid
    expect(report.errors[:comment]).to be_present
  end

  it "accepts a comment of exactly 500 characters" do
    report.comment = "a" * 500
    expect(report).to be_valid
  end

  it "accepts a nil comment" do
    report.comment = nil
    expect(report).to be_valid
  end

  # ── reason validation ──────────────────────────────────────────────────────

  it "rejects an unknown reason" do
    report.reason = "bogus"
    expect(report).not_to be_valid
    expect(report.errors[:reason]).to be_present
  end

  # ── metric emission ────────────────────────────────────────────────────────

  it "emits report_submitted metric with reason and reporter_role tags" do
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_report_submitted)
    report.save!
    DiscussionThreadSummarizer::Metrics.increment_report_submitted(
      reason: report.reason,
      reporter_role: report.reporter_role
    )
    expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_report_submitted).with(
      reason: "inaccurate",
      reporter_role: "student"
    )
  end

  it "emits metric with no user_id in tags" do
    allow(InstStatsd::Statsd).to receive(:distributed_increment)
    DiscussionThreadSummarizer::Metrics.increment_report_submitted(
      reason: "other",
      reporter_role: "teacher"
    )
    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
      "discussion_thread_summarizer.report_submitted",
      tags: { reason: "other", reporter_role: "teacher" }
    )
  end
end
