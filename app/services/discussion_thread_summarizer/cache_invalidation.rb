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
  # Write-side cache invalidation for DiscussionTopicSummary rows.
  # Meaningful changes leave rows as hash orphans (stale-aware lookup in #84).
  # Below-threshold message edits rekey dynamic_content_hash without regeneration.
  class CacheInvalidation
    SETTING_KEY = "discussion_thread_summarizer_meaningful_change_word_threshold"
    DEFAULT_WORD_THRESHOLD = 5

    def self.handle_entry_created(entry)
      new(entry).handle_created
    end

    def self.handle_entry_updated(entry, message_before:, message_after:)
      new(entry).handle_updated(message_before:, message_after:)
    end

    def self.handle_entry_deleted(entry)
      new(entry).handle_deleted
    end

    def initialize(entry)
      @entry = entry
      @topic = entry.discussion_topic
    end

    def handle_created
      return unless enabled?

      Metrics.increment_invalidation_fired(cause: "create", account:)
    end

    def handle_deleted
      return unless enabled?

      Metrics.increment_invalidation_fired(cause: "delete", account:)
    end

    def handle_updated(message_before:, message_after:)
      return unless enabled?

      delta = word_delta(message_before, message_after)
      if delta < word_threshold
        rekey_summaries
        Metrics.increment_invalidation_skipped_below_threshold(account:)
      else
        Metrics.increment_invalidation_fired(cause: "edit", account:)
      end
    end

    private

    def enabled?
      course = @topic&.context
      course.is_a?(Course) && course.feature_enabled?(:discussion_thread_summarizer)
    end

    def account
      @topic.context.root_account
    end

    def word_threshold
      Setting.get(SETTING_KEY, DEFAULT_WORD_THRESHOLD.to_s).to_i
    end

    def word_delta(before, after)
      count = ->(msg) { HtmlTextHelper.strip_tags(msg.to_s).split.size }
      (count.call(after) - count.call(before)).abs
    end

    def rekey_summaries
      new_hash = ContentVersionHash.call(@topic)
      # NOTE: Rekey updates dynamic_content_hash to the post-edit content hash
      # even though the stored summary text was generated from the pre-edit content.
      # This is the intended behavior per #17 AC: below-threshold edits do not
      # trigger regeneration. The hash semantically means "the content this summary
      # is considered current for", not "the content this summary was generated from".
      # See https://github.com/ejgdr/canvas-lms/issues/17 for the threshold definition.
      @topic.summaries
            .where(
              llm_config_version: SummarizationService::LLM_CONFIG_VERSION,
              parent_id: nil
            )
            .update_all(dynamic_content_hash: new_hash, updated_at: Time.current)
    end
  end
end
