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

describe DiscussionThreadSummarizer::RegenerationRateLimiter do
  include ActiveSupport::Testing::TimeHelpers

  let(:course)  { course_model }
  let(:user)    { user_model }
  let(:topic)   { course.discussion_topics.create! }
  let(:account) { course.root_account }

  before do
    allow(Canvas).to receive(:redis_enabled?).and_return(true)
    course.enable_feature!(:discussion_thread_summarizer)
  end

  def cooldown_key(for_user: user, for_topic: topic)
    ["discussion_thread_summarizer", "cooldown", for_user.id, for_topic.id].cache_key
  end

  def quota_key(for_account: account, day: Time.now.utc.strftime("%Y%m%d"))
    ["discussion_thread_summarizer", "quota", for_account.global_id, day].cache_key
  end

  it "denies the second miss for the same user and thread within cooldown" do
    allow(Canvas.redis).to receive(:set).with(cooldown_key, 1, nx: true, ex: 600).and_return(true, false)
    allow(Canvas.redis).to receive(:incr).and_return(1)
    allow(Canvas.redis).to receive(:expire)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:cooldown_denied)
  end

  it "allows two threads for the same user when cooldown keys differ" do
    topic_b = course.discussion_topics.create!
    allow(Canvas.redis).to receive(:set).with(cooldown_key, 1, nx: true, ex: 600).and_return(true)
    allow(Canvas.redis).to receive(:set).with(cooldown_key(for_topic: topic_b), 1, nx: true, ex: 600).and_return(true)
    allow(Canvas.redis).to receive(:incr).and_return(1, 2)
    allow(Canvas.redis).to receive(:expire)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
    expect(described_class.check(account:, user:, discussion_topic: topic_b)).to eq(:allowed)
  end

  it "allows two users on the same thread when cooldown keys differ" do
    user_b = user_model
    allow(Canvas.redis).to receive(:set).with(cooldown_key, 1, nx: true, ex: 600).and_return(true)
    allow(Canvas.redis).to receive(:set).with(cooldown_key(for_user: user_b), 1, nx: true, ex: 600).and_return(true)
    allow(Canvas.redis).to receive(:incr).and_return(1, 2)
    allow(Canvas.redis).to receive(:expire)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
    expect(described_class.check(account:, user: user_b, discussion_topic: topic)).to eq(:allowed)
  end

  it "denies when daily quota is exceeded and rolls back the increment" do
    allow(Canvas.redis).to receive(:set).and_return(true)
    allow(Canvas.redis).to receive(:incr).with(quota_key).and_return(101)
    expect(Canvas.redis).to receive(:decr).with(quota_key)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:quota_denied)
  end

  it "allows regeneration after cooldown TTL elapses" do
    travel_to Time.utc(2026, 1, 15, 12, 0, 0) do
      allow(Canvas.redis).to receive(:set).and_return(true, true)
      allow(Canvas.redis).to receive(:incr).and_return(1, 2)
      allow(Canvas.redis).to receive(:expire)

      expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
      travel 601.seconds
      expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
    end
  end

  it "resets daily quota at the UTC day boundary" do
    travel_to Time.utc(2026, 1, 15, 23, 30, 0) do
      key_day_one = quota_key(day: "20260115")
      allow(Canvas.redis).to receive(:set).and_return(true)
      allow(Canvas.redis).to receive(:incr).with(key_day_one).and_return(100)
      allow(Canvas.redis).to receive(:expire)

      expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
    end

    travel_to Time.utc(2026, 1, 16, 0, 0, 1) do
      key_day_two = quota_key(day: "20260116")
      allow(Canvas.redis).to receive(:set).and_return(true)
      allow(Canvas.redis).to receive(:incr).with(key_day_two).and_return(1)
      allow(Canvas.redis).to receive(:expire)

      expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
    end
  end

  it "does not touch Redis during CacheInvalidation rekey" do
    allow_any_instance_of(DiscussionTopic).to receive(:update_materialized_view)
    allow_any_instance_of(DiscussionEntry).to receive(:schedule_thread_summary_cache_invalidation_on_create)
    allow_any_instance_of(DiscussionEntry).to receive(:consider_thread_summary_cache_invalidation)
    entry = topic.discussion_entries.create!(user:, message: "one two three four five six seven")
    seed_hash = "0" * 64
    topic.summaries.create!(
      user:,
      locale: "en",
      summary: DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE.to_json,
      dynamic_content_hash: seed_hash,
      llm_config_version: DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION
    )
    allow(Canvas.redis).to receive(:set)
    allow(Canvas.redis).to receive(:incr)

    DiscussionThreadSummarizer::CacheInvalidation.handle_entry_updated(
      entry,
      message_before: entry.message,
      message_after: "one two three four five six seven."
    )

    expect(Canvas.redis).not_to have_received(:set)
    expect(Canvas.redis).not_to have_received(:incr)
  end

  it "returns :allowed without Redis when the feature flag is off" do
    course.disable_feature!(:discussion_thread_summarizer)
    expect(Canvas.redis).not_to receive(:set)
    expect(Canvas.redis).not_to receive(:incr)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
  end

  # SET NX is atomic at Redis; concurrent allow-check race is not testable at the Ruby layer.
  it "skips concurrent race coverage (SET NX is atomic at Redis)" do
    skip "SET NX is atomic at Redis; concurrent allow-check race is not testable at the Ruby layer"
  end

  it "checks cooldown before quota and does not INCR when cooldown denies" do
    allow(Canvas.redis).to receive(:set).and_return(false)
    expect(Canvas.redis).not_to receive(:incr)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:cooldown_denied)
  end

  it "restores quota counter after deny so a subsequent check at the limit can allow" do
    allow(Canvas.redis).to receive(:set).and_return(true)
    allow(Canvas.redis).to receive(:incr).with(quota_key).and_return(101, 100)
    expect(Canvas.redis).to receive(:decr).with(quota_key).once
    allow(Canvas.redis).to receive(:expire)

    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:quota_denied)
    expect(described_class.check(account:, user:, discussion_topic: topic)).to eq(:allowed)
  end

  it "raises when Redis is disabled (fail-closed, matches InstLLMHelper)" do
    allow(Canvas).to receive(:redis_enabled?).and_return(false)
    expect do
      described_class.check(account:, user:, discussion_topic: topic)
    end.to raise_error(
      "InstLLMHelper rate limiting requires Redis to be enabled for the Canvas instance. " \
      "You may remove the 'rate_limit' option from the LLMConfig to disable rate limiting."
    )
  end
end
