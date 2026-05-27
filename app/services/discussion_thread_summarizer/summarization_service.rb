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
    # Enqueues a background summary attempt via Delayed Job.
    # Mirrors the insight_generation pattern in DiscussionTopicsApiController.
    # Singleton + n_strand ensure at most one job per topic runs at a time.
    def self.enqueue_for(discussion_topic:, viewer:)
      new.delay(
        priority: Delayed::HIGH_PRIORITY,
        singleton: "discussion_thread_summarizer:generation_for_topic:#{discussion_topic.id}",
        n_strand: ["discussion_thread_summarizer:generation:#{Shard.current.database_server.region}", 1]
      ).summarize(discussion_topic:, viewer:)
    end

    def initialize(client: StubModelClient.new)
      @client = client
    end

    def summarize(discussion_topic:, viewer:)
      account = discussion_topic.context.root_account
      payload = gather(discussion_topic, viewer)
      payload = pseudonymize(payload)
      t0      = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = @client.summarize(payload)
      begin
        validate(result)
      rescue DiscussionThreadSummarizer::SchemaViolationError
        Metrics.increment_failure(reason: "schema_invalid", account:)
        raise
      end
      result
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

    def gather(discussion_topic, viewer)
      course        = discussion_topic.context
      scope_limited = course.root_account.feature_enabled?(
        :discussion_thread_summarizer_scope_limited
      )
      scope_mode    = scope_limited ? "limited" : "default"

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
