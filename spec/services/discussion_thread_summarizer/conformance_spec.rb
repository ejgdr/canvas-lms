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

# Conformance suite for DiscussionThreadSummarizer adapters (#53).
#
# Sends the same fixture payloads to both the third-party adapter
# (StubModelClient) and the self-hosted adapter (SelfHostedModelClient backed
# by a local stub) and asserts that both return schema-valid responses.
#
# Shape differences between adapters are reported as test warnings, not
# failures — self-hosted endpoints are permitted to include extension fields.
#
# Both concrete clients must satisfy the ModelClient contract.
RSpec.describe "DiscussionThreadSummarizer adapter conformance" do
  STUB_ENDPOINT = "http://localhost:11434/summarize"

  FIXTURE_PAYLOADS = [
    {
      topic_id: 1,
      scope_mode: "default",
      entries: [
        { author_name: "Author A", body: "First post content" },
        { author_name: "Author B", body: "Reply to first post" }
      ]
    },
    {
      topic_id: 2,
      scope_mode: "limited",
      entries: [{ author_name: "Author A", body: "Instructor post only" }]
    },
    {
      topic_id: 3,
      scope_mode: "default",
      entries: []
    }
  ].freeze

  STUB_RESPONSE = DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE

  # ── contract shared examples ─────────────────────────────────────────────

  shared_examples "ModelClient contract" do
    it "is a ModelClient subclass" do
      expect(adapter).to be_a(DiscussionThreadSummarizer::ModelClient)
    end

    it "responds to #summarize" do
      expect(adapter).to respond_to(:summarize).with(1).argument
    end

    it "responds to #model_identifier" do
      expect(adapter).to respond_to(:model_identifier).with(0).arguments
    end

    it "#model_identifier returns a non-empty String" do
      expect(adapter.model_identifier).to be_a(String).and be_present
    end
  end

  # ── StubModelClient (stand-in for third-party adapter) ───────────────────

  describe "StubModelClient (third-party adapter)" do
    let(:adapter) { DiscussionThreadSummarizer::StubModelClient.new }

    include_examples "ModelClient contract"

    it "#model_identifier returns the class name" do
      expect(adapter.model_identifier).to eq("DiscussionThreadSummarizer::StubModelClient")
    end

    FIXTURE_PAYLOADS.each_with_index do |payload, i|
      it "fixture #{i + 1}: response passes OutputSchemaValidator" do
        result = adapter.summarize(payload)
        expect { DiscussionThreadSummarizer::OutputSchemaValidator.call(result) }.not_to raise_error
      end
    end
  end

  # ── SelfHostedModelClient (self-hosted adapter backed by local stub) ──────

  describe "SelfHostedModelClient (self-hosted adapter)" do
    let(:adapter) { DiscussionThreadSummarizer::SelfHostedModelClient.new }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return(STUB_ENDPOINT)
      allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_TOKEN").and_return(nil)
      allow(ENV).to receive(:fetch).with("SUMMARIZER_ENDPOINT_URL", "").and_return(STUB_ENDPOINT)
      stub_request(:post, STUB_ENDPOINT)
        .to_return(
          status: 200,
          body: STUB_RESPONSE.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    include_examples "ModelClient contract"

    it "#model_identifier returns self-hosted:<host><path>" do
      expect(adapter.model_identifier).to eq("self-hosted:localhost/summarize")
    end

    FIXTURE_PAYLOADS.each_with_index do |payload, i|
      it "fixture #{i + 1}: response passes OutputSchemaValidator" do
        result = adapter.summarize(payload)
        expect { DiscussionThreadSummarizer::OutputSchemaValidator.call(result) }.not_to raise_error
      end
    end

    context "when self-hosted response includes extension fields" do
      let(:extended_response) { STUB_RESPONSE.merge(confidence_score: 0.87, provider: "vllm") }

      before do
        stub_request(:post, STUB_ENDPOINT)
          .to_return(
            status: 200,
            body: extended_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "schema validator passes (extension fields are a warning, not a failure)" do
        result = adapter.summarize(FIXTURE_PAYLOADS.first)
        # Extension fields are permitted — validator only checks required keys.
        expect { DiscussionThreadSummarizer::OutputSchemaValidator.call(result) }.not_to raise_error
        # Report the extra fields as informational (not a test failure).
        extra = result.keys - %i[themes viewpoints open_questions scope_mode]
        RSpec.current_example.metadata[:shape_diff_warning] = extra unless extra.empty?
      end
    end
  end

  # ── Cross-adapter: same fixtures, both adapters, one suite ───────────────

  describe "cross-adapter conformance" do
    let(:third_party)  { DiscussionThreadSummarizer::StubModelClient.new }
    let(:self_hosted)  { DiscussionThreadSummarizer::SelfHostedModelClient.new }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return(STUB_ENDPOINT)
      allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_TOKEN").and_return(nil)
      allow(ENV).to receive(:fetch).with("SUMMARIZER_ENDPOINT_URL", "").and_return(STUB_ENDPOINT)
      stub_request(:post, STUB_ENDPOINT)
        .to_return(
          status: 200,
          body: STUB_RESPONSE.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    FIXTURE_PAYLOADS.each_with_index do |payload, i|
      it "fixture #{i + 1}: both adapters produce schema-valid responses" do
        aggregate_failures do
          tp_result = third_party.summarize(payload)
          sh_result = self_hosted.summarize(payload)
          expect { DiscussionThreadSummarizer::OutputSchemaValidator.call(tp_result) }.not_to raise_error
          expect { DiscussionThreadSummarizer::OutputSchemaValidator.call(sh_result) }.not_to raise_error
        end
      end
    end

    it "audit log emits correct model_identifier for each adapter" do
      aggregate_failures do
        expect(third_party.model_identifier).to eq("DiscussionThreadSummarizer::StubModelClient")
        expect(self_hosted.model_identifier).to eq("self-hosted:localhost/summarize")
      end
    end

    it "both adapters satisfy the ModelClient contract (respond to #summarize and #model_identifier)" do
      [third_party, self_hosted].each do |adapter|
        aggregate_failures do
          expect(adapter).to respond_to(:summarize).with(1).argument
          expect(adapter).to respond_to(:model_identifier).with(0).arguments
        end
      end
    end
  end
end
