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

describe DiscussionThreadSummarizer::CacheInvalidation do
  let(:course)  { course_model }
  let(:user)    { user_model }
  let(:topic)   { course.discussion_topics.create! }
  let(:account) { course.root_account }
  let(:entry)   { topic.discussion_entries.create!(user:, message: "one two three four five six seven") }
  let(:llm_version) { DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION }

  before do
    course.enable_feature!(:discussion_thread_summarizer)
    allow(InstStatsd::Statsd).to receive(:distributed_increment)
    allow_any_instance_of(DiscussionTopic).to receive(:update_materialized_view)
    allow_any_instance_of(DiscussionEntry).to receive(:schedule_thread_summary_cache_invalidation_on_create)
    allow_any_instance_of(DiscussionEntry).to receive(:consider_thread_summary_cache_invalidation)
  end

  def seed_summary(locale: "en", hash:)
    topic.summaries.create!(
      user:,
      locale:,
      summary: DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE.to_json,
      dynamic_content_hash: hash,
      llm_config_version: llm_version
    )
  end

  def fired_metric(cause:)
    [
      "discussion_thread_summarizer.invalidation.fired",
      { tags: { account_id: account.global_id, cause: } }
    ]
  end

  def skipped_metric
    [
      "discussion_thread_summarizer.invalidation.skipped_below_threshold",
      { tags: { account_id: account.global_id } }
    ]
  end

  it "fires invalidation.fired cause create on handle_entry_created" do
    described_class.handle_entry_created(entry)
    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(*fired_metric(cause: "create"))
    expect(InstStatsd::Statsd).not_to have_received(:distributed_increment).with(*skipped_metric)
  end

  it "fires invalidation.fired cause edit and preserves stale hash on above-threshold edit" do
    stale_hash = "0" * 64
    seed_summary(hash: stale_hash)
    after_msg = "one two three four five six seven eight nine ten eleven twelve"
    described_class.handle_entry_updated(entry, message_before: entry.message, message_after: after_msg)
    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(*fired_metric(cause: "edit")).once
    expect(topic.summaries.pluck(:dynamic_content_hash)).to eq([stale_hash])
  end

  it "skips invalidation and rekeys rows on below-threshold edit" do
    seed_summary(hash: "0" * 64)
    after_msg = "one two three four five six seven."
    before_msg = entry.message
    entry.update_column(:message, after_msg)
    described_class.handle_entry_updated(entry, message_before: before_msg, message_after: after_msg)
    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(*skipped_metric).once
    expect(InstStatsd::Statsd).not_to have_received(:distributed_increment).with(*fired_metric(cause: "edit"))
    expect(topic.summaries.pluck(:dynamic_content_hash).uniq).to eq(
      [DiscussionThreadSummarizer::ContentVersionHash.call(topic)]
    )
  end

  it "fires invalidation.fired cause delete on handle_entry_deleted" do
    described_class.handle_entry_deleted(entry)
    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(*fired_metric(cause: "delete"))
  end

  it "does not route editor_id-only saves through invalidation handlers" do
    entry
    allow(entry).to receive(:consider_thread_summary_cache_invalidation).and_call_original
    expect(described_class).not_to receive(:handle_entry_updated)
    expect(described_class).not_to receive(:handle_entry_deleted)
    entry.update!(editor_id: user.id)
    entry.consider_thread_summary_cache_invalidation
  end

  it "emits no metrics and does not rekey when the feature flag is off" do
    seed_summary(hash: "0" * 64)
    allow_any_instance_of(described_class).to receive(:enabled?).and_return(false)
    allow(InstStatsd::Statsd).to receive(:distributed_increment)
    described_class.handle_entry_updated(
      entry,
      message_before: entry.message,
      message_after: "one two three four five six seven."
    )
    expect(InstStatsd::Statsd).not_to have_received(:distributed_increment).with(
      a_string_starting_with("discussion_thread_summarizer.invalidation"),
      anything
    )
    expect(topic.summaries.pluck(:dynamic_content_hash)).to eq(["0" * 64])
  end

  it "still returns cache :hit after below-threshold rekey" do
    seed_summary(hash: DiscussionThreadSummarizer::ContentVersionHash.call(topic))
    stub_client = DiscussionThreadSummarizer::StubModelClient.new
    service = DiscussionThreadSummarizer::SummarizationService.new(client: stub_client)
    allow(stub_client).to receive(:summarize).and_call_original
    after_msg = "one two three four five six seven."
    before_msg = entry.message
    entry.update_column(:message, after_msg)
    described_class.handle_entry_updated(entry, message_before: before_msg, message_after: after_msg)
    result = service.fetch_or_create_summary(discussion_topic: topic, viewer: user, locale: "en")
    expect(result.status).to eq(:hit)
    expect(stub_client).not_to have_received(:summarize)
  end

  it "uses soft-delete on normal destroy (user delete path)" do
    entry.destroy
    expect(entry.reload.workflow_state).to eq("deleted")
  end

  it "does not call the model client or enqueue jobs on below-threshold rekey" do
    seed_summary(hash: "0" * 64)
    stub_client = DiscussionThreadSummarizer::StubModelClient.new
    allow(stub_client).to receive(:summarize).and_call_original
    service = DiscussionThreadSummarizer::SummarizationService.new(client: stub_client)
    after_msg = "one two three four five six seven."
    before_msg = entry.message
    entry.update_column(:message, after_msg)
    jobs_before = Delayed::Job.count
    described_class.handle_entry_updated(entry, message_before: before_msg, message_after: after_msg)
    service.fetch_or_create_summary(discussion_topic: topic, viewer: user, locale: "en")
    expect(Delayed::Job.count).to eq(jobs_before)
    expect(stub_client).not_to have_received(:summarize)
  end

  it "rekeys all locale rows to the same post-edit hash in one operation" do
    old_hash = "1" * 64
    %w[en es fr].each { |locale| seed_summary(locale:, hash: old_hash) }
    after_msg = "one two three four five six seven."
    before_msg = entry.message
    entry.update_column(:message, after_msg)
    described_class.handle_entry_updated(entry, message_before: before_msg, message_after: after_msg)
    new_hash = DiscussionThreadSummarizer::ContentVersionHash.call(topic)
    expect(topic.summaries.pluck(:dynamic_content_hash).uniq).to eq([new_hash])
  end
end
