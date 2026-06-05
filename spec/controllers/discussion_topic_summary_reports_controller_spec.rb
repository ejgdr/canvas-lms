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

require "spec_helper"

RSpec.describe DiscussionTopicSummaryReportsController, type: :controller do
  let(:site_admin_user) do
    account_admin_user(account: Account.site_admin)
  end

  let(:regular_user) do
    user_with_pseudonym(active_all: true)
  end

  let(:course) { course_model }

  def create_summary(course:, user:)
    hash = DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION
    topic = course.discussion_topics.create!(title: "T", user:)
    topic.summaries.create!(
      user:,
      locale: "en",
      summary: "{}",
      dynamic_content_hash: "abc#{topic.id}",
      llm_config_version: hash
    )
  end

  def create_report(summary, reporter:, reason:, comment: nil, reporter_role: "student")
    DiscussionTopicSummaryReport.create!(
      discussion_topic_summary: summary,
      user: reporter,
      reason:,
      comment:,
      reporter_role:
    )
  end

  describe "GET #index" do
    context "when requester is a site admin" do
      before { user_session(site_admin_user) }

      it "returns grouped counts by reason" do
        teacher = user_with_pseudonym(active_all: true)
        summary = create_summary(course:, user: teacher)

        create_report(summary, reporter: teacher, reason: "inaccurate")
        create_report(summary, reporter: teacher, reason: "inaccurate")
        create_report(summary, reporter: teacher, reason: "other")

        get :index, format: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["grouped_counts"]["inaccurate"]).to eq(2)
        expect(json["grouped_counts"]["other"]).to eq(1)
      end

      it "returns recent reports without user_id" do
        teacher = user_with_pseudonym(active_all: true)
        summary = create_summary(course:, user: teacher)
        create_report(summary, reporter: teacher, reason: "harmful_content", comment: "Bad output")

        get :index, format: :json

        json = response.parsed_body
        report = json["recent_reports"].first
        expect(report).not_to have_key("user_id")
        expect(report["reason"]).to eq("harmful_content")
        expect(report["comment"]).to eq("Bad output")
        expect(report["reporter_role"]).to eq("student")
      end

      it "caps results at 100 per page" do
        teacher = user_with_pseudonym(active_all: true)
        summary = create_summary(course:, user: teacher)

        101.times { create_report(summary, reporter: teacher, reason: "other") }

        get :index, format: :json

        json = response.parsed_body
        expect(json["recent_reports"].length).to eq(100)
        expect(json["per_page"]).to eq(100)
      end
    end

    context "when requester is not a site admin" do
      before { user_session(regular_user) }

      it "returns 403 forbidden" do
        get :index, format: :json

        expect(response).to have_http_status(:forbidden)
        json = response.parsed_body
        expect(json["errors"]).to include("Unauthorized")
      end
    end

    context "when the summarizer flag is off at site-admin scope" do
      before do
        user_session(site_admin_user)
        Account.site_admin.disable_feature!(:discussion_thread_summarizer)
      end

      after do
        Account.site_admin.enable_feature!(:discussion_thread_summarizer)
      end

      it "returns 404" do
        get :index, format: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
