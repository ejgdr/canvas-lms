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

describe DiscussionThreadSummarizer::OutputSchemaValidator do
  subject(:validator) { described_class }

  let(:valid_response) do
    {
      themes:         ["Theme A", "Theme B"],
      viewpoints:     ["Viewpoint 1"],
      open_questions: ["Q1?"],
      scope_mode:     "default"
    }
  end

  # ── Happy path ────────────────────────────────────────────────────────────

  it "returns nil and does not raise for a valid four-key response" do
    expect { validator.call(valid_response) }.not_to raise_error
    expect(validator.call(valid_response)).to be_nil
  end

  it "passes StubModelClient::FIXED_RESPONSE unchanged (regression guard)" do
    expect do
      validator.call(DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE)
    end.not_to raise_error
  end

  # ── Missing required keys ─────────────────────────────────────────────────

  it "raises SchemaViolationError when :themes is missing" do
    expect { validator.call(valid_response.except(:themes)) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:themes/)
  end

  it "raises SchemaViolationError when :viewpoints is missing" do
    expect { validator.call(valid_response.except(:viewpoints)) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:viewpoints/)
  end

  it "raises SchemaViolationError when :open_questions is missing" do
    expect { validator.call(valid_response.except(:open_questions)) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:open_questions/)
  end

  it "raises SchemaViolationError when :scope_mode is missing" do
    expect { validator.call(valid_response.except(:scope_mode)) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:scope_mode/)
  end

  # ── Type mismatches ───────────────────────────────────────────────────────

  it "raises SchemaViolationError when :themes is a String instead of Array" do
    expect { validator.call(valid_response.merge(themes: "not an array")) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:themes must be an Array/)
  end

  it "raises SchemaViolationError when :scope_mode is an Array instead of String" do
    expect { validator.call(valid_response.merge(scope_mode: ["oops"])) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:scope_mode must be a String/)
  end

  # ── Nested element type ───────────────────────────────────────────────────

  it "raises SchemaViolationError when :themes contains a non-String element" do
    expect { validator.call(valid_response.merge(themes: [1, 2, 3])) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /:themes\[0\] must be a String/)
  end

  # ── Size limits ───────────────────────────────────────────────────────────

  it "raises SchemaViolationError when :themes array exceeds MAX_ARRAY_LENGTH" do
    oversized = Array.new(described_class::MAX_ARRAY_LENGTH + 1, "item")
    expect { validator.call(valid_response.merge(themes: oversized)) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /exceeds maximum length/)
  end

  it "raises SchemaViolationError when a :themes element exceeds MAX_STRING_LENGTH" do
    long_string = "x" * (described_class::MAX_STRING_LENGTH + 1)
    expect { validator.call(valid_response.merge(themes: [long_string])) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /exceeds maximum string length/)
  end

  it "raises SchemaViolationError when :scope_mode exceeds MAX_SCOPE_MODE_LENGTH" do
    long_scope = "s" * (described_class::MAX_SCOPE_MODE_LENGTH + 1)
    expect { validator.call(valid_response.merge(scope_mode: long_scope)) }
      .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /exceeds maximum length/)
  end

  # ── Top-level type guard ──────────────────────────────────────────────────

  it "raises SchemaViolationError when result is not a Hash" do
    [nil, [], "string", 42].each do |bad_value|
      expect { validator.call(bad_value) }
        .to raise_error(DiscussionThreadSummarizer::SchemaViolationError, /must be a Hash/),
            "expected SchemaViolationError for #{bad_value.inspect}"
    end
  end
end
