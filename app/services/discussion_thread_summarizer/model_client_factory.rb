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
  # Selects the appropriate ModelClient implementation at enqueue time.
  #
  # Selection order:
  #   1. SUMMARIZER_ENDPOINT_URL set → SelfHostedModelClient
  #   2. Default                     → StubModelClient
  #
  # This is the single provider-selection point: all code that instantiates
  # SummarizationService for production use goes through this factory, so
  # toggling the env var is the only operator action needed to switch adapters.
  class ModelClientFactory
    def self.build
      if ENV["SUMMARIZER_ENDPOINT_URL"].present?
        SelfHostedModelClient.new
      else
        StubModelClient.new
      end
    end
  end
end
