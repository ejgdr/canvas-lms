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

# Thin service-level invariant: SummarizationService#summarize emits exactly
# one audit log record per call regardless of outcome. Router-level gate
# assertions (flag off, TransportError, PII, scope_mode) live in the API
# integration spec at spec/apis/v1/discussion_thread_summarizer_audit_log_spec.rb.

describe "DiscussionThreadSummarizer audit log one-record-per-attempt invariant" do
  let(:course)   { course_factory(active_all: true) }
  let(:teacher)  { teacher_in_course(course:, active_all: true).user }
  let(:topic) do
    course.discussion_topics.create!(title: "Audit invariant thread", user: teacher)
  end
  let(:logged_payloads) { [] }

  before do
    # Force Zeitwerk to autoload SchemaViolationError before any raise_error arg is evaluated.
    DiscussionThreadSummarizer::OutputSchemaValidator
    course.enable_feature!(:discussion_thread_summarizer)
    topic.discussion_entries.create!(user: teacher, message: "hello")
    allow(Rails.logger).to receive(:info) { |msg| logged_payloads << msg }
  end

  def audit_entries
    logged_payloads.select { |m| m.is_a?(String) && m.include?("generation_attempt") }
  end

  it "success path emits exactly one audit record" do
    DiscussionThreadSummarizer::SummarizationService.new
      .summarize(discussion_topic: topic, viewer: teacher)
    expect(audit_entries.size).to eq(1)
    expect(JSON.parse(audit_entries.first, symbolize_names: true)[:success]).to be(true)
  end

  it "TransportError path emits exactly one audit record with success: false" do
    client = Class.new(DiscussionThreadSummarizer::ModelClient) do
      def summarize(_p)
        raise DiscussionThreadSummarizer::TransportError, "stub"
      end
    end.new

    expect do
      DiscussionThreadSummarizer::SummarizationService.new(client:)
        .summarize(discussion_topic: topic, viewer: teacher)
    end.to raise_error(DiscussionThreadSummarizer::TransportError)

    expect(audit_entries.size).to eq(1)
    expect(JSON.parse(audit_entries.first, symbolize_names: true)[:success]).to be(false)
  end
end
