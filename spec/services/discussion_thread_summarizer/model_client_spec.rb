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

describe DiscussionThreadSummarizer::ModelClient do
  describe "#summarize" do
    it "raises NotImplementedError, enforcing the abstract contract" do
      client = described_class.new
      expect { client.summarize({}) }.to raise_error(NotImplementedError, /ModelClient#summarize must be implemented/)
    end
  end
end

describe DiscussionThreadSummarizer::StubModelClient do
  let(:client) { described_class.new }

  it "is a ModelClient subclass" do
    expect(client).to be_a(DiscussionThreadSummarizer::ModelClient)
  end

  describe "#summarize" do
    it "returns FIXED_RESPONSE unchanged regardless of payload" do
      result = client.summarize({ topic_id: 999, arbitrary_key: "ignored" })
      expect(result).to eq(DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE)
    end

    it "FIXED_RESPONSE includes the four documented contract keys" do
      response = DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE
      expect(response).to include(
        :themes,
        :viewpoints,
        :open_questions,
        :scope_mode
      )
      expect(response[:themes]).to be_an(Array)
      expect(response[:viewpoints]).to be_an(Array)
      expect(response[:open_questions]).to be_an(Array)
      expect(response[:scope_mode]).to be_a(String)
    end
  end
end
