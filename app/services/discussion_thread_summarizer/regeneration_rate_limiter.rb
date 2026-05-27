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
  # Redis-backed regeneration gate: per-user per-thread cooldown + per-account daily quota.
  class RegenerationRateLimiter
    COOLDOWN_SETTING_KEY = "discussion_thread_summarizer_user_thread_cooldown_seconds"
    DEFAULT_COOLDOWN_SECONDS = "600"
    QUOTA_SETTING_KEY = "discussion_thread_summarizer_account_daily_quota"
    DEFAULT_DAILY_QUOTA = "100"
    REDIS_REQUIRED_MESSAGE =
      "InstLLMHelper rate limiting requires Redis to be enabled for the Canvas instance. " \
      "You may remove the 'rate_limit' option from the LLMConfig to disable rate limiting."

    def self.check(account:, user:, discussion_topic:)
      course = discussion_topic.context
      return :allowed unless course.is_a?(Course) && course.feature_enabled?(:discussion_thread_summarizer)

      raise REDIS_REQUIRED_MESSAGE unless Canvas.redis_enabled?

      unless acquire_cooldown(user:, discussion_topic:)
        return :cooldown_denied
      end

      return :quota_denied unless acquire_quota(account:)

      :allowed
    end

    # READ-ONLY probe. Mirrors .check's cooldown-before-quota ordering using GET
    # on the cooldown key and quota counter. Does NOT mutate Redis — no SET, no
    # INCR, no DECR, no EXPIRE. Intended for render-time decisions where
    # consuming budget would be incorrect (the generation worker calls .check).
    def self.preview(account:, user:, discussion_topic:)
      course = discussion_topic.context
      return :allowed unless course.is_a?(Course) && course.feature_enabled?(:discussion_thread_summarizer)

      raise REDIS_REQUIRED_MESSAGE unless Canvas.redis_enabled?

      if Canvas.redis.get(cooldown_key(user, discussion_topic)).present?
        return :cooldown_denied
      end

      limit = Setting.get(QUOTA_SETTING_KEY, DEFAULT_DAILY_QUOTA).to_i
      return :quota_denied if Canvas.redis.get(quota_key(account)).to_i >= limit

      :allowed
    end

    def self.acquire_cooldown(user:, discussion_topic:)
      seconds = Setting.get(COOLDOWN_SETTING_KEY, DEFAULT_COOLDOWN_SECONDS).to_i
      Canvas.redis.set(cooldown_key(user, discussion_topic), 1, nx: true, ex: seconds)
    end
    private_class_method :acquire_cooldown

    def self.acquire_quota(account:)
      limit = Setting.get(QUOTA_SETTING_KEY, DEFAULT_DAILY_QUOTA).to_i
      key = quota_key(account)
      count = Canvas.redis.incr(key).to_i
      Canvas.redis.expire(key, 24.hours.to_i) if count == 1

      if count > limit
        Canvas.redis.decr(key)
        return false
      end

      true
    end
    private_class_method :acquire_quota

    def self.cooldown_key(user, discussion_topic)
      ["discussion_thread_summarizer", "cooldown", user.id, discussion_topic.id].cache_key
    end
    private_class_method :cooldown_key

    def self.quota_key(account)
      ["discussion_thread_summarizer", "quota", account.global_id, Time.now.utc.strftime("%Y%m%d")].cache_key
    end
    private_class_method :quota_key
  end
end
