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

# Internal-only site-admin view for recent summary quality reports.
# Grouped counts by reason + paginated recent list.
# Never exposes user_id — only reporter_role is surfaced.
class DiscussionTopicSummaryReportsController < ApplicationController
  before_action :require_user

  PER_PAGE = 100

  def index
    unless Account.site_admin.grants_right?(@current_user, :read)
      return render json: {errors: ["Unauthorized"]}, status: :forbidden
    end

    page = [params[:page].to_i, 1].max
    offset = (page - 1) * PER_PAGE

    grouped = DiscussionTopicSummaryReport
                .group(:reason)
                .count
                .sort_by { |_, v| -v }
                .to_h

    recent = DiscussionTopicSummaryReport
               .order(created_at: :desc)
               .limit(PER_PAGE)
               .offset(offset)
               .pluck(:id, :reason, :comment, :reporter_role, :created_at)
               .map do |id, reason, comment, reporter_role, created_at|
                 {
                   id:,
                   reason:,
                   comment:,
                   reporter_role:,
                   created_at:
                 }
               end

    render json: {
      grouped_counts: grouped,
      recent_reports: recent,
      page:,
      per_page: PER_PAGE
    }
  end
end
