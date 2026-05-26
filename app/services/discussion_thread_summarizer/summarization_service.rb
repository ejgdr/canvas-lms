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
      payload = gather(discussion_topic, viewer)
      payload = pseudonymize(payload)
      result  = @client.summarize(payload)
      validate(result)
      result
    end

    private

    def gather(discussion_topic, _viewer)
      # Stub: real content extraction lands in a later M2 slice.
      { topic_id: discussion_topic.id }
    end

    def pseudonymize(payload)
      entries = payload[:entries]
      return payload if entries.nil? || entries.empty?

      result = Pseudonymizer.call(entries)
      # author_map stays in memory only — never logged or forwarded.
      payload.merge(entries: result.pseudonymized_entries)
    end

    def validate(_result)
      # Stub: real validator (issue #10) raises on schema violation; this is a no-op.
      nil
    end
  end
end
