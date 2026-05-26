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
  #
  # The three private pipeline stubs (gather, pseudonymize, validate) are
  # no-ops in this scaffold slice. Each carries a comment naming the future
  # slice that replaces it with real logic.
  class SummarizationService
    def initialize(client: StubModelClient.new)
      @client = client
    end

    def summarize(discussion_topic:, viewer:)
      account = discussion_topic.context.root_account
      payload = gather(discussion_topic, viewer)
      payload = pseudonymize(payload)
      result  = @client.summarize(payload)
      begin
        validate(result)
      rescue DiscussionThreadSummarizer::SchemaViolationError
        Metrics.increment_failure(reason: "schema_invalid", account:)
        raise
      end
      result
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
  end
end
