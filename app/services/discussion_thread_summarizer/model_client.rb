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
  # Raised by any ModelClient implementation on unrecoverable transport or
  # service failure. Defined at the namespace level so callers (jobs, controllers)
  # can rescue DiscussionThreadSummarizer::TransportError without knowing which
  # concrete client raised it. Future error subclasses (TimeoutError,
  # RateLimitedError, etc.) will also live at this level; if they multiply,
  # extract to a dedicated errors.rb at that point.
  TransportError = Class.new(StandardError)

  # Abstract base class defining the contract every model client must satisfy.
  # Concrete implementations: StubModelClient (this slice), real HTTP adapter
  # (a later M2 slice).
  #
  # #summarize(payload) must:
  #   - Accept a Hash payload built by SummarizationService#gather + #pseudonymize.
  #   - Return a Hash with at minimum:
  #       :themes         (Array<String>)
  #       :viewpoints     (Array<String>)
  #       :open_questions (Array<String>)
  #       :scope_mode     (String)
  #   - Raise DiscussionThreadSummarizer::TransportError on any unrecoverable
  #     transport or service failure so callers can handle it uniformly.
  class ModelClient
    def summarize(payload)
      raise NotImplementedError, "#{self.class}#summarize must be implemented"
    end

    # Returns a loggable identifier for this adapter — never a raw URL or credential.
    # Concrete clients may override to return a more descriptive string.
    def model_identifier
      self.class.name
    end
  end
end
