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

# #47 — Performance regression guard for the summarizer render path.
# Uses an exact equality check (not <=) between a 1-entry run and a 10-entry run
# on the same topic. Because both measurements hit the same warmed caches, any
# per-entry extra query (N+1) shows up as a count difference of exactly N-1.
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
  let(:topic)   { course.discussion_topics.create! }
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
  end

  def plant_cached_summary
    content_hash = DiscussionThreadSummarizer::ContentVersionHash.call(topic)
    topic.summaries.create!(
      llm_config_version: described_class::LLM_CONFIG_VERSION,
      dynamic_content_hash: content_hash,
      user:,
      locale: "en",
      summary: cached_summary_json,
      parent_id: nil
    )
  end

  # Run the block once to warm AR association caches and feature-flag lookups,
  # then measure a second run in the warm state. This isolates the query count
  # to the actual work (not cold-start AR loads), making the delta comparison
  # between 1-entry and 10-entry meaningful.
  def warm_then_count(&block)
    block.call # warmup
    count_queries(&block)
  end

  describe "lookup_for_render — O(1) query count (no N+1)" do
    it "issues the same number of queries for 1 entry as for 10 entries" do
      topic.discussion_entries.create!(user:, message: "first entry")
      plant_cached_summary
      queries_1 = warm_then_count do
        service.lookup_for_render(discussion_topic: topic, viewer: user, locale: "en")
      end

      # Add 9 more entries and refresh the cached summary hash
      9.times { |i| topic.discussion_entries.create!(user:, message: "entry #{i + 2}") }
      DiscussionTopicSummary.where(discussion_topic: topic).find_each do |s|
        s.update!(dynamic_content_hash: DiscussionThreadSummarizer::ContentVersionHash.call(topic))
      end
      queries_10 = warm_then_count do
        service.lookup_for_render(discussion_topic: topic, viewer: user, locale: "en")
      end

      expect(queries_10).to eq(queries_1),
        "Query count grew from #{queries_1} (1 entry) to #{queries_10} (10 entries) — " \
        "N+1 detected on the render path"
    end
  end

  describe "fetch_or_create_summary — cache-hit path O(1)" do
    it "issues the same number of queries for 1 entry as for 10 entries on cache hit" do
      topic.discussion_entries.create!(user:, message: "single entry")
      plant_cached_summary
      queries_1 = warm_then_count do
        service.fetch_or_create_summary(discussion_topic: topic, viewer: user, locale: "en")
      end

      9.times { |i| topic.discussion_entries.create!(user:, message: "entry #{i + 2}") }
      DiscussionTopicSummary.where(discussion_topic: topic).find_each do |s|
        s.update!(dynamic_content_hash: DiscussionThreadSummarizer::ContentVersionHash.call(topic))
      end
      queries_10 = warm_then_count do
        service.fetch_or_create_summary(discussion_topic: topic, viewer: user, locale: "en")
      end

      expect(queries_10).to eq(queries_1),
        "Cache-hit query count grew from #{queries_1} (1 entry) to #{queries_10} (10 entries) — " \
        "N+1 detected on the cache-hit path"
    end
  end

  describe "ContentVersionHash.call — single bulk pluck (no N+1)" do
    it "issues exactly 1 query regardless of entry count" do
      topic.discussion_entries.create!(user:, message: "a")
      queries_1 = warm_then_count { DiscussionThreadSummarizer::ContentVersionHash.call(topic) }

      9.times { |i| topic.discussion_entries.create!(user:, message: "b#{i}") }
      queries_10 = warm_then_count { DiscussionThreadSummarizer::ContentVersionHash.call(topic) }

      expect(queries_1).to eq(1),
        "ContentVersionHash.call should issue exactly 1 query, got #{queries_1}"
      expect(queries_10).to eq(queries_1),
        "ContentVersionHash.call query count grew: #{queries_1} → #{queries_10} (N+1 detected)"
    end
  end
end
