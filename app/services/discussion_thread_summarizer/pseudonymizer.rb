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
  # Replaces each entry's :author_name with a stable per-thread pseudonym
  # ("Author A", "Author B", …) before any content crosses the application
  # boundary to the model client.
  #
  # Assignment is first-seen: the first distinct author encountered receives
  # "Author A", the second "Author B", and so on. The mapping is deterministic
  # within a single call but is NOT persisted across requests.
  #
  # Returns a Result with:
  #   pseudonymized_entries — the transformed array (new hashes; input not mutated)
  #   author_map            — { real_name => label } for potential UI re-insertion
  #
  # The caller (SummarizationService) currently discards author_map. When M4
  # introduces summary rendering that references pseudonyms, the map will need
  # to be threaded through the service's return value.
  class Pseudonymizer
    Result = Struct.new(:pseudonymized_entries, :author_map)

    def self.call(entries)
      new.call(entries)
    end

    def call(entries)
      author_map = {}
      counter    = 0

      pseudonymized = entries.map do |entry|
        real_name = entry[:author_name]
        unless author_map.key?(real_name)
          author_map[real_name] = "Author #{("A".ord + counter).chr}"
          counter += 1
        end
        entry.merge(author_name: author_map[real_name])
      end

      Result.new(pseudonymized, author_map.freeze)
    end
  end
end
