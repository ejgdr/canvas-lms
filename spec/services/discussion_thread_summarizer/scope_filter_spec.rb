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

# Cycle 31 (#35, #39) — Scope-limited content filter + disclosure unit tests.
#
# FR-5 acceptance criteria:
#   1. scope-limited: payload sent to model has only instructor + viewer posts;
#      the three other-student posts are absent (count == 2, not 5).
#   2. stub-rendered result includes disclosure string when scope is limited.
#   3. default mode: all posts (5) present; no disclosure in result.
#   4. No network access — capture client substitutes for a real LLM call.
#   5. Filter driven by belongs_to :user (entry.user_id) matched against
#      TeacherEnrollment/TaEnrollment types, which are the enrollments that
#      grant grants_right?(user, :moderate_forum) in Canvas policy (#35 spec).
#
# Thread fixture: 1 instructor (TeacherEnrollment), 1 viewer (StudentEnrollment),
# 3 other students (StudentEnrollment).
describe "DiscussionThreadSummarizer scope-limited filter and disclosure (#35, #39)" do
  # Capture client records the payload passed to #summarize and returns a
  # structurally-valid response that mirrors the request's scope_mode.
  # No network access — this is the injectable model stub required by #39.
  let(:capture_client) do
    Class.new(DiscussionThreadSummarizer::ModelClient) do
      attr_reader :last_payload

      def summarize(payload)
        @last_payload = payload
        {
          themes:         ["A theme"],
          viewpoints:     ["A viewpoint"],
          open_questions: ["A question"],
          scope_mode:     payload[:scope_mode] || "default"
        }
      end
    end.new
  end

  let(:service) { DiscussionThreadSummarizer::SummarizationService.new(client: capture_client) }

  let(:course)     { course_model }
  let(:account)    { course.root_account }
  let(:topic)      { course.discussion_topics.create! }

  # Teacher: has :moderate_forum via TeacherEnrollment (Canvas policy rule)
  let(:instructor) { user_model }
  # Viewer: requesting student whose own posts must be included even in limited mode
  let(:viewer)     { user_model }
  # Three other students excluded in scope-limited mode (no :moderate_forum, not viewer)
  let(:other1)     { user_model }
  let(:other2)     { user_model }
  let(:other3)     { user_model }

  before do
    course.enable_feature!(:discussion_thread_summarizer)
    # Suppress Statsd metric calls fired by invalidation callbacks on entry creation
    allow(InstStatsd::Statsd).to receive(:distributed_increment)

    # Enroll instructor as Teacher (grants :moderate_forum in Canvas discussion policy)
    course.enroll_teacher(instructor, enrollment_state: :active)
    # Enroll viewer and three others as Students (no :moderate_forum grant)
    [viewer, other1, other2, other3].each { |u| course.enroll_student(u, enrollment_state: :active) }

    # One discussion entry per user
    topic.discussion_entries.create!(user: instructor, message: "Instructor post")
    topic.discussion_entries.create!(user: viewer,     message: "Viewer post")
    topic.discussion_entries.create!(user: other1,     message: "Other student 1")
    topic.discussion_entries.create!(user: other2,     message: "Other student 2")
    topic.discussion_entries.create!(user: other3,     message: "Other student 3")

    # Suppress audit log lines
    allow(Rails.logger).to receive(:info)
  end

  # ── Scope-limited mode ────────────────────────────────────────────────────

  context "when discussion_thread_summarizer_scope_limited is enabled" do
    before do
      account.enable_feature!(:discussion_thread_summarizer_scope_limited)
    end

    it "sends only instructor and viewer entries to the model (2 entries, 3 other-students absent)" do
      service.summarize(discussion_topic: topic, viewer:)

      # The payload entries are pseudonymized ("Author A", "Author B"…) at this point.
      # Assert count == 2: instructor post + viewer post; the 3 other students are excluded.
      # The filter is driven by entry.user_id (belongs_to :user) checked against
      # instructor_user_ids (TeacherEnrollment/TaEnrollment → grants :moderate_forum)
      # unioned with viewer.id.
      expect(capture_client.last_payload[:entries].size).to eq(2)
    end

    it "sets scope_mode to 'limited' in the request payload" do
      service.summarize(discussion_topic: topic, viewer:)
      expect(capture_client.last_payload[:scope_mode]).to eq("limited")
    end

    it "adds the disclosure string to the returned result" do
      result = service.summarize(discussion_topic: topic, viewer:)
      expect(result[:disclosure]).to eq("Based on instructor posts and your posts only")
    end

    it "includes a TA-enrolled user (TaEnrollment also grants :moderate_forum)" do
      ta = user_model
      course.enroll_ta(ta, enrollment_state: :active)
      topic.discussion_entries.create!(user: ta, message: "TA post")

      service.summarize(discussion_topic: topic, viewer:)

      # Now 3 allowed: instructor (Teacher) + ta (TA) + viewer → 3 entries
      expect(capture_client.last_payload[:entries].size).to eq(3)
    end
  end

  # ── Default mode ─────────────────────────────────────────────────────────

  context "when discussion_thread_summarizer_scope_limited is disabled" do
    before do
      account.disable_feature!(:discussion_thread_summarizer_scope_limited)
    end

    it "includes all five entries in the payload (no filtering)" do
      service.summarize(discussion_topic: topic, viewer:)
      expect(capture_client.last_payload[:entries].size).to eq(5)
    end

    it "sets scope_mode to 'default' in the request payload" do
      service.summarize(discussion_topic: topic, viewer:)
      expect(capture_client.last_payload[:scope_mode]).to eq("default")
    end

    it "does not add a disclosure string to the returned result" do
      result = service.summarize(discussion_topic: topic, viewer:)
      expect(result[:disclosure]).to be_nil
    end
  end

  # ── ContentVersionHash differentiates scope modes and viewers ──────────────

  context "ContentVersionHash cache-key invariants (#35)" do
    it "produces different hashes for 'default' vs 'limited' on the same topic" do
      hash_default = DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "default")
      hash_limited = DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "limited", viewer:)
      expect(hash_default).not_to eq(hash_limited)
    end

    it "produces the same hash for the same topic, scope_mode, and viewer on repeated calls" do
      h1 = DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "limited", viewer:)
      h2 = DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "limited", viewer:)
      expect(h1).to eq(h2)
    end

    it "raises ArgumentError when scope_mode is 'limited' but viewer is nil" do
      expect do
        DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "limited", viewer: nil)
      end.to raise_error(ArgumentError, /viewer is required/)
    end
  end

  # ── Per-viewer cache isolation in scope-limited mode ─────────────────────

  context "per-viewer cache isolation (#35 privacy requirement)" do
    let(:viewer_b) { user_model }

    before do
      account.enable_feature!(:discussion_thread_summarizer_scope_limited)
      course.enroll_student(viewer_b, enrollment_state: :active)
      topic.discussion_entries.create!(user: viewer_b, message: "Viewer B post")
    end

    it "viewer A and viewer B get distinct dynamic_content_hash values" do
      hash_a = DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "limited", viewer:)
      hash_b = DiscussionThreadSummarizer::ContentVersionHash.call(topic, scope_mode: "limited", viewer: viewer_b)
      expect(hash_a).not_to eq(hash_b)
    end

    it "viewer B's fetch_or_create_summary never returns viewer A's cached summary row" do
      allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:check)
        .and_return(:allowed)

      # Populate cache for viewer A
      service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale: "en")
      expect(topic.summaries.count).to eq(1)
      viewer_a_row = topic.summaries.last

      # Viewer B must get a separate row, not viewer A's
      service.fetch_or_create_summary(discussion_topic: topic, viewer: viewer_b, locale: "en")
      expect(topic.summaries.count).to eq(2)

      viewer_b_row = topic.summaries.order(created_at: :asc).last
      expect(viewer_b_row.dynamic_content_hash).not_to eq(viewer_a_row.dynamic_content_hash)
    end

    it "viewer B's payload excludes viewer A's posts (only includes viewer B's own + instructor posts)" do
      service_b = DiscussionThreadSummarizer::SummarizationService.new(client: capture_client)
      service_b.summarize(discussion_topic: topic, viewer: viewer_b)

      # viewer_b is a student (not instructor); their allowed set = instructor posts + viewer_b.id
      # viewer A's posts should not appear (viewer_b ≠ viewer_a and viewer_a is not an instructor)
      # The payload has: instructor (1) + viewer_b (1) = 2 entries
      expect(capture_client.last_payload[:entries].size).to eq(2)
    end
  end
end
