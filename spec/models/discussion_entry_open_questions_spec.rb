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
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

describe DiscussionEntry do
  describe ".open_questions_for_course" do
    before do
      course_with_teacher(active_all: true)
      student_in_course(active_all: true, course: @course)
      original_course = @course
      @other_course = course_model
      @course = original_course
    end

    it "returns unanswered questions for the course oldest-first and excludes answered, dismissed, locked, anonymous, and out-of-course threads" do
      older_topic = @course.discussion_topics.create!(title: "older", user: @teacher)
      newer_topic = @course.discussion_topics.create!(title: "newer", user: @teacher)
      older_question = older_topic.discussion_entries.create!(user: @student, message: "How do I submit this?", created_at: 2.days.ago, updated_at: 2.days.ago)
      newer_question = newer_topic.discussion_entries.create!(user: @student, message: "What does this require?", created_at: 1.day.ago, updated_at: 1.day.ago)
      older_topic.discussion_entries.create!(user: @teacher, parent_entry: older_question, message: "Use the course page")

      dismissed_topic = @course.discussion_topics.create!(title: "dismissed", user: @teacher)
      dismissed_question = dismissed_topic.discussion_entries.create!(user: @student, message: "Where is the rubric?", created_at: 3.days.ago, updated_at: 3.days.ago)
      DiscussionQuestionDismissal.create!(discussion_entry: dismissed_question, user: @teacher)

      locked_topic = @course.discussion_topics.create!(title: "locked", user: @teacher, locked: true)
      locked_topic.discussion_entries.create!(user: @student, message: "Can someone help?")

      anonymous_topic = @course.discussion_topics.create!(title: "anonymous", user: @teacher, anonymous_state: "full_anonymity")
      anonymous_topic.discussion_entries.create!(user: @student, message: "How does this work?")

      out_of_course_topic = @other_course.discussion_topics.create!(title: "other course", user: @teacher)
      out_of_course_question = out_of_course_topic.discussion_entries.create!(user: @student, message: "When is this due?")

      results = described_class.open_questions_for_course(@course).preload(:discussion_topic).to_a

      expect(results.map(&:id)).to eq([newer_question.id])
      expect(results).not_to include(dismissed_question, out_of_course_question)
    end
  end
end
