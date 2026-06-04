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
  # Computes a deterministic SHA-256 content-version hash for a discussion
  # topic's current reply state, for use as a cache key in M3.
  #
  # The hash covers every non-deleted entry's id and message body, sorted by
  # id for determinism. It changes when:
  #   - a new entry is created
  #   - an entry is soft-deleted (workflow_state → "deleted")
  #   - an entry's message body is edited
  #
  # Mirrors the algorithm in DiscussionTopicInsight::Entry.hash_for_dynamic_content
  # (app/models/discussion_topic_insight/entry.rb:43–50): Digest::SHA256.hexdigest
  # over a JSON-serialised structured value, producing a 64-char lowercase hex
  # string.
  #
  # Scope behaviour:
  #   - Default mode (scope_mode: "default"): viewer-agnostic. Produces the same
  #     digest as the original algorithm (Digest::SHA256.hexdigest(tuples.to_json))
  #     so all existing cached rows remain valid after the upgrade — no regeneration
  #     storm on deploy.
  #   - Scope-limited mode (scope_mode: "limited"): folds viewer.id into the digest
  #     so each viewer gets an isolated cache row. Prevents cross-viewer summary
  #     leakage when summaries are built from viewer-specific entry subsets (FR-5).
  #     viewer must not be nil in this mode.
  #
  # Pure utility: no DB writes, no cache interaction, no side effects.
  class ContentVersionHash
    # Returns a 64-char lowercase hex SHA-256 digest.
    #
    # Raises ArgumentError if discussion_topic is nil, or if scope_mode is
    # "limited" and viewer is nil.
    def self.call(discussion_topic, scope_mode: "default", viewer: nil)
      raise ArgumentError, "discussion_topic must not be nil" if discussion_topic.nil?
      if scope_mode == "limited" && viewer.nil?
        raise ArgumentError, "viewer is required when scope_mode is 'limited'"
      end

      rows = discussion_topic
               .discussion_entries
               .active
               .order(:id)
               .pluck(:id, :message)

      tuples = rows.map { |id, msg| { id:, message: msg.to_s } }

      if scope_mode == "limited"
        # Per-viewer key: different viewers on the same topic → different rows.
        Digest::SHA256.hexdigest({ scope_mode:, viewer_id: viewer.id, entries: tuples }.to_json)
      else
        # Default mode: viewer-agnostic, identical to the original algorithm.
        Digest::SHA256.hexdigest(tuples.to_json)
      end
    end
  end
end
