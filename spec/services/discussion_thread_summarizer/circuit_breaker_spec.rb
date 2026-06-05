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

describe DiscussionThreadSummarizer::CircuitBreaker do
  let(:account)    { instance_double("Account", global_id: 10_000_000_000_001) }
  let(:scope_mode) { "default" }
  let(:fake_redis) { double("redis") }

  before do
    allow(Canvas).to receive(:redis_enabled?).and_return(true)
    allow(Canvas).to receive(:redis).and_return(fake_redis)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_open)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_circuit_closed)
  end

  # ── .state ─────────────────────────────────────────────────────────────────

  describe ".state" do
    it "returns :closed when the open key is absent" do
      allow(fake_redis).to receive(:get).and_return(nil)  # open_key absent
      expect(described_class.state(account:)).to eq(:closed)
    end

    it "returns :open when within the cooldown window (open_key + cooldown_key present)" do
      # Both get calls return a value: open_key present, cooldown_key present.
      allow(fake_redis).to receive(:get).and_return("1")
      expect(described_class.state(account:)).to eq(:open)
    end

    context "half-open: cooldown elapsed (cooldown_key absent), open_key still present" do
      before do
        # open_key present, cooldown_key absent → half-open window.
        allow(fake_redis).to receive(:get).and_return("1", nil)
      end

      it "returns :closed (probe granted) when probe_key can be acquired" do
        allow(fake_redis).to receive(:set).with(anything, 1, nx: true, ex: anything).and_return(true)
        expect(described_class.state(account:)).to eq(:closed)
      end

      it "returns :open (probe in flight) when probe_key is already held" do
        allow(fake_redis).to receive(:set).with(anything, 1, nx: true, ex: anything).and_return(false)
        expect(described_class.state(account:)).to eq(:open)
      end

      it "admits exactly one probe per cooldown window" do
        # First caller acquires probe; second is blocked.
        allow(fake_redis).to receive(:set)
          .with(anything, 1, nx: true, ex: anything)
          .and_return(true, false)

        # Simulate two concurrent .state calls (same redis state each time).
        allow(fake_redis).to receive(:get).and_return("1", nil, "1", nil)

        expect(described_class.state(account:)).to eq(:closed)  # probe granted
        expect(described_class.state(account:)).to eq(:open)    # probe in flight
      end
    end
  end

  # ── .record_failure ─────────────────────────────────────────────────────────

  describe ".record_failure" do
    before do
      allow(fake_redis).to receive(:incr).and_return(1)
      allow(fake_redis).to receive(:expire)
      allow(fake_redis).to receive(:set)
      allow(fake_redis).to receive(:del)
    end

    it "increments the failure counter" do
      described_class.record_failure(account:, scope_mode:)
      expect(fake_redis).to have_received(:incr)
    end

    it "sets a 7-day expiry on first failure" do
      described_class.record_failure(account:, scope_mode:)
      expect(fake_redis).to have_received(:expire).with(anything, 7.days.to_i)
    end

    it "does not open the circuit below the threshold" do
      threshold = Setting.get(
        described_class::FAILURE_THRESHOLD_SETTING_KEY,
        described_class::DEFAULT_FAILURE_THRESHOLD
      ).to_i
      allow(fake_redis).to receive(:incr).and_return(threshold - 1)
      described_class.record_failure(account:, scope_mode:)
      expect(DiscussionThreadSummarizer::Metrics).not_to have_received(:increment_circuit_open)
    end

    it "opens the circuit and emits metric when threshold is reached" do
      threshold = Setting.get(
        described_class::FAILURE_THRESHOLD_SETTING_KEY,
        described_class::DEFAULT_FAILURE_THRESHOLD
      ).to_i
      allow(fake_redis).to receive(:incr).and_return(threshold)
      described_class.record_failure(account:, scope_mode:)
      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_open).with(
        account:,
        scope_mode:
      )
    end
  end

  # ── .record_success ─────────────────────────────────────────────────────────

  describe ".record_success" do
    it "deletes all circuit state keys" do
      allow(fake_redis).to receive(:del).and_return(0)
      described_class.record_success(account:, scope_mode:)
      expect(fake_redis).to have_received(:del).at_least(:twice)
    end

    it "emits circuit_closed when the circuit was open" do
      # First del (open_key alone) returns 1; second del (cooldown+probe+failure) returns 0.
      allow(fake_redis).to receive(:del).and_return(1, 0)
      described_class.record_success(account:, scope_mode:)
      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_circuit_closed).with(
        account:,
        scope_mode:
      )
    end

    it "does not emit circuit_closed when the circuit was already closed" do
      allow(fake_redis).to receive(:del).and_return(0)
      described_class.record_success(account:, scope_mode:)
      expect(DiscussionThreadSummarizer::Metrics).not_to have_received(:increment_circuit_closed)
    end
  end
end
