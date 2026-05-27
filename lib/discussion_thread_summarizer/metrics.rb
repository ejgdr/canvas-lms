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
  # Thin metric helpers for the Discussion Thread Summarizer feature (NFR-4).
  # Each method wraps a single InstStatsd call with a fixed
  # discussion_thread_summarizer.* prefix and a consistent tag schema.
  # Callers are not wired yet; this module is scaffolded in M1 so that M2+
  # service code can require and call it without touching this file again.
  module Metrics
    PREFIX = "discussion_thread_summarizer"

    # Emitted each time a generation is attempted, regardless of outcome.
    def self.increment_generation_attempt(account:, scope_mode:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.generation.attempt",
        tags: { account_id: account.global_id, scope_mode: }
      )
    end

    # Records end-to-end generation latency in milliseconds.
    # outcome: one of "success", "error", "timeout", "schema_invalid"
    def self.record_generation_latency(duration_ms:, account:, outcome:)
      InstStatsd::Statsd.timing(
        "#{PREFIX}.generation.latency",
        duration_ms,
        tags: { account_id: account.global_id, outcome: }
      )
    end

    # Emitted on a cache hit (summary served from cache without model call).
    def self.increment_cache_hit(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.cache.hit",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted on a cache miss (no usable cached summary; generation queued).
    def self.increment_cache_miss(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.cache.miss",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when generation fails for any reason.
    # reason: one of "quota_exceeded", "throttled", "schema_invalid",
    #         "transport_error", "unknown"
    def self.increment_failure(reason:, account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.failure",
        tags: { account_id: account.global_id, reason: }
      )
    end

    # Emitted when a meaningful entry change orphans cached summaries (hash mismatch).
    # cause: one of "create", "edit", "delete"
    def self.increment_invalidation_fired(cause:, account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.invalidation.fired",
        tags: { account_id: account.global_id, cause: }
      )
    end

    # Emitted when a below-threshold message edit rekeys rows without invalidation.
    def self.increment_invalidation_skipped_below_threshold(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.invalidation.skipped_below_threshold",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when regeneration is allowed (cooldown and quota checks passed).
    def self.increment_rate_limit_allowed(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.rate_limit.allowed",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when per-user per-thread cooldown denies regeneration.
    def self.increment_rate_limit_cooldown_denied(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.rate_limit.cooldown_denied",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when per-account daily quota denies regeneration.
    def self.increment_rate_limit_quota_denied(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.rate_limit.quota_denied",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when render lookup serves a current (hash-matched) summary.
    def self.increment_render_current(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.render.current",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when render lookup serves a stale summary (hash orphan).
    def self.increment_render_stale(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.render.stale",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when render lookup finds no summary row for the locale.
    def self.increment_render_generating(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.render.generating",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when preview denies refresh and a stale row exists.
    def self.increment_render_rate_limited_stale(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.render.rate_limited_stale",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when preview denies refresh and no summary row exists.
    def self.increment_render_rate_limited_empty(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.render.rate_limited_empty",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when the feature flag is off at render lookup time.
    def self.increment_render_disabled(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.render.disabled",
        tags: { account_id: account.global_id }
      )
    end

    # Emitted when a user submits an inaccuracy report against a summary.
    # reason_category: one of "inaccurate", "missed_viewpoint",
    #                  "harmful_content", "other"
    # reporter_role:   "student", "teacher", "admin", or "observer"
    def self.increment_report_submission(account:, reason_category:, reporter_role:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.report.submission",
        tags: { account_id: account.global_id, reason_category:, reporter_role: }
      )
    end
  end
end
