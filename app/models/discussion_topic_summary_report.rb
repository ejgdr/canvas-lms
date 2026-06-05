# frozen_string_literal: true

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

# Append-only report of an inaccuracy or quality issue against a specific
# DiscussionTopicSummary version. user_id is stored for abuse-prevention purposes
# and must never be serialized in API responses or admin output.
class DiscussionTopicSummaryReport < ApplicationRecord
  belongs_to :discussion_topic_summary
  belongs_to :user

  REASONS = %w[inaccurate missed_viewpoint harmful_content other].freeze
  REPORTER_ROLES = %w[student teacher admin].freeze

  validates :reason, inclusion: { in: REASONS }
  validates :comment, length: { maximum: 500 }, allow_nil: true
  validates :reporter_role, inclusion: { in: REPORTER_ROLES }
end
