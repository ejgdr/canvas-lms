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

describe DiscussionThreadSummarizer::Pseudonymizer do
  # Three-author fixture reused across happy-path examples.
  let(:entries) do
    [
      { author_name: "Alice", body: "post one"   },
      { author_name: "Bob",   body: "post two"   },
      { author_name: "Carol", body: "post three" },
      { author_name: "Alice", body: "post four"  },
    ]
  end

  subject(:result) { described_class.call(entries) }

  # ── Happy-path contract ──────────────────────────────────────────────────

  it "replaces all real author names with pseudonyms in the returned entries" do
    names = result.pseudonymized_entries.map { |e| e[:author_name] }
    expect(names).not_to include("Alice", "Bob", "Carol")
    expect(names).to all(match(/\AAuthor [A-Z]\z/))
  end

  it "assigns the same label to the same author within a single call (stability)" do
    alice_labels = result.pseudonymized_entries
                         .select { |e| e[:body].include?("Alice") rescue false }

    # locate entries that were originally Alice's by body content
    original_alice_bodies = ["post one", "post four"]
    alice_entries = result.pseudonymized_entries.select { |e| original_alice_bodies.include?(e[:body]) }
    expect(alice_entries.map { |e| e[:author_name] }.uniq.size).to eq(1)
  end

  it "assigns distinct labels to distinct authors (no collisions)" do
    labels = result.pseudonymized_entries.map { |e| e[:author_name] }.uniq
    expect(labels.size).to eq(3)
  end

  it "preserves :body text unchanged" do
    original_bodies = entries.map { |e| e[:body] }
    returned_bodies = result.pseudonymized_entries.map { |e| e[:body] }
    expect(returned_bodies).to eq(original_bodies)
  end

  it "returns an author_map pairing each real name to its label" do
    expect(result.author_map["Alice"]).to match(/\AAuthor [A-Z]\z/)
    expect(result.author_map["Bob"]).to match(/\AAuthor [A-Z]\z/)
    expect(result.author_map["Carol"]).to match(/\AAuthor [A-Z]\z/)
    expect(result.author_map["Alice"]).not_to eq(result.author_map["Bob"])
  end

  # ── Edge cases ───────────────────────────────────────────────────────────

  it "returns empty pseudonymized_entries and empty author_map for an empty input" do
    r = described_class.call([])
    expect(r.pseudonymized_entries).to eq([])
    expect(r.author_map).to eq({})
  end

  it "produces exactly one author_map entry when a single author is repeated" do
    repeated = [
      { author_name: "Alice", body: "a" },
      { author_name: "Alice", body: "b" },
      { author_name: "Alice", body: "c" },
    ]
    r = described_class.call(repeated)
    expect(r.author_map.size).to eq(1)
    expect(r.pseudonymized_entries.map { |e| e[:author_name] }.uniq).to eq(["Author A"])
  end

  # ── Label contract ───────────────────────────────────────────────────────

  it "assigns labels in first-seen order (first author gets A, second gets B, …)" do
    # Alice appears first → Author A; Bob second → Author B; Carol third → Author C
    expect(result.author_map["Alice"]).to eq("Author A")
    expect(result.author_map["Bob"]).to  eq("Author B")
    expect(result.author_map["Carol"]).to eq("Author C")
  end

  it "uses the exact format 'Author X' (capital A, space, uppercase letter)" do
    result.author_map.each_value do |label|
      expect(label).to match(/\AAuthor [A-Z]\z/),
                       "expected label to be 'Author X' format, got: #{label.inspect}"
    end
  end

  # ── Immutability ─────────────────────────────────────────────────────────

  it "does not mutate the original entry hashes" do
    originals = entries.map(&:dup)
    described_class.call(entries)
    expect(entries).to eq(originals)
  end
end
