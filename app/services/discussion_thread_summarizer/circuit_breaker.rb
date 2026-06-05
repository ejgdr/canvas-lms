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
  # State machine (three Redis keys per account):
  #
  #   open_key     — present while circuit is open (no TTL; deleted on close).
  #   cooldown_key — present during the cooldown window after opening (TTL =
  #                  cooldown_seconds). When it expires, the circuit is half-open.
  #   probe_key    — acquired (nx: true) by exactly one caller in the half-open
  #                  window; prevents concurrent probes from flooding the service.
  #
  # States:
  #   closed    — open_key absent.  All calls allowed.
  #   open      — open_key present AND cooldown_key present.  All calls blocked.
  #   half-open — open_key present, cooldown_key absent (expired).  Exactly ONE
  #               caller acquires probe_key (nx) and is let through as a trial.
  #               All other concurrent callers see :open until the trial resolves.
  #               Success → closed (record_success).
  #               Failure → re-open with a fresh cooldown (record_failure → open!).
  #
  # .state(account:)             → :open | :closed
  # .record_success(account:, …) — resets counter, closes circuit, emits metric.
  # .record_failure(account:, …) — increments counter; opens when threshold hit.
  class CircuitBreaker
    FAILURE_THRESHOLD_SETTING_KEY = "discussion_thread_summarizer_circuit_failure_threshold"
    DEFAULT_FAILURE_THRESHOLD     = "5"
    COOLDOWN_SETTING_KEY          = "discussion_thread_summarizer_circuit_cooldown_seconds"
    DEFAULT_COOLDOWN_SECONDS      = "30"

    def self.state(account:)
      raise DiscussionThreadSummarizer::RegenerationRateLimiter::REDIS_REQUIRED_MESSAGE \
        unless Canvas.redis_enabled?

      return :closed unless Canvas.redis.get(open_key(account)).present?

      # Circuit is open. Still within the cooldown window?
      return :open if Canvas.redis.get(cooldown_key(account)).present?

      # Cooldown elapsed — half-open. Grant exactly one probe per window.
      Canvas.redis.set(probe_key(account), 1, nx: true, ex: cooldown_seconds) ? :closed : :open
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
      Canvas.redis.del(cooldown_key(account), probe_key(account), failure_key(account))

      DiscussionThreadSummarizer::Metrics.increment_circuit_closed(account:, scope_mode:) if was_open
    end

    def self.reset!(account:)
      Canvas.redis.del(open_key(account), cooldown_key(account), probe_key(account), failure_key(account))
    end

    def self.open!(account:, scope_mode:)
      cx = cooldown_seconds
      Canvas.redis.set(open_key(account), 1)              # no TTL — survives until record_success
      Canvas.redis.set(cooldown_key(account), 1, ex: cx)  # expires to signal half-open window
      Canvas.redis.del(probe_key(account))                 # clear stale probe from prior cycle
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

    def self.cooldown_key(account)
      ["discussion_thread_summarizer", "circuit", "cooldown", account.global_id].cache_key
    end
    private_class_method :cooldown_key

    def self.probe_key(account)
      ["discussion_thread_summarizer", "circuit", "probe", account.global_id].cache_key
    end
    private_class_method :probe_key

    def self.cooldown_seconds
      Setting.get(COOLDOWN_SETTING_KEY, DEFAULT_COOLDOWN_SECONDS).to_i
    end
    private_class_method :cooldown_seconds
  end
end
