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

# Integration tests for SummarizationService.enqueue_for.
# Uses real AR fixtures (Course, DiscussionTopic, DiscussionEntry, User) and
# drives Delayed Job through its real execution path via run_jobs/run_job.
#
# Scope: M2 async pipeline + M3 cache write (Cycle 16).
# AC2: after run_jobs, one DiscussionTopicSummary row with expected dynamic_content_hash.
# "Thread open" is simulated by direct enqueue_for calls — controller wiring
# is M4 work.

describe "DiscussionThreadSummarizer::SummarizationService async integration" do
  # ── AR fixtures ────────────────────────────────────────────────────────────

  let(:course)   { course_factory(active_all: true) }
  let(:teacher)  { teacher_in_course(course:, active_all: true).user }
  let(:student)  { student_in_course(course:, active_all: true).user }
  let(:topic) do
    course.discussion_topics.create!(
      title:   "Test thread",
      message: "Discuss here",
      user:    teacher
    )
  end

  before do
    # Create two real entries so gather has something to process.
    topic.discussion_entries.create!(message: "Teacher says hello.", user: teacher)
    topic.discussion_entries.create!(message: "Student replies.",    user: student)
    # Silence the audit log in non-capturing examples.
    allow(Rails.logger).to receive(:info)
  end

  let(:singleton_key) do
    "discussion_thread_summarizer:generation_for_topic:#{topic.id}"
  end

  # ── Example 1: exactly one job with the correct singleton key ─────────────

  it "enqueue_for creates exactly one Delayed::Job with the correct singleton key" do
    expect do
      DiscussionThreadSummarizer::SummarizationService.enqueue_for(
        discussion_topic: topic,
        viewer:           teacher
      )
    end.to change { Delayed::Job.where(singleton: singleton_key).count }.by(1)

    expect(Delayed::Job.where(singleton: singleton_key).count).to eq(1)
  end

  # ── Example 2: singleton dedup with real DB ────────────────────────────────

  it "a second enqueue_for for the same topic while the first is pending is a no-op" do
    DiscussionThreadSummarizer::SummarizationService.enqueue_for(
      discussion_topic: topic,
      viewer:           teacher
    )
    expect(Delayed::Job.where(singleton: singleton_key).count).to eq(1)

    # Second call — the singleton key already exists in the DB.
    DiscussionThreadSummarizer::SummarizationService.enqueue_for(
      discussion_topic: topic,
      viewer:           teacher
    )
    expect(Delayed::Job.where(singleton: singleton_key).count).to eq(1)
  end

  # ── Example 3: job runs end-to-end ────────────────────────────────────────

  it "when the job runs, the pipeline completes: audit log success: true, no failure metric" do
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_failure)

    logged_payloads = []
    allow(Rails.logger).to receive(:info) { |msg| logged_payloads << msg }

    DiscussionThreadSummarizer::SummarizationService.enqueue_for(
      discussion_topic: topic,
      viewer:           teacher
    )

    expect { run_jobs }.not_to raise_error

    # Delayed::Worker emits non-JSON [STAT] lines; find our structured record.
    audit_entry = logged_payloads.find { |m| m.is_a?(String) && m.include?("generation_attempt") }
    expect(audit_entry).not_to be_nil, "expected an audit log entry but none was found"
    audit = JSON.parse(audit_entry, symbolize_names: true)
    expect(audit[:success]).to be(true)
    expect(audit[:error_category]).to be_nil
    expect(audit[:event]).to eq("discussion_thread_summarizer.generation_attempt")
    expect(audit[:thread_id]).to eq(topic.id)

    expect(DiscussionThreadSummarizer::Metrics).not_to have_received(:increment_failure)

    expected_hash = DiscussionThreadSummarizer::ContentVersionHash.call(topic)
    summaries = DiscussionTopicSummary.where(discussion_topic: topic)
    expect(summaries.count).to eq(1)
    expect(summaries.first.dynamic_content_hash).to eq(expected_hash)
    expect(summaries.first.llm_config_version)
      .to eq(DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION)
  end
end
