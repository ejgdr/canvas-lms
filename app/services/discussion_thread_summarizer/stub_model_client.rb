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
  # Deterministic ModelClient implementation for use in tests and in local
  # development before a real model endpoint is wired. Always returns
  # FIXED_RESPONSE regardless of the payload, making test assertions stable
  # without any network access.
  #
  # To exercise the failure path in tests, subclass or double this client and
  # configure #summarize to raise DiscussionThreadSummarizer::TransportError.
  class StubModelClient < ModelClient
    FIXED_RESPONSE = {
      themes: ["Main theme A", "Main theme B"],
      viewpoints: ["Majority viewpoint", "Minority viewpoint"],
      open_questions: ["What are the next steps?"],
      scope_mode: "default"
    }.freeze

    def summarize(_payload)
      FIXED_RESPONSE
    end
  end
end
