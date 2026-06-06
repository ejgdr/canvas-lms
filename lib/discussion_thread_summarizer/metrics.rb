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

    # Emitted each time a generation is attempted (cache miss + rate limit pass).
    def self.increment_generation_attempt(account:, scope_mode:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.generation_attempt",
        tags: { account_id: account.global_id, scope_mode: }
      )
    end

    # Records model-generation latency in milliseconds for completed jobs only.
    # Tagged for p50/p95/p99 rollups — no PII.
    def self.record_generation_latency_ms(duration_ms:, account:, scope_mode:)
      InstStatsd::Statsd.timing(
        "#{PREFIX}.generation_latency_ms",
        duration_ms,
        tags: { account_id: account.global_id, scope_mode: }
      )
    end

    # Emitted when a generation attempt fails before completing successfully.
    def self.increment_generation_error(account:, scope_mode:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.generation_error",
        tags: { account_id: account.global_id, scope_mode: }
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

    # Part of the cache.* family (NFR-4: cache effectiveness telemetry). Parallel to
    # render.stale and render.rate_limited_stale, which serve render-state dashboards.
    # Both render states fire cache.stale because both serve orphan-hash content from
    # the cache without regeneration. Dual-emit is intentional — see Cycle 20 evidence.
    def self.increment_cache_stale(account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.cache.stale",
        tags: { account_id: account.global_id }
      )
    end

    # Part of the cache.* family (NFR-4). Parallel to invalidation.fired (Cycle 17),
    # which serves write-side event dashboards. Same callsites; trigger tag uses
    # reply_* values per #20 AC (reply_create / reply_edit / reply_delete), while
    # invalidation.fired uses cause: create/edit/delete. Dual-emit is intentional.
    def self.increment_cache_invalidated(trigger:, account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.cache.invalidated",
        tags: { account_id: account.global_id, trigger: }
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

    # Emitted on each successful DiscussionTopicSummaryReport creation (#41/#45).
    # reason:        one of "inaccurate", "missed_viewpoint", "harmful_content", "other"
    # reporter_role: "student", "teacher", or "admin" — no user_id or report text in tags.
    # account_id:    global_id for per-account aggregation (consistent with other metrics).
    def self.increment_report_submitted(reason:, reporter_role:, account:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.report_submitted",
        tags: { reason:, reporter_role:, account_id: account.global_id }
      )
    end

    # Emitted when the circuit breaker transitions to the open state (M8 #48).
    # Frozen name — Cycle 37 #50 dashboard depends on it.
    def self.increment_circuit_open(account:, scope_mode:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.circuit_open",
        tags: { account_id: account.global_id, scope_mode: }
      )
    end

    # Emitted when the circuit breaker transitions from open → closed (M8 #48).
    # Frozen name — Cycle 37 #50 dashboard depends on it.
    def self.increment_circuit_closed(account:, scope_mode:)
      InstStatsd::Statsd.distributed_increment(
        "#{PREFIX}.circuit_closed",
        tags: { account_id: account.global_id, scope_mode: }
      )
    end
  end
end
