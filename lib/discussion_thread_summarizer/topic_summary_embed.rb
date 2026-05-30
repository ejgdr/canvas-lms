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
  # Builds the additive thread-summary payload for DiscussionTopic REST/GraphQL
  # surfaces. Reuses SummarizationService#lookup_for_render for status semantics.
  module TopicSummaryEmbed
    OMIT = Object.new.freeze

    module_function

    # @return [Object] OMIT when flag off; nil when flag on but no summary object;
    #   otherwise a Hash with :text, :status, :generated_at (Time; ISO 8601 in REST)
    def rest_value(discussion_topic:, viewer:, locale: I18n.locale.to_s, session: nil)
      payload = embed_payload(discussion_topic:, viewer:, locale:, session:)
      return payload if payload == OMIT || payload.nil?
      return payload if payload[:generated_at].nil?

      payload.merge(generated_at: payload[:generated_at].iso8601)
    end

    # @return [Hash, nil] nil when flag off, gated, or no summary object
    def graphql_value(discussion_topic:, viewer:, locale: I18n.locale.to_s, session: nil)
      payload = embed_payload(discussion_topic:, viewer:, locale:, session:)
      payload == OMIT ? nil : payload
    end

    def embed_payload(discussion_topic:, viewer:, locale: I18n.locale.to_s, session: nil)
      course = discussion_topic.context
      return OMIT unless course.is_a?(Course) && course.feature_enabled?(:discussion_thread_summarizer)
      return nil unless discussion_topic.visible_for?(viewer)
      return nil unless discussion_topic.user_can_see_posts?(viewer, session)

      result = SummarizationService.new.lookup_for_render(
        discussion_topic:,
        viewer:,
        locale:
      )
      return OMIT if result.status == :disabled

      payload_from_render_result(result)
    end

    def payload_from_render_result(result)
      case result.status
      when :generating
        { text: nil, status: "generating", generated_at: nil }
      when :rate_limited_empty
        nil
      when :current, :stale, :rate_limited_stale
        record = result.record
        return nil unless record

        {
          text: format_summary_text(result.result),
          status: api_status_for(result.status),
          generated_at: record.created_at
        }
      end
    end

    def api_status_for(render_status)
      case render_status
      when :current then "current"
      when :stale then "stale"
      when :rate_limited_stale then "unavailable"
      end
    end

    def format_summary_text(parsed)
      return nil unless parsed.is_a?(Hash)

      sections = []
      themes = parsed[:themes] || parsed["themes"]
      viewpoints = parsed[:viewpoints] || parsed["viewpoints"]
      open_questions = parsed[:open_questions] || parsed["open_questions"]

      if themes.is_a?(Array) && themes.any?
        sections << themes.map { |theme| "• #{theme}" }.join("\n")
      end
      if viewpoints.is_a?(Array) && viewpoints.any?
        sections << viewpoints.map { |viewpoint| "• #{viewpoint}" }.join("\n")
      end
      if open_questions.is_a?(Array) && open_questions.any?
        sections << open_questions.map { |question| "• #{question}" }.join("\n")
      end

      sections.join("\n\n").strip.presence
    end
  end
end
