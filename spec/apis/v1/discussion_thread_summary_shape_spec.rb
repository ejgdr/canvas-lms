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

require_relative "../api_spec_helper"

# Smoke-level integration coverage for additive thread-summary fields on Discussion
# REST show and GraphQL Discussion. Exercises routing, token auth, and real
# serialization (Api::V1::DiscussionTopics / CanvasSchema) rather than calling
# controller actions or GraphQLTypeTester in isolation (#21 unit matrix).
RSpec.describe "Discussion thread summary response shapes", type: :request do
  before(:once) do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true, course: @course)
    @topic = @course.discussion_topics.create!(title: "Summary shape topic", user: @teacher)
    @topic.discussion_entries.create!(user: @teacher, message: "hello")
  end

  before do
    @user = @student
    allow(Canvas).to receive(:redis_enabled?).and_return(true)
    allow(Canvas.redis).to receive(:get).and_return(nil)
  end

  let(:show_path) { "/api/v1/courses/#{@course.id}/discussion_topics/#{@topic.id}" }
  let(:show_route_params) do
    {
      controller: "discussion_topics_api",
      action: "show",
      format: "json",
      course_id: @course.id.to_s,
      topic_id: @topic.id.to_s
    }
  end

  def fetch_show_json
    api_call(:get, show_path, show_route_params)
  end

  def fetch_graphql_discussion_node
    type, = CanvasSchema.resolve_type(nil, @topic, { current_user: @student })
    node_id = CanvasSchema.id_from_object(@topic, type, { current_user: @student })
    query = <<~GQL
      query($id: ID!) {
        node(id: $id) {
          ... on Discussion {
            _id
            title
            summary {
              text
              status
              generatedAt
            }
            entryCounts {
              repliesCount
            }
            discussionEntriesConnection {
              edges {
                node {
                  _id
                }
              }
            }
          }
        }
      }
    GQL
    result = CanvasSchema.execute(
      query,
      context: { current_user: @student, request: ActionDispatch::TestRequest.create },
      variables: { id: node_id }
    )
    expect(result["errors"]).to be_blank
    result.dig("data", "node")
  end

  def seed_cached_summary(created_at: 1.hour.ago.change(usec: 0))
    locale = I18n.locale.to_s
    content_hash = DiscussionThreadSummarizer::ContentVersionHash.call(@topic)
    @topic.summaries.create!(
      user: @student,
      locale:,
      summary: DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE.to_json,
      dynamic_content_hash: content_hash,
      llm_config_version: DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION,
      created_at:
    )
    created_at
  end

  describe "REST GET show" do
    it "omits summary when the discussion_thread_summarizer flag is off" do
      @course.disable_feature!(:discussion_thread_summarizer)

      json = fetch_show_json

      expect(json).not_to have_key("summary")
      expect(json["id"]).to eq(@topic.id)
      expect(json["title"]).to eq("Summary shape topic")
      expect(json).to have_key("discussion_subentry_count")
    end

    it "leaves existing top-level keys unchanged when toggling the flag" do
      @course.disable_feature!(:discussion_thread_summarizer)
      baseline_keys = fetch_show_json.keys.sort

      @course.enable_feature!(:discussion_thread_summarizer)
      allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview)
        .and_return(:cooldown_denied)

      json = fetch_show_json
      expect(json.except("summary").keys.sort).to eq(baseline_keys)
    end

    it "returns a populated summary when the flag is on and a cache row matches" do
      @course.enable_feature!(:discussion_thread_summarizer)
      created_at = seed_cached_summary

      json = fetch_show_json
      summary = json["summary"]

      expect(summary["status"]).to eq("current")
      expect(summary["text"]).to include("Main theme A")
      expect(summary["generated_at"]).to eq(created_at.iso8601)
    end

    it "returns null summary when the flag is on and generation has not started" do
      @course.enable_feature!(:discussion_thread_summarizer)
      allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview)
        .and_return(:cooldown_denied)

      json = fetch_show_json

      expect(json).to have_key("summary")
      expect(json["summary"]).to be_nil
    end
  end

  describe "GraphQL Discussion.summary" do
    it "returns null summary when the discussion_thread_summarizer flag is off" do
      @course.disable_feature!(:discussion_thread_summarizer)

      node = fetch_graphql_discussion_node

      expect(node["summary"]).to be_nil
      expect(node.dig("entryCounts", "repliesCount")).to eq(1)
      expect(node.dig("discussionEntriesConnection", "edges").length).to eq(1)
    end

    it "leaves sibling fields unchanged when toggling the flag" do
      @course.disable_feature!(:discussion_thread_summarizer)
      baseline = fetch_graphql_discussion_node.except("summary")

      @course.enable_feature!(:discussion_thread_summarizer)
      allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview)
        .and_return(:cooldown_denied)

      node = fetch_graphql_discussion_node
      expect(node.except("summary")).to eq(baseline)
    end

    it "returns a populated summary when the flag is on and a cache row matches" do
      @course.enable_feature!(:discussion_thread_summarizer)
      seed_cached_summary

      node = fetch_graphql_discussion_node
      summary = node["summary"]

      expect(summary["status"]).to eq("current")
      expect(summary["text"]).to include("Main theme A")
      expect(summary["generatedAt"]).to be_present
    end

    it "returns null summary when the flag is on and generation has not started" do
      @course.enable_feature!(:discussion_thread_summarizer)
      allow(DiscussionThreadSummarizer::RegenerationRateLimiter).to receive(:preview)
        .and_return(:cooldown_denied)

      node = fetch_graphql_discussion_node

      expect(node["summary"]).to be_nil
      expect(node.dig("entryCounts", "repliesCount")).to eq(1)
    end
  end
end
