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

describe DiscussionThreadSummarizer::ContentVersionHash do
  # DB-backed: exercises the .active scope and real AR queries.
  let(:course) { course_model }
  let(:user)   { user_model }
  let(:topic)  { course.discussion_topics.create! }

  subject(:call) { described_class.call(topic) }

  # ── Output format ────────────────────────────────────────────────────────

  it "returns a 64-character lowercase hex string (SHA-256 hexdigest format)" do
    expect(call).to match(/\A[0-9a-f]{64}\z/)
  end

  # ── Determinism (core invariant) ─────────────────────────────────────────

  it "returns the same hash for the same topic state on repeated calls (determinism)" do
    topic.discussion_entries.create!(user:, message: "hello")

    first  = described_class.call(topic)
    second = described_class.call(topic)

    expect(first).to eq(second)
  end

  # ── Empty topic ───────────────────────────────────────────────────────────

  it "returns a deterministic non-nil hash for a topic with no active entries" do
    result = described_class.call(topic)

    expect(result).not_to be_nil
    expect(result).to match(/\A[0-9a-f]{64}\z/)
    expect(result).to eq(described_class.call(topic))
  end

  # ── Two different topics ──────────────────────────────────────────────────

  it "returns different hashes for two topics with different entries" do
    topic_a = course.discussion_topics.create!
    topic_b = course.discussion_topics.create!
    topic_a.discussion_entries.create!(user:, message: "unique content A")
    topic_b.discussion_entries.create!(user:, message: "unique content B")

    expect(described_class.call(topic_a)).not_to eq(described_class.call(topic_b))
  end

  # ── New entry added ───────────────────────────────────────────────────────

  it "changes hash when a new entry is added to the topic" do
    before_add = described_class.call(topic)
    topic.discussion_entries.create!(user:, message: "new reply")
    after_add  = described_class.call(topic)

    expect(before_add).not_to eq(after_add)
  end

  # ── Soft-delete ───────────────────────────────────────────────────────────

  it "changes hash when an entry is soft-deleted (excluded from .active scope)" do
    entry = topic.discussion_entries.create!(user:, message: "will be deleted")
    hash_before = described_class.call(topic)

    entry.update!(workflow_state: "deleted")
    hash_after  = described_class.call(topic)

    expect(hash_before).not_to eq(hash_after)
  end

  it "produces the same hash as an empty topic after soft-deleting the only entry" do
    empty_hash = described_class.call(topic)

    entry = topic.discussion_entries.create!(user:, message: "goes away")
    entry.update!(workflow_state: "deleted")

    expect(described_class.call(topic)).to eq(empty_hash)
  end

  # ── Message edit ─────────────────────────────────────────────────────────

  it "changes hash when an entry's message body is edited (content is part of the hash)" do
    entry = topic.discussion_entries.create!(user:, message: "original text")
    hash_before = described_class.call(topic)

    entry.update_column(:message, "edited text")
    hash_after  = described_class.call(topic)

    expect(hash_before).not_to eq(hash_after)
  end

  # ── nil guard ─────────────────────────────────────────────────────────────

  it "raises ArgumentError when discussion_topic is nil" do
    expect { described_class.call(nil) }.to raise_error(ArgumentError, /discussion_topic must not be nil/)
  end
end
