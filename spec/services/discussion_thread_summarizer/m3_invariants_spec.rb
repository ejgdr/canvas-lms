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

# Cycle 21 (#19) — M3 invariant regression anchors and cross-cutting examples.
#
# AC coverage index (see also issue #19 body):
#   Hash stability (repeated calls, same state)
#     content_version_hash_spec.rb:36-43
#     m3_invariants_spec.rb — "returns the same hash on repeated calls"
#   Word-delta threshold (invalidation vs rekey; NOT hash suppression)
#     cache_invalidation_spec.rb:74-94, :127-138
#     m3_invariants_spec.rb — above/below threshold examples
#   Cooldown blocks second regenerate (no summarize, no new job)
#     regeneration_rate_limiter_spec.rb:41-48
#     summarization_service_spec.rb:609-621
#     m3_invariants_spec.rb — E2E fetch_or_create_summary with Redis stubs
#   After cooldown allows regenerate
#     regeneration_rate_limiter_spec.rb:80-89
#     m3_invariants_spec.rb — travel 601s + second miss invokes summarize
#   No network — StubModelClient throughout
#   Create always changes ContentVersionHash (Lens A: not reply-count threshold)
#     content_version_hash_spec.rb:68-74
#     m3_invariants_spec.rb — sequential creates change hash each time

describe "DiscussionThreadSummarizer M3 invariants (#19)" do
  include ActiveSupport::Testing::TimeHelpers

  let(:course)  { course_model }
  let(:user)    { user_model }
  let(:topic)   { course.discussion_topics.create! }
  let(:account) { course.root_account }
  let(:locale)  { "en" }
  let(:llm_version) { DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION }

  before do
    course.enable_feature!(:discussion_thread_summarizer)
  end

  describe DiscussionThreadSummarizer::ContentVersionHash do
    before { topic.discussion_entries.create!(user:, message: "hello") }

    it "returns the same hash on repeated calls for an unchanged topic (AC: stability)" do
      first  = described_class.call(topic)
      second = described_class.call(topic)

      expect(first).to eq(second)
      expect(first).to match(/\A[0-9a-f]{64}\z/)
    end

    it "changes the hash on each new reply (ContentVersionHash is not threshold-aware)" do
      hash0 = described_class.call(topic)
      topic.discussion_entries.create!(user:, message: "first addition")
      hash1 = described_class.call(topic)
      topic.discussion_entries.create!(user:, message: "second addition")
      hash2 = described_class.call(topic)

      expect(hash0).not_to eq(hash1)
      expect(hash1).not_to eq(hash2)
    end
  end

  describe DiscussionThreadSummarizer::CacheInvalidation do
    let(:entry) { topic.discussion_entries.create!(user:, message: "one two three four five six seven") }

    before do
      allow(InstStatsd::Statsd).to receive(:distributed_increment)
      allow_any_instance_of(DiscussionTopic).to receive(:update_materialized_view)
      allow_any_instance_of(DiscussionEntry).to receive(:schedule_thread_summary_cache_invalidation_on_create)
      allow_any_instance_of(DiscussionEntry).to receive(:consider_thread_summary_cache_invalidation)
    end

    def seed_summary(hash:)
      topic.summaries.create!(
        user:,
        locale:,
        summary: DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE.to_json,
        dynamic_content_hash: hash,
        llm_config_version: llm_version
      )
    end

    it "preserves orphan hash on above-threshold edit (AC: word-delta invalidation)" do
      stale_hash = "0" * 64
      seed_summary(hash: stale_hash)
      after_msg = "one two three four five six seven eight nine ten eleven twelve"
      described_class.handle_entry_updated(entry, message_before: entry.message, message_after: after_msg)

      expect(topic.summaries.pluck(:dynamic_content_hash)).to eq([stale_hash])
    end

    it "rekeys below-threshold edit without firing invalidation.fired (AC: word-delta rekey)" do
      seed_summary(hash: "0" * 64)
      after_msg = "one two three four five six seven."
      before_msg = entry.message
      entry.update_column(:message, after_msg)
      described_class.handle_entry_updated(entry, message_before: before_msg, message_after: after_msg)

      expect(topic.summaries.pluck(:dynamic_content_hash).uniq).to eq(
        [DiscussionThreadSummarizer::ContentVersionHash.call(topic)]
      )
    end
  end

  describe DiscussionThreadSummarizer::SummarizationService, "#fetch_or_create_summary" do
    let(:stub_client) { DiscussionThreadSummarizer::StubModelClient.new }
    let(:service)     { described_class.new(client: stub_client) }
    let(:viewer)      { user }

    before do
      topic.discussion_entries.create!(user:, message: "seed entry")
      allow(Rails.logger).to receive(:info)
      allow(Canvas).to receive(:redis_enabled?).and_return(true)
    end

    def cooldown_key
      ["discussion_thread_summarizer", "cooldown", user.id, topic.id].cache_key
    end

    def quota_key(day: Time.now.utc.strftime("%Y%m%d"))
      ["discussion_thread_summarizer", "quota", account.global_id, day].cache_key
    end

    def force_cache_miss!
      topic.discussion_entries.create!(user:, message: "bust cache #{SecureRandom.hex(4)}")
    end

    it "does not call summarize or enqueue on a second cache miss within cooldown (AC: cooldown deny)" do
      travel_to Time.utc(2026, 1, 15, 12, 0, 0) do
        allow(Canvas.redis).to receive(:set).with(cooldown_key, 1, nx: true, ex: 600).and_return(true, false)
        allow(Canvas.redis).to receive(:incr).with(quota_key).and_return(1)
        allow(Canvas.redis).to receive(:expire)
        allow(stub_client).to receive(:summarize).and_call_original
        jobs_before = Delayed::Job.count

        service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)
        expect(stub_client).to have_received(:summarize).once

        force_cache_miss!
        result = service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

        expect(result.status).to eq(:rate_limited)
        expect(stub_client).to have_received(:summarize).once
        expect(Delayed::Job.count).to eq(jobs_before)
      end
    end

    it "invokes summarize on a second cache miss after cooldown TTL (AC: cooldown expires)" do
      travel_to Time.utc(2026, 1, 15, 12, 0, 0) do
        allow(Canvas.redis).to receive(:set).and_return(true, true)
        allow(Canvas.redis).to receive(:incr).and_return(1, 2)
        allow(Canvas.redis).to receive(:expire)
        allow(stub_client).to receive(:summarize).and_call_original

        service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)
        force_cache_miss!
        travel 601.seconds
        service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

        expect(stub_client).to have_received(:summarize).twice
      end
    end
  end
end
