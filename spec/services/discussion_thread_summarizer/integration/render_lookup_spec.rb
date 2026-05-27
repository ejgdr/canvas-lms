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

describe "DiscussionThreadSummarizer render lookup integration" do
  let(:course)  { course_factory(active_all: true) }
  let(:teacher) { teacher_in_course(course:, active_all: true).user }
  let(:topic) do
    course.discussion_topics.create!(
      title:   "Test thread",
      message: "Discuss here",
      user:    teacher
    )
  end
  let(:service) { DiscussionThreadSummarizer::SummarizationService.new }

  before do
    course.enable_feature!(:discussion_thread_summarizer)
    topic.discussion_entries.create!(user: teacher, message: "Teacher says hello.")
    allow(Canvas).to receive(:redis_enabled?).and_return(true)
    allow(Canvas.redis).to receive(:get).and_return(nil)
    allow(Rails.logger).to receive(:info)
  end

  it "generating lookup enqueues a job and a subsequent lookup is :current after run_jobs" do
    first = service.lookup_for_render(discussion_topic: topic, viewer: teacher, locale: "en")

    expect(first.status).to eq(:generating)
    expect(first.enqueued).to be(true)

    expect { run_jobs }.not_to raise_error

    second = service.lookup_for_render(discussion_topic: topic, viewer: teacher, locale: "en")

    expect(second.status).to eq(:current)
    expect(second.result).to eq(DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE)
    expect(topic.summaries.count).to eq(1)
  end
end
