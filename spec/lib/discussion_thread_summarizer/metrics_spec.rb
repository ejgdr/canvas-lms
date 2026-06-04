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

describe DiscussionThreadSummarizer::Metrics do
  let(:account) { instance_double("Account", global_id: 10_000_000_000_001) }

  before do
    allow(InstStatsd::Statsd).to receive(:distributed_increment).and_return(nil)
    allow(InstStatsd::Statsd).to receive(:timing).and_return(nil)
  end

  describe ".increment_generation_attempt" do
    # Dashboard panel contract (#40): daily generation_attempt counts per account,
    # filterable by scope_mode tag. Only two values are valid: "default" and "limited".
    it "emits with scope_mode: default for standard mode" do
      described_class.increment_generation_attempt(account:, scope_mode: "default")
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.generation_attempt",
        tags: { account_id: 10_000_000_000_001, scope_mode: "default" }
      )
    end

    it "emits with scope_mode: limited for scope-limited mode" do
      described_class.increment_generation_attempt(account:, scope_mode: "limited")
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.generation_attempt",
        tags: { account_id: 10_000_000_000_001, scope_mode: "limited" }
      )
    end
  end

  describe ".record_generation_latency_ms" do
    it "emits discussion_thread_summarizer.generation_latency_ms with duration, account_id, and scope_mode tags" do
      described_class.record_generation_latency_ms(duration_ms: 342, account:, scope_mode: "limited")
      expect(InstStatsd::Statsd).to have_received(:timing).with(
        "discussion_thread_summarizer.generation_latency_ms",
        342,
        tags: { account_id: 10_000_000_000_001, scope_mode: "limited" }
      )
    end
  end

  describe ".increment_generation_error" do
    it "emits discussion_thread_summarizer.generation_error with account_id and scope_mode tags" do
      described_class.increment_generation_error(account:, scope_mode: "default")
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.generation_error",
        tags: { account_id: 10_000_000_000_001, scope_mode: "default" }
      )
    end
  end

  describe ".increment_cache_hit" do
    it "emits discussion_thread_summarizer.cache.hit with account_id tag" do
      described_class.increment_cache_hit(account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.cache.hit",
        tags: { account_id: 10_000_000_000_001 }
      )
    end
  end

  describe ".increment_cache_miss" do
    it "emits discussion_thread_summarizer.cache.miss with account_id tag" do
      described_class.increment_cache_miss(account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.cache.miss",
        tags: { account_id: 10_000_000_000_001 }
      )
    end
  end

  describe ".increment_cache_stale" do
    it "emits discussion_thread_summarizer.cache.stale with account_id tag" do
      described_class.increment_cache_stale(account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.cache.stale",
        tags: { account_id: 10_000_000_000_001 }
      )
    end
  end

  describe ".increment_cache_invalidated" do
    it "emits discussion_thread_summarizer.cache.invalidated with account_id and trigger tags" do
      described_class.increment_cache_invalidated(trigger: "reply_edit", account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.cache.invalidated",
        tags: { account_id: 10_000_000_000_001, trigger: "reply_edit" }
      )
    end
  end

  describe ".increment_failure" do
    it "emits discussion_thread_summarizer.failure with account_id and reason tags" do
      described_class.increment_failure(reason: "timeout", account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.failure",
        tags: { account_id: 10_000_000_000_001, reason: "timeout" }
      )
    end
  end

  describe ".increment_invalidation_fired" do
    it "emits discussion_thread_summarizer.invalidation.fired with account_id and cause tags" do
      described_class.increment_invalidation_fired(cause: "edit", account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.invalidation.fired",
        tags: { account_id: 10_000_000_000_001, cause: "edit" }
      )
    end
  end

  describe ".increment_invalidation_skipped_below_threshold" do
    it "emits discussion_thread_summarizer.invalidation.skipped_below_threshold with account_id tag" do
      described_class.increment_invalidation_skipped_below_threshold(account:)
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.invalidation.skipped_below_threshold",
        tags: { account_id: 10_000_000_000_001 }
      )
    end
  end

  describe ".increment_report_submission" do
    it "emits discussion_thread_summarizer.report.submission with account_id, reason_category, and reporter_role tags" do
      described_class.increment_report_submission(
        account:,
        reason_category: "missed_viewpoint",
        reporter_role: "student"
      )
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
        "discussion_thread_summarizer.report.submission",
        tags: { account_id: 10_000_000_000_001, reason_category: "missed_viewpoint", reporter_role: "student" }
      )
    end
  end
end
