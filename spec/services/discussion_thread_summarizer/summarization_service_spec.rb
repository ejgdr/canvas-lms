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

describe DiscussionThreadSummarizer::SummarizationService do
  let(:stub_client) { DiscussionThreadSummarizer::StubModelClient.new }
  let(:service)     { described_class.new(client: stub_client) }
  let(:topic)       { instance_double("DiscussionTopic", id: 42) }
  let(:viewer)      { instance_double("User") }

  describe "#summarize" do
    it "calls the injected client with a payload derived from the topic" do
      allow(stub_client).to receive(:summarize).and_call_original
      service.summarize(discussion_topic: topic, viewer:)
      expect(stub_client).to have_received(:summarize).with(hash_including(topic_id: 42))
    end

    it "returns the client's output unchanged in this skeleton" do
      result = service.summarize(discussion_topic: topic, viewer:)
      expect(result).to eq(DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE)
    end

    it "accepts any ModelClient implementation (dependency injection)" do
      custom_client = Class.new(DiscussionThreadSummarizer::ModelClient) do
        def summarize(_payload)
          { themes: ["from custom client"], viewpoints: [], open_questions: [], scope_mode: "default" }
        end
      end.new

      result = described_class.new(client: custom_client)
                              .summarize(discussion_topic: topic, viewer:)
      expect(result[:themes]).to eq(["from custom client"])
    end

    it "strips real author names from the payload when entries are present" do
      capturing_client = Class.new(DiscussionThreadSummarizer::ModelClient) do
        attr_reader :received_payload

        def summarize(payload)
          @received_payload = payload
          { themes: [], viewpoints: [], open_questions: [], scope_mode: "default" }
        end
      end.new

      svc = described_class.new(client: capturing_client)
      allow(svc).to receive(:gather).and_return(
        {
          topic_id: 42,
          entries:  [
            { author_name: "Alice", body: "post one"   },
            { author_name: "Bob",   body: "post two"   },
            { author_name: "Alice", body: "post three" },
          ]
        }
      )
      svc.summarize(discussion_topic: topic, viewer:)

      received_names = capturing_client.received_payload[:entries].map { |e| e[:author_name] }
      expect(received_names).to eq(["Author A", "Author B", "Author A"])
      expect(received_names).not_to include("Alice", "Bob")
    end
  end
end
