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

module DiscussionThreadSummarizer
  # Redis-backed circuit breaker around the model-client call, keyed per account
  # (global_id). Mirrors RegenerationRateLimiter's Redis access pattern.
  #
  # States:
  #   closed    — normal operation; consecutive-failure counter < threshold.
  #   open      — threshold exceeded; open_key is SET with TTL = cooldown.
  #               All attempts short-circuit — no outbound call.
  #   half-open — open_key TTL has elapsed and it expired naturally; next
  #               attempt is a trial probe. On success → closed. On failure
  #               → re-open with a fresh cooldown.
  #
  # .state(account:) → :open | :closed
  # .record_success  — resets counter, closes circuit (emits circuit_closed if
  #                    was open).
  # .record_failure  — increments counter; opens circuit when threshold reached.
  class CircuitBreaker
    FAILURE_THRESHOLD_SETTING_KEY = "discussion_thread_summarizer_circuit_failure_threshold"
    DEFAULT_FAILURE_THRESHOLD     = "5"
    COOLDOWN_SETTING_KEY          = "discussion_thread_summarizer_circuit_cooldown_seconds"
    DEFAULT_COOLDOWN_SECONDS      = "30"

    def self.state(account:)
      raise DiscussionThreadSummarizer::RegenerationRateLimiter::REDIS_REQUIRED_MESSAGE \
        unless Canvas.redis_enabled?

      Canvas.redis.get(open_key(account)).present? ? :open : :closed
    end

    def self.record_failure(account:, scope_mode:)
      raise DiscussionThreadSummarizer::RegenerationRateLimiter::REDIS_REQUIRED_MESSAGE \
        unless Canvas.redis_enabled?

      threshold = Setting.get(FAILURE_THRESHOLD_SETTING_KEY, DEFAULT_FAILURE_THRESHOLD).to_i
      count     = Canvas.redis.incr(failure_key(account)).to_i
      Canvas.redis.expire(failure_key(account), 7.days.to_i) if count == 1

      open!(account:, scope_mode:) if count >= threshold
    end

    def self.record_success(account:, scope_mode:)
      raise DiscussionThreadSummarizer::RegenerationRateLimiter::REDIS_REQUIRED_MESSAGE \
        unless Canvas.redis_enabled?

      was_open = Canvas.redis.del(open_key(account)).to_i > 0
      Canvas.redis.del(failure_key(account))

      DiscussionThreadSummarizer::Metrics.increment_circuit_closed(account:, scope_mode:) if was_open
    end

    def self.reset!(account:)
      Canvas.redis.del(open_key(account), failure_key(account))
    end

    def self.open!(account:, scope_mode:)
      Canvas.redis.set(open_key(account), 1, ex: cooldown_seconds)
      DiscussionThreadSummarizer::Metrics.increment_circuit_open(account:, scope_mode:)
    end
    private_class_method :open!

    def self.failure_key(account)
      ["discussion_thread_summarizer", "circuit", "failures", account.global_id].cache_key
    end
    private_class_method :failure_key

    def self.open_key(account)
      ["discussion_thread_summarizer", "circuit", "open", account.global_id].cache_key
    end
    private_class_method :open_key

    def self.cooldown_seconds
      Setting.get(COOLDOWN_SETTING_KEY, DEFAULT_COOLDOWN_SECONDS).to_i
    end
    private_class_method :cooldown_seconds
  end
end
