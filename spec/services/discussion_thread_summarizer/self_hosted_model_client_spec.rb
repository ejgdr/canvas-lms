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

require "webmock/rspec"

describe DiscussionThreadSummarizer::SelfHostedModelClient do
  subject(:client) { described_class.new }

  let(:endpoint_url) { "http://llm.example.internal/summarize" }
  let(:valid_response) do
    {
      themes: ["Theme A"],
      viewpoints: ["Viewpoint A"],
      open_questions: ["Question A?"],
      scope_mode: "default"
    }
  end
  let(:payload) { { topic_id: 1, scope_mode: "default", entries: [{ author_name: "Author A", body: "Post" }] } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return(endpoint_url)
    allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_TOKEN").and_return(nil)
    allow(ENV).to receive(:fetch).with("SUMMARIZER_ENDPOINT_URL", "").and_return(endpoint_url)
    allow(ENV).to receive(:present?).and_call_original
  end

  it "is a ModelClient subclass" do
    expect(client).to be_a(DiscussionThreadSummarizer::ModelClient)
  end

  describe "#summarize" do
    context "when the endpoint returns a valid response" do
      before do
        stub_request(:post, endpoint_url)
          .to_return(
            status: 200,
            body: valid_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns a symbolized-key hash from the response body" do
        result = client.summarize(payload)
        expect(result).to eq(valid_response)
      end

      it "sends the payload as JSON in the request body" do
        client.summarize(payload)
        expect(
          a_request(:post, endpoint_url).with(body: payload.to_json)
        ).to have_been_made.once
      end

      it "sets Content-Type: application/json" do
        client.summarize(payload)
        expect(
          a_request(:post, endpoint_url)
            .with(headers: { "Content-Type" => "application/json" })
        ).to have_been_made.once
      end
    end

    context "when SUMMARIZER_ENDPOINT_TOKEN is set" do
      before do
        allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_TOKEN").and_return("secret-token")
        stub_request(:post, endpoint_url)
          .to_return(status: 200, body: valid_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "sends Authorization: Bearer header" do
        client.summarize(payload)
        expect(
          a_request(:post, endpoint_url)
            .with(headers: { "Authorization" => "Bearer secret-token" })
        ).to have_been_made.once
      end
    end

    context "when SUMMARIZER_ENDPOINT_URL is blank" do
      before { allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return(nil) }

      it "raises TransportError" do
        expect { client.summarize(payload) }.to raise_error(
          DiscussionThreadSummarizer::TransportError,
          /SUMMARIZER_ENDPOINT_URL is not configured/
        )
      end
    end

    context "when the endpoint returns a non-2xx status" do
      before do
        stub_request(:post, endpoint_url).to_return(status: 503, body: "Service Unavailable")
      end

      it "raises TransportError with the HTTP status code" do
        expect { client.summarize(payload) }.to raise_error(
          DiscussionThreadSummarizer::TransportError,
          /HTTP 503/
        )
      end
    end

    context "when the endpoint returns invalid JSON" do
      before do
        stub_request(:post, endpoint_url)
          .to_return(status: 200, body: "not json", headers: { "Content-Type" => "application/json" })
      end

      it "raises TransportError" do
        expect { client.summarize(payload) }.to raise_error(
          DiscussionThreadSummarizer::TransportError,
          /invalid JSON/
        )
      end
    end

    context "when the connection is refused" do
      before { stub_request(:post, endpoint_url).to_raise(Errno::ECONNREFUSED) }

      it "raises TransportError" do
        expect { client.summarize(payload) }.to raise_error(
          DiscussionThreadSummarizer::TransportError,
          /unreachable/
        )
      end
    end

    context "when the connection times out" do
      before { stub_request(:post, endpoint_url).to_raise(Net::ReadTimeout) }

      it "raises TransportError" do
        expect { client.summarize(payload) }.to raise_error(
          DiscussionThreadSummarizer::TransportError,
          /timed out/
        )
      end
    end
  end

  describe "#model_identifier" do
    it "returns self-hosted:<host><path>" do
      expect(client.model_identifier).to eq("self-hosted:llm.example.internal/summarize")
    end

    it "excludes scheme and any credentials from the identifier" do
      allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL")
                                .and_return("https://user:pass@llm.example.internal/summarize")
      allow(ENV).to receive(:fetch).with("SUMMARIZER_ENDPOINT_URL", "")
                                   .and_return("https://user:pass@llm.example.internal/summarize")
      expect(client.model_identifier).to eq("self-hosted:llm.example.internal/summarize")
    end

    context "when SUMMARIZER_ENDPOINT_URL is empty" do
      before do
        allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return("")
        allow(ENV).to receive(:fetch).with("SUMMARIZER_ENDPOINT_URL", "").and_return("")
      end

      it "returns self-hosted:unknown" do
        expect(client.model_identifier).to eq("self-hosted:unknown")
      end
    end
  end
end
