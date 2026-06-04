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

# Full-stack integration coverage for the Open Questions digest endpoints (#33).
# Exercises real routing, Bearer-token auth, and ActiveRecord model scopes.
# Backend shipped in PR #125; frontend + index ENV in PR #126.
RSpec.describe "Open Questions digest", type: :request do
  before(:once) do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true, course: @course)
    @course.root_account.allow_feature!(:discussion_thread_summarizer)
    @course.enable_feature!(:discussion_thread_summarizer)

    @topic_a = @course.discussion_topics.create!(title: "Topic A", user: @teacher)
    @topic_b = @course.discussion_topics.create!(title: "Topic B", user: @teacher)

    # Two open questions with explicit created_ats to assert oldest-first ordering
    @q_older = @topic_a.discussion_entries.create!(
      user: @student,
      message: "What is the main point?",
      created_at: 3.days.ago
    )
    @q_newer = @topic_b.discussion_entries.create!(
      user: @student,
      message: "How does this apply in practice?",
      created_at: 1.day.ago
    )
  end

  let(:open_questions_path) { "/api/v1/courses/#{@course.id}/discussion_topics/open_questions" }
  let(:open_questions_params) do
    {
      controller: "discussion_topics_api",
      action: "open_questions",
      format: "json",
      course_id: @course.id.to_s
    }
  end

  def dismiss_path(question_id)
    "/api/v1/courses/#{@course.id}/discussion_questions/#{question_id}/dismiss"
  end

  def dismiss_params(question_id)
    {
      controller: "discussion_topics_api",
      action: "dismiss_question",
      format: "json",
      course_id: @course.id.to_s,
      id: question_id.to_s
    }
  end

  def fetch_questions(as_user: @teacher)
    @user = as_user
    api_call(:get, open_questions_path, open_questions_params)
  end

  def dismiss_question(question_id, as_user: @teacher)
    @user = as_user
    raw_api_call(:post, dismiss_path(question_id), dismiss_params(question_id))
  end

  describe "route recognition guard" do
    it "resolves GET .../discussion_topics/open_questions to the open_questions action" do
      recognized = Rails.application.routes.recognize_path(
        "/api/v1/courses/#{@course.id}/discussion_topics/open_questions",
        method: :get
      )
      expect(recognized[:action]).to eq("open_questions")
      expect(recognized[:controller]).to eq("discussion_topics_api")
    end
  end

  describe "GET open_questions" do
    it "returns 200 with questions oldest-first for a moderator with the flag on" do
      json = fetch_questions
      expect(response).to have_http_status(:ok)
      expect(json.length).to eq(2)
      expect(json[0]["question_id"]).to eq(@q_older.id)
      expect(json[1]["question_id"]).to eq(@q_newer.id)
    end

    it "includes all required JSON fields on each row" do
      json = fetch_questions
      row = json[0]
      expect(row.keys).to include("question_id", "thread_id", "thread_title", "question_text", "created_at", "deep_link")
      expect(row["thread_id"]).to eq(@topic_a.id)
      expect(row["thread_title"]).to eq("Topic A")
      expect(row["question_text"]).to eq("What is the main point?")
      expect(row["created_at"]).to eq(@q_older.created_at.iso8601)
      expect(row["deep_link"]).to include("entry-#{@q_older.id}")
    end

    it "returns 404 when the flag is off" do
      @course.disable_feature!(:discussion_thread_summarizer)
      fetch_questions
      expect(response).to have_http_status(:not_found)
    ensure
      @course.enable_feature!(:discussion_thread_summarizer)
    end

    it "returns 403 for a user without moderate_forum" do
      fetch_questions(as_user: @student)
      expect(response).to have_http_status(:forbidden)
    end

    it "excludes questions that have an active reply" do
      @q_older.discussion_subentries.create!(
        user: @teacher,
        message: "Good question — here's the answer.",
        discussion_topic: @topic_a
      )
      json = fetch_questions
      ids = json.map { |q| q["question_id"] }
      expect(ids).not_to include(@q_older.id)
      expect(ids).to include(@q_newer.id)
    end

    it "excludes questions dismissed by the requesting moderator" do
      DiscussionQuestionDismissal.create!(discussion_entry: @q_older, user: @teacher)
      json = fetch_questions
      ids = json.map { |q| q["question_id"] }
      expect(ids).not_to include(@q_older.id)
      expect(ids).to include(@q_newer.id)
    end
  end

  describe "POST dismiss_question + round-trip" do
    it "returns 204 on a successful dismiss" do
      dismiss_question(@q_older.id)
      expect(response).to have_http_status(:no_content)
    end

    it "removes the dismissed question from subsequent digest calls" do
      dismiss_question(@q_older.id)
      json = fetch_questions
      ids = json.map { |q| q["question_id"] }
      expect(ids).not_to include(@q_older.id)
      expect(ids).to include(@q_newer.id)
    end

    it "dismissal is per-user: another moderator still sees the question" do
      original_teacher = @teacher
      other_teacher = teacher_in_course(active_all: true, course: @course).user
      dismiss_question(@q_older.id, as_user: original_teacher)
      json = fetch_questions(as_user: other_teacher)
      ids = json.map { |q| q["question_id"] }
      expect(ids).to include(@q_older.id)
    end
  end
end
