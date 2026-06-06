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

# #47 — Performance regression guard: no N+1 on the summarizer render path.
#
# Methodology: two *fresh* DiscussionTopic objects (1-entry baseline and 10-entry
# scaled) are loaded via DiscussionTopic.find immediately before each measurement so
# that their AR association caches are cold. This ensures a per-entry query (N+1)
# adds N-1 extra DB hits and causes the count to differ.
#
# Feature-flag and Setting lookups are warmed separately (via a throwaway topic
# call in before) to eliminate that one-time cold-cache noise without warming the
# topics under test. The measured assertion is exact equality — not <=.
#
# Verified: temporarily injecting `fresh_topic.discussion_entries.to_a` inside
# the measured block (forcing per-row AR loads) causes the 10-entry count to
# exceed the 1-entry count by 9, failing the spec.
describe DiscussionThreadSummarizer::SummarizationService do
  def count_queries
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      count += 1 unless sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  let(:course)  { course_model }
  let(:user)    { user_model }
  let(:service) { described_class.new }

  let(:cached_summary_json) do
    {themes: ["T"], viewpoints: ["V"], open_questions: ["Q?"], scope_mode: "default"}.to_json
  end

  before do
    course.enable_feature!(:discussion_thread_summarizer)
    allow(Canvas).to receive(:redis_enabled?).and_return(false)
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview).and_return(:allowed)
    allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:check).and_return(:allowed)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_render_current)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_render_stale)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_render_generating)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_cache_hit)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_cache_miss)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_rate_limit_allowed)
    allow(described_class).to receive(:enqueue_for)

    # Warm feature-flag / Setting lookups using a throwaway topic so those one-time
    # cold-cache DB hits don't skew the 1-entry vs 10-entry comparison below.
    warmup_topic = course.discussion_topics.create!
    warmup_topic.discussion_entries.create!(user:, message: "warmup")
    service.lookup_for_render(discussion_topic: warmup_topic, viewer: user, locale: "en")
  end

  def build_topic_with_entries(n)
    t = course.discussion_topics.create!
    n.times { |i| t.discussion_entries.create!(user:, message: "entry #{i}") }
    content_hash = DiscussionThreadSummarizer::ContentVersionHash.call(t)
    t.summaries.create!(
      llm_config_version: described_class::LLM_CONFIG_VERSION,
      dynamic_content_hash: content_hash,
      user:,
      locale: "en",
      summary: cached_summary_json,
      parent_id: nil
    )
    t.id # return the id so we can reload fresh
  end

  describe "lookup_for_render — O(1) query count (no N+1)" do
    it "issues the same number of queries for 1 entry as for 10 entries" do
      id_1  = build_topic_with_entries(1)
      id_10 = build_topic_with_entries(10)

      # Reload fresh: cold AR association cache, no pre-loaded entries collection.
      queries_1 = count_queries do
        service.lookup_for_render(discussion_topic: DiscussionTopic.find(id_1), viewer: user, locale: "en")
      end

      queries_10 = count_queries do
        service.lookup_for_render(discussion_topic: DiscussionTopic.find(id_10), viewer: user, locale: "en")
      end

      expect(queries_10).to eq(queries_1),
        "Query count grew from #{queries_1} (1 entry) to #{queries_10} (10 entries) — " \
        "N+1 detected on the render path"
    end
  end

  describe "fetch_or_create_summary — cache-hit path O(1)" do
    it "issues the same number of queries for 1 entry as for 10 entries on cache hit" do
      id_1  = build_topic_with_entries(1)
      id_10 = build_topic_with_entries(10)

      queries_1 = count_queries do
        service.fetch_or_create_summary(discussion_topic: DiscussionTopic.find(id_1), viewer: user, locale: "en")
      end

      queries_10 = count_queries do
        service.fetch_or_create_summary(discussion_topic: DiscussionTopic.find(id_10), viewer: user, locale: "en")
      end

      expect(queries_10).to eq(queries_1),
        "Cache-hit query count grew from #{queries_1} (1 entry) to #{queries_10} (10 entries) — " \
        "N+1 detected on the cache-hit path"
    end
  end

  describe "ContentVersionHash.call — single bulk pluck (no N+1)" do
    it "issues exactly 1 query regardless of entry count" do
      id_1  = build_topic_with_entries(1)
      id_10 = build_topic_with_entries(10)

      # Load topics before the measurement window: DiscussionTopic.find itself
      # is not the operation under test and must not be counted.
      topic_1  = DiscussionTopic.find(id_1)
      topic_10 = DiscussionTopic.find(id_10)

      queries_1 = count_queries do
        DiscussionThreadSummarizer::ContentVersionHash.call(topic_1)
      end

      queries_10 = count_queries do
        DiscussionThreadSummarizer::ContentVersionHash.call(topic_10)
      end

      expect(queries_1).to eq(1),
        "ContentVersionHash.call should issue exactly 1 query, got #{queries_1}"
      expect(queries_10).to eq(queries_1),
        "ContentVersionHash.call query count grew: #{queries_1} → #{queries_10} (N+1 detected)"
    end
  end
end
