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

describe DiscussionThreadSummarizer::ModelClientFactory do
  describe ".build" do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    context "when SUMMARIZER_ENDPOINT_URL is set and non-blank" do
      before do
        allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL")
                                  .and_return("http://llm.example.internal/summarize")
      end

      it "returns a SelfHostedModelClient" do
        expect(described_class.build).to be_a(DiscussionThreadSummarizer::SelfHostedModelClient)
      end
    end

    context "when SUMMARIZER_ENDPOINT_URL is nil" do
      before { allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return(nil) }

      it "returns a StubModelClient" do
        expect(described_class.build).to be_a(DiscussionThreadSummarizer::StubModelClient)
      end
    end

    context "when SUMMARIZER_ENDPOINT_URL is an empty string" do
      before { allow(ENV).to receive(:[]).with("SUMMARIZER_ENDPOINT_URL").and_return("") }

      it "returns a StubModelClient" do
        expect(described_class.build).to be_a(DiscussionThreadSummarizer::StubModelClient)
      end
    end
  end
end
