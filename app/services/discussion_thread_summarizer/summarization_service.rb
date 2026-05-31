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
  # Orchestrates the per-thread summary pipeline:
  #   gather → pseudonymize → client.summarize → validate → return result
  #
  # This is the only code path that calls the model client. Controllers, jobs,
  # and cache layers all go through here, never through the client directly.
  class SummarizationService
    LLM_CONFIG_VERSION = "thread-summarizer-v1"

    CacheResult = Struct.new(:status, :record, :result, keyword_init: true)

    RenderState = %i[
      current
      stale
      generating
      rate_limited_stale
      rate_limited_empty
      disabled
    ].freeze

    RenderResult = Struct.new(:status, :record, :result, :enqueued, keyword_init: true)

    # Enqueues a background summary attempt via Delayed Job.
    # Mirrors the insight_generation pattern in DiscussionTopicsApiController.
    # Singleton + n_strand ensure at most one job per topic runs at a time.
    def self.enqueue_for(discussion_topic:, viewer:)
      new.delay(
        priority: Delayed::HIGH_PRIORITY,
        singleton: "discussion_thread_summarizer:generation_for_topic:#{discussion_topic.id}",
        n_strand: ["discussion_thread_summarizer:generation:#{Shard.current.database_server.region}", 1]
      ).fetch_or_create_summary(discussion_topic:, viewer:)
    end

    def initialize(client: StubModelClient.new)
      @client = client
    end

    # Cache-aware entrypoint: O(1) lookup by content hash + config version + locale.
    # On hit, returns stored summary without calling the model client.
    def fetch_or_create_summary(discussion_topic:, viewer:, locale: I18n.locale.to_s)
      course = discussion_topic.context
      unless course.is_a?(Course) && course.feature_enabled?(:discussion_thread_summarizer)
        # Defense-in-depth flag gate mirroring #lookup_for_render guard. Production
        # callers (job, controller) already gate the flag before reaching here; this
        # guard prevents accidental invocation from misconfigured contexts. See #20 DoD.
        # Returns :rate_limited without invoking the limiter or model — not a real deny,
        # but the closest frozen CacheResult.status that blocks regeneration (no :disabled
        # in the pipeline enum). Documented in Cycle 20 evidence.
        return CacheResult.new(status: :rate_limited, record: nil, result: nil)
      end

      account      = discussion_topic.context.root_account
      content_hash = ContentVersionHash.call(discussion_topic)
      cached       = find_cached_summary(discussion_topic, content_hash, locale)

      if cached
        DiscussionThreadSummarizer::Metrics.increment_cache_hit(account:)
        return CacheResult.new(
          status: :hit,
          record: cached,
          result: parse_summary_record(cached)
        )
      end

      DiscussionThreadSummarizer::Metrics.increment_cache_miss(account:)

      # NOTE: The rekey path in DiscussionThreadSummarizer::CacheInvalidation does NOT
      # pass through this gate — rekey is a metadata-only UPDATE that never invokes the
      # model, so it must not consume cooldown or daily-quota budget. The limiter is
      # only consulted on the cache-miss path of #fetch_or_create_summary, immediately
      # before #summarize. Cache hits also bypass the limiter (no model call).
      #
      # Redis-down posture: fail-closed — matches InstLLMHelper behavior verified at
      # app/helpers/inst_llm_helper.rb:41 during Cycle 18 (raises when Redis disabled).
      case RegenerationRateLimiter.check(account:, user: viewer, discussion_topic:)
      when :cooldown_denied
        DiscussionThreadSummarizer::Metrics.increment_rate_limit_cooldown_denied(account:)
        return CacheResult.new(status: :rate_limited, record: nil, result: nil)
      when :quota_denied
        DiscussionThreadSummarizer::Metrics.increment_rate_limit_quota_denied(account:)
        return CacheResult.new(status: :rate_limited, record: nil, result: nil)
      end

      DiscussionThreadSummarizer::Metrics.increment_rate_limit_allowed(account:)
      scope_mode = scope_mode_for(discussion_topic)
      DiscussionThreadSummarizer::Metrics.increment_generation_attempt(account:, scope_mode:)
      result = summarize(discussion_topic:, viewer:)
      record = persist_summary_record(
        discussion_topic:,
        viewer:,
        locale:,
        content_hash:,
        result:
      )
      CacheResult.new(status: :miss, record: record, result: result)
    end

    # Render-time lookup: read-only with respect to the model and rate-limit budget.
    def lookup_for_render(discussion_topic:, viewer:, locale: I18n.locale.to_s)
      course = discussion_topic.context
      unless course.is_a?(Course) && course.feature_enabled?(:discussion_thread_summarizer)
        if course.is_a?(Course)
          DiscussionThreadSummarizer::Metrics.increment_render_disabled(account: course.root_account)
        end
        return RenderResult.new(status: :disabled, record: nil, result: nil, enqueued: false)
      end

      account = discussion_topic.context.root_account
      record      = find_latest_summary_row(discussion_topic, locale)
      current_hash = ContentVersionHash.call(discussion_topic)

      # NOTE: This is the render-time lookup. Distinct from #fetch_or_create_summary
      # (cache miss path that actually invokes the model). Read-only with respect to
      # the model and rate-limit budget — uses RegenerationRateLimiter.preview, never
      # .check. Enqueue happens here when state is :stale or :generating AND preview
      # allows. The job's miss path will consult .check authoritatively; race between
      # preview-allow and job-deny is acceptable (one-cycle delay).
      #
      # Hash race: ContentVersionHash.call(topic) is computed after the row fetch.
      # Concurrent entry edits can make :current appear :stale (or vice versa) for
      # one request. Self-corrects on next render. Matches the legacy summary
      # `obsolete` flag race semantics (discussion_topics_api_controller.rb:135).
      #
      # Singleton: enqueue_for keys only discussion_topic.id (not locale). Multiple
      # locales requesting refresh for the same topic share one Delayed::Job; the job
      # runs fetch_or_create_summary with the viewer/locale from whichever enqueue won.

      if record.nil?
        build_generating_or_rate_limited_empty(discussion_topic:, viewer:, locale:, account:)
      elsif record.dynamic_content_hash == current_hash
        DiscussionThreadSummarizer::Metrics.increment_render_current(account:)
        RenderResult.new(
          status: :current,
          record:,
          result: parse_summary_record(record),
          enqueued: false
        )
      else
        build_stale_or_rate_limited_stale(discussion_topic:, viewer:, locale:, account:, record:)
      end
    end

    def summarize(discussion_topic:, viewer:)
      account = discussion_topic.context.root_account
      scope_mode = scope_mode_for(discussion_topic)
      payload = gather(discussion_topic, viewer)
      payload = pseudonymize(payload)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = @client.summarize(payload)
      begin
        validate(result)
      rescue DiscussionThreadSummarizer::SchemaViolationError
        Metrics.increment_generation_error(account:, scope_mode:)
        Metrics.increment_failure(reason: "schema_invalid", account:)
        raise
      end
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      Metrics.record_generation_latency_ms(duration_ms: latency_ms, account:, scope_mode:)
      result
    rescue StandardError => e
      unless e.is_a?(DiscussionThreadSummarizer::SchemaViolationError)
        Metrics.increment_generation_error(account:, scope_mode:)
      end
      raise
    ensure
      if t0
        propagating = $!
        emit_audit_log(
          thread_id:         discussion_topic.id,
          scope_mode:        payload[:scope_mode],
          model_identifier:  @client.class.name,
          request_byte_size: payload.to_json.bytesize,
          latency_ms:        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round,
          success:           propagating.nil?,
          error_category:    error_category_for(propagating)
        )
      end
    end

    private

    def find_latest_summary_row(discussion_topic, locale)
      discussion_topic.summaries
                      .where(
                        llm_config_version: LLM_CONFIG_VERSION,
                        parent_id: nil,
                        locale:
                      )
                      .order(created_at: :desc)
                      .first
    end

    def build_generating_or_rate_limited_empty(discussion_topic:, viewer:, locale:, account:)
      case RegenerationRateLimiter.preview(account:, user: viewer, discussion_topic:)
      when :cooldown_denied, :quota_denied
        DiscussionThreadSummarizer::Metrics.increment_render_rate_limited_empty(account:)
        RenderResult.new(status: :rate_limited_empty, record: nil, result: nil, enqueued: false)
      else
        self.class.enqueue_for(discussion_topic:, viewer:)
        DiscussionThreadSummarizer::Metrics.increment_render_generating(account:)
        RenderResult.new(status: :generating, record: nil, result: nil, enqueued: true)
      end
    end

    def build_stale_or_rate_limited_stale(discussion_topic:, viewer:, locale:, account:, record:)
      parsed = parse_summary_record(record)
      case RegenerationRateLimiter.preview(account:, user: viewer, discussion_topic:)
      when :cooldown_denied, :quota_denied
        DiscussionThreadSummarizer::Metrics.increment_render_rate_limited_stale(account:)
        DiscussionThreadSummarizer::Metrics.increment_cache_stale(account:)
        RenderResult.new(status: :rate_limited_stale, record:, result: parsed, enqueued: false)
      else
        self.class.enqueue_for(discussion_topic:, viewer:)
        DiscussionThreadSummarizer::Metrics.increment_render_stale(account:)
        DiscussionThreadSummarizer::Metrics.increment_cache_stale(account:)
        RenderResult.new(status: :stale, record:, result: parsed, enqueued: true)
      end
    end

    def find_cached_summary(discussion_topic, content_hash, locale)
      # NOTE: Cache key assumes discussion_thread_summarizer_scope_limited is OFF.
      # When enabled, gather filters entries by viewer while ContentVersionHash hashes
      # the unfiltered .active set, so this key can return cross-viewer wrong results.
      # Before enabling scope_limited in production, add scope_mode to the cache key
      # or include viewer-filtered entry IDs in the hash. Tracked in
      # https://github.com/ejgdr/canvas-lms/issues/85.
      discussion_topic.summaries
                      .where(
                        llm_config_version: LLM_CONFIG_VERSION,
                        dynamic_content_hash: content_hash,
                        parent_id: nil,
                        locale:
                      )
                      .order(created_at: :desc)
                      .first
    end

    def persist_summary_record(discussion_topic:, viewer:, locale:, content_hash:, result:)
      discussion_topic.summaries.create!(
        llm_config_version: LLM_CONFIG_VERSION,
        dynamic_content_hash: content_hash,
        user: viewer,
        locale:,
        summary: result.to_json,
        parent_id: nil
      )
    end

    def parse_summary_record(record)
      JSON.parse(record.summary, symbolize_names: true)
    end

    def gather(discussion_topic, viewer)
      course        = discussion_topic.context
      scope_limited = course.root_account.feature_enabled?(
        :discussion_thread_summarizer_scope_limited
      )
      scope_mode    = scope_mode_for(discussion_topic, scope_limited:)

      raw_entries = discussion_topic.discussion_entries
                                    .active
                                    .order(:created_at)
                                    .preload(:user)
                                    .to_a

      if scope_limited
        allowed_ids = instructor_user_ids(course) | [viewer.id]
        raw_entries = raw_entries.select { |e| allowed_ids.include?(e.user_id) }
      end

      {
        topic_id:   discussion_topic.id,
        scope_mode:,
        entries:    raw_entries.map do |entry|
                      { author_name: entry.user&.short_name || "Unknown",
                        body:        entry.message || "" }
                    end
      }
    end

    def scope_mode_for(discussion_topic, scope_limited: nil)
      scope_limited = discussion_topic.context.root_account.feature_enabled?(
        :discussion_thread_summarizer_scope_limited
      ) if scope_limited.nil?

      scope_limited ? "limited" : "default"
    end

    def instructor_user_ids(course)
      # Mirrors PromptPresenter#enrollments_by_user (prompt_presenter.rb:116) but
      # cheaper: DB-side type filter + pluck avoids loading full enrollment rows.
      course.enrollments
            .active
            .where(type: %w[TeacherEnrollment TaEnrollment])
            .pluck(:user_id)
            .to_set
    end

    def pseudonymize(payload)
      entries = payload[:entries]
      return payload if entries.nil? || entries.empty?

      result = Pseudonymizer.call(entries)
      # author_map stays in memory only — never logged or forwarded.
      payload.merge(entries: result.pseudonymized_entries)
    end

    def validate(result)
      OutputSchemaValidator.call(result)
    end

    # Maps a propagating exception to an audit log error_category string.
    # Returns nil on the success path ($! == nil).
    # Returns "unknown" for unanticipated exception types so ops dashboards
    # always have a non-null category to filter on when success: false.
    def error_category_for(exception)
      case exception
      when nil                                              then nil
      when DiscussionThreadSummarizer::SchemaViolationError then "schema_invalid"
      when DiscussionThreadSummarizer::TransportError       then "transport_error"
      else "unknown"
      end
    end

    # Emits a structured JSON audit line per generation attempt (FR-5, NFR-2).
    # Raw payload content and author names are never included — metadata only.
    def emit_audit_log(**fields)
      Rails.logger.info(
        { event: "discussion_thread_summarizer.generation_attempt", **fields }.to_json
      )
    end
  end
end
