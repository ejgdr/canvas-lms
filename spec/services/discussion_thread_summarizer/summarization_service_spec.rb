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
  let(:root_account)     { instance_double("Account", global_id: 10_000_000_000_001) }
  let(:course)           { instance_double("Course", root_account:) }
  let(:stub_client)      { DiscussionThreadSummarizer::StubModelClient.new }
  let(:service)          { described_class.new(client: stub_client) }
  let(:topic)            { instance_double("DiscussionTopic", id: 42, context: course) }
  let(:viewer)           { instance_double("User", id: 99) }
  let(:entries_relation) { double("AR::Relation") }
  let(:malformed_client) do
    Class.new(DiscussionThreadSummarizer::ModelClient) do
      def summarize(_payload)
        { themes: nil }  # missing required keys + wrong type
      end
    end.new
  end

  let(:transport_client) do
    Class.new(DiscussionThreadSummarizer::ModelClient) do
      def summarize(_payload)
        raise DiscussionThreadSummarizer::TransportError, "connection refused"
      end
    end.new
  end

  # Default gather-chain stubs: default mode, no entries.
  # Keeps the four pre-existing #summarize examples working unchanged.
  before do
    # Force Zeitwerk to autoload OutputSchemaValidator (and SchemaViolationError)
    # before any example evaluates the constant as a raise_error argument.
    DiscussionThreadSummarizer::OutputSchemaValidator
    allow(root_account).to receive(:feature_enabled?)
      .with(:discussion_thread_summarizer_scope_limited)
      .and_return(false)
    allow(topic).to receive(:discussion_entries).and_return(entries_relation)
    allow(entries_relation).to receive(:active).and_return(entries_relation)
    allow(entries_relation).to receive(:order).and_return(entries_relation)
    allow(entries_relation).to receive(:preload).and_return(entries_relation)
    allow(entries_relation).to receive(:to_a).and_return([])
    # Suppress audit log output across all examples; the audit-log context
    # overrides this with a capturing stub to assert on logged content.
    allow(Rails.logger).to receive(:info)
  end

  # ── Async enqueueing via .enqueue_for (Cycle 12) ─────────────────────────

  describe ".enqueue_for" do
    let(:delay_proxy) { instance_double(described_class, fetch_or_create_summary: nil) }

    it "dispatches with HIGH_PRIORITY, singleton scoped to the topic id, and n_strand with region" do
      expected_singleton = "discussion_thread_summarizer:generation_for_topic:42"
      expected_n_strand  = ["discussion_thread_summarizer:generation:#{Shard.current.database_server.region}", 1]

      expect_any_instance_of(described_class).to receive(:delay).with(
        hash_including(
          priority:  Delayed::HIGH_PRIORITY,
          singleton: expected_singleton,
          n_strand:  expected_n_strand
        )
      ).and_return(delay_proxy)

      described_class.enqueue_for(discussion_topic: topic, viewer:)
    end

    it "chains #fetch_or_create_summary on the delay proxy with the correct discussion_topic and viewer kwargs" do
      expect_any_instance_of(described_class).to receive(:delay).and_return(delay_proxy)
      expect(delay_proxy).to receive(:fetch_or_create_summary).with(discussion_topic: topic, viewer:)

      described_class.enqueue_for(discussion_topic: topic, viewer:)
    end

    it "encodes the topic id in the singleton key so the same topic always produces the same key" do
      captured_singleton = nil
      allow_any_instance_of(described_class).to receive(:delay) do |_instance, **opts|
        captured_singleton = opts[:singleton]
        delay_proxy
      end

      described_class.enqueue_for(discussion_topic: topic, viewer:)

      expect(captured_singleton).to eq("discussion_thread_summarizer:generation_for_topic:42")
    end

    it "produces distinct singleton keys for topics with different ids" do
      topic_a = instance_double("DiscussionTopic", id: 42, context: course)
      topic_b = instance_double("DiscussionTopic", id: 99, context: course)
      collected_keys = []

      allow_any_instance_of(described_class).to receive(:delay) do |_instance, **opts|
        collected_keys << opts[:singleton]
        delay_proxy
      end

      described_class.enqueue_for(discussion_topic: topic_a, viewer:)
      described_class.enqueue_for(discussion_topic: topic_b, viewer:)

      expect(collected_keys.uniq.size).to eq(2)
      expect(collected_keys.first).to include("42")
      expect(collected_keys.last).to include("99")
    end
  end

  # ── Pre-existing #summarize contract examples (Cycles 7–8, unchanged) ────

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

  # ── Audit log emission (Cycle 11) ────────────────────────────────────────

  context "audit log emission" do
    let(:logged_payloads) { [] }

    before do
      allow(Rails.logger).to receive(:info) { |msg| logged_payloads << msg }
    end

    def audit_log
      JSON.parse(logged_payloads.last, symbolize_names: true)
    end

    let(:broken_client) do
      Class.new(DiscussionThreadSummarizer::ModelClient) do
        def summarize(_payload)
          raise StandardError, "boom"
        end
      end.new
    end

    it "success path emits one audit record with success: true and all required fields" do
      service.summarize(discussion_topic: topic, viewer:)
      log = audit_log
      expect(log[:success]).to be(true)
      expect(log[:error_category]).to be_nil
      expect(log).to include(
        :thread_id, :scope_mode, :model_identifier,
        :request_byte_size, :latency_ms
      )
      expect(log[:event]).to eq("discussion_thread_summarizer.generation_attempt")
    end

    it "schema violation emits audit record with success: false and 'schema_invalid', then re-raises" do
      svc = described_class.new(client: malformed_client)
      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::SchemaViolationError)
      log = audit_log
      expect(log[:success]).to be(false)
      expect(log[:error_category]).to eq("schema_invalid")
    end

    it "transport error emits audit record with success: false and 'transport_error', then re-raises" do
      svc = described_class.new(client: transport_client)
      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::TransportError)
      log = audit_log
      expect(log[:success]).to be(false)
      expect(log[:error_category]).to eq("transport_error")
    end

    it "unexpected exception emits audit record with success: false and 'unknown', then re-raises" do
      svc = described_class.new(client: broken_client)
      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(StandardError, "boom")
      log = audit_log
      expect(log[:success]).to be(false)
      expect(log[:error_category]).to eq("unknown")
    end

    it "emits exactly one audit log call per generation attempt regardless of outcome" do
      svc = described_class.new(client: malformed_client)
      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::SchemaViolationError)
      expect(logged_payloads.size).to eq(1)
    end

    it "logged record contains no raw entry content or author names (PII guard)" do
      service.summarize(discussion_topic: topic, viewer:)
      raw_log = logged_payloads.last
      expect(raw_log).not_to include("entries")
      expect(raw_log).not_to match(/[Aa]uthor|Alice|Bob/)
    end
  end

  # ── Schema validator wiring (Cycle 10) ───────────────────────────────────

  context "schema validation" do
    it "propagates SchemaViolationError when the client returns malformed output" do
      svc = described_class.new(client: malformed_client)
      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::SchemaViolationError)
    end

    it "emits failure metric with reason 'schema_invalid' before re-raising" do
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_failure)
      svc = described_class.new(client: malformed_client)

      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::SchemaViolationError)

      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_failure).with(
        reason:  "schema_invalid",
        account: root_account
      )
    end
  end

  # ── Gather pipeline (Cycle 9) ─────────────────────────────────────────────

  context "gather pipeline" do
    # Lightweight entry builder: avoids DB while giving gather everything it reads.
    def make_entry(user_id:, name:, message:)
      user = instance_double("User", short_name: name)
      instance_double("DiscussionEntry", user_id:, user:, message:)
    end

    let(:student_entry)  { make_entry(user_id: 1,  name: "Alice",   message: "student post")  }
    let(:student2_entry) { make_entry(user_id: 2,  name: "Bob",     message: "bob post")      }
    let(:teacher_entry)  { make_entry(user_id: 3,  name: "Teacher", message: "teacher post")  }
    let(:viewer_entry)   { make_entry(user_id: 99, name: "Viewer",  message: "viewer post")   }

    before do
      # Default for this context: all three entries, default mode.
      allow(entries_relation).to receive(:to_a)
        .and_return([student_entry, teacher_entry, student2_entry])
    end

    it "default mode includes all entries in the payload" do
      payload = service.send(:gather, topic, viewer)
      expect(payload[:scope_mode]).to eq("default")
      expect(payload[:entries].map { |e| e[:author_name] })
        .to eq(["Alice", "Teacher", "Bob"])
    end

    it "scope-limited mode excludes non-instructor, non-viewer entries" do
      allow(root_account).to receive(:feature_enabled?)
        .with(:discussion_thread_summarizer_scope_limited).and_return(true)
      allow(service).to receive(:instructor_user_ids).and_return(Set[3])

      payload = service.send(:gather, topic, viewer)
      expect(payload[:scope_mode]).to eq("limited")
      # alice (1) and bob (2) are neither instructors nor viewer (99) — excluded
      expect(payload[:entries].map { |e| e[:author_name] }).to eq(["Teacher"])
    end

    it "scope-limited mode includes the viewer's own entries alongside instructor entries" do
      allow(root_account).to receive(:feature_enabled?)
        .with(:discussion_thread_summarizer_scope_limited).and_return(true)
      allow(entries_relation).to receive(:to_a)
        .and_return([student_entry, teacher_entry, viewer_entry])
      allow(service).to receive(:instructor_user_ids).and_return(Set[3])

      payload = service.send(:gather, topic, viewer)
      names = payload[:entries].map { |e| e[:author_name] }
      expect(names).to contain_exactly("Teacher", "Viewer")
      expect(names).not_to include("Alice")
    end

    it "viewer who is also an instructor appears once, not duplicated" do
      # viewer.id (3) overlaps with instructor set — union prevents duplication
      viewer_as_instructor = instance_double("User", id: 3)
      allow(root_account).to receive(:feature_enabled?)
        .with(:discussion_thread_summarizer_scope_limited).and_return(true)
      allow(entries_relation).to receive(:to_a).and_return([teacher_entry])
      allow(service).to receive(:instructor_user_ids).and_return(Set[3])

      payload = service.send(:gather, topic, viewer_as_instructor)
      expect(payload[:entries].size).to eq(1)
      expect(payload[:entries].first[:author_name]).to eq("Teacher")
    end

    it "scope-limited with no instructor posts produces only viewer's entries" do
      allow(root_account).to receive(:feature_enabled?)
        .with(:discussion_thread_summarizer_scope_limited).and_return(true)
      allow(entries_relation).to receive(:to_a)
        .and_return([student_entry, student2_entry, viewer_entry])
      allow(service).to receive(:instructor_user_ids).and_return(Set.new)

      payload = service.send(:gather, topic, viewer)
      expect(payload[:entries].map { |e| e[:author_name] }).to eq(["Viewer"])
    end

    it "ordering is applied before filtering: order(:created_at) is called on the relation" do
      expect(entries_relation).to receive(:order).with(:created_at).and_return(entries_relation)
      service.send(:gather, topic, viewer)
    end
  end

  # ── Cross-cutting pipeline seams (Cycle 13) ──────────────────────────────
  # These examples exercise the seams where gather / pseudonymize / validate /
  # audit-log / metric-emit interact within a single summarize call.
  # Individual unit behaviour is already covered by the contexts above.

  context "cross-cutting pipeline seams" do
    # Lightweight entry builder matching the shape gather() produces.
    def make_entry(user_id:, name:, message:)
      user = instance_double("User", short_name: name)
      instance_double("DiscussionEntry", user_id:, user:, message:)
    end

    let(:student_entry)  { make_entry(user_id: 1,  name: "Alice",   message: "student post")  }
    let(:teacher_entry)  { make_entry(user_id: 3,  name: "Teacher", message: "teacher post")  }
    let(:viewer_entry)   { make_entry(user_id: 99, name: "Viewer",  message: "viewer post")   }

    # A client that captures its payload and returns a valid shape.
    let(:capturing_client) do
      Class.new(DiscussionThreadSummarizer::ModelClient) do
        attr_reader :received_payloads

        def initialize
          @received_payloads = []
        end

        def summarize(payload)
          @received_payloads << payload
          { themes: ["t"], viewpoints: [], open_questions: [], scope_mode: payload[:scope_mode] }
        end
      end.new
    end

    let(:logged_payloads) { [] }

    before do
      allow(Rails.logger).to receive(:info) { |msg| logged_payloads << msg }
    end

    def last_audit_log
      JSON.parse(logged_payloads.last, symbolize_names: true)
    end

    it "scope-limited: filter → pseudonymize → validate all fire; client sees only teacher+viewer with pseudonyms" do
      allow(root_account).to receive(:feature_enabled?)
        .with(:discussion_thread_summarizer_scope_limited).and_return(true)
      allow(entries_relation).to receive(:to_a)
        .and_return([student_entry, teacher_entry, viewer_entry])
      allow(topic).to receive(:discussion_entries).and_return(entries_relation)
      # Stub instructor_user_ids on the service instance that will be created.
      svc = described_class.new(client: capturing_client)
      allow(svc).to receive(:instructor_user_ids).and_return(Set[3])

      svc.summarize(discussion_topic: topic, viewer:)

      payload = capturing_client.received_payloads.last
      names   = payload[:entries].map { |e| e[:author_name] }

      # Scope filter: Alice (user_id 1) excluded; teacher + viewer included.
      expect(names.size).to eq(2)
      # Pseudonymize: no real names reach the client.
      expect(names).not_to include("Alice", "Teacher", "Viewer")
      expect(names).to all(match(/\AAuthor [A-Z]+\z/))
      # Audit log fires with success.
      expect(last_audit_log[:success]).to be(true)
      expect(last_audit_log[:scope_mode]).to eq("limited")
    end

    it "scope-limited + malformed client: Metrics.increment_failure and audit log both fire in the same call" do
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_failure)
      allow(root_account).to receive(:feature_enabled?)
        .with(:discussion_thread_summarizer_scope_limited).and_return(true)
      allow(entries_relation).to receive(:to_a)
        .and_return([student_entry, teacher_entry, viewer_entry])
      svc = described_class.new(client: malformed_client)
      allow(svc).to receive(:instructor_user_ids).and_return(Set[3])

      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::SchemaViolationError)

      expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_failure)
        .with(reason: "schema_invalid", account: root_account)
      expect(last_audit_log[:success]).to be(false)
      expect(last_audit_log[:error_category]).to eq("schema_invalid")
    end

    it "transport error: Metrics.increment_failure is NOT emitted (only schema violations trigger it)" do
      allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_failure)
      svc = described_class.new(client: transport_client)

      expect { svc.summarize(discussion_topic: topic, viewer:) }
        .to raise_error(DiscussionThreadSummarizer::TransportError)

      expect(DiscussionThreadSummarizer::Metrics).not_to have_received(:increment_failure)
    end

    it "idempotence: repeated summarize calls with identical inputs send identical payloads to the client" do
      allow(entries_relation).to receive(:to_a)
        .and_return([student_entry, teacher_entry])
      svc = described_class.new(client: capturing_client)

      svc.summarize(discussion_topic: topic, viewer:)
      svc.summarize(discussion_topic: topic, viewer:)

      expect(capturing_client.received_payloads.size).to eq(2)
      expect(capturing_client.received_payloads.first)
        .to eq(capturing_client.received_payloads.last)
    end
  end

end

# DB-backed cache tests (Cycle 16, #16) — separate describe to avoid instance_double stubs.
describe "DiscussionThreadSummarizer::SummarizationService#fetch_or_create_summary" do
  let(:course)         { course_model }
  let(:user)           { user_model }
  let(:topic)          { course.discussion_topics.create! }
  let(:viewer)         { user }
  let(:locale)         { "en" }
  let(:stub_client)    { DiscussionThreadSummarizer::StubModelClient.new }
  let(:service)        { DiscussionThreadSummarizer::SummarizationService.new(client: stub_client) }
  let(:content_hash)   { DiscussionThreadSummarizer::ContentVersionHash.call(topic) }

  before do
    topic.discussion_entries.create!(user:, message: "hello")
    allow(Rails.logger).to receive(:info)
  end

  def seed_summary(locale: "en", hash: content_hash, summary_json: nil)
    topic.summaries.create!(
      user:,
      locale:,
      summary: summary_json || DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE.to_json,
      dynamic_content_hash: hash,
      llm_config_version: DiscussionThreadSummarizer::SummarizationService::LLM_CONFIG_VERSION
    )
  end

  it "returns :hit without calling the model client when a matching row exists" do
    seed_summary
    allow(stub_client).to receive(:summarize).and_call_original

    result = service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

    expect(result.status).to eq(:hit)
    expect(stub_client).not_to have_received(:summarize)
  end

  it "returns :miss, calls the client once, and creates one DiscussionTopicSummary" do
    allow(stub_client).to receive(:summarize).and_call_original

    expect do
      result = service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)
      expect(result.status).to eq(:miss)
    end.to change { topic.summaries.count }.by(1)

    expect(stub_client).to have_received(:summarize).once
  end

  it "miss-then-hit calls the model client only once" do
    allow(stub_client).to receive(:summarize).and_call_original

    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)
    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

    expect(stub_client).to have_received(:summarize).once
  end

  it "isolates cache rows per discussion topic" do
    topic_b = course.discussion_topics.create!
    topic_b.discussion_entries.create!(user:, message: "other thread")
    allow(stub_client).to receive(:summarize).and_call_original

    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)
    service.fetch_or_create_summary(discussion_topic: topic_b, viewer:, locale:)

    expect(topic.summaries.count).to eq(1)
    expect(topic_b.summaries.count).to eq(1)
    expect(stub_client).to have_received(:summarize).twice
  end

  it "stores separate rows per locale for the same topic content" do
    seed_summary(locale: "en")
    allow(stub_client).to receive(:summarize).and_call_original

    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale: "es")

    expect(topic.summaries.pluck(:locale)).to contain_exactly("en", "es")
    expect(stub_client).to have_received(:summarize).once
  end

  it "persists dynamic_content_hash equal to ContentVersionHash.call(topic)" do
    allow(stub_client).to receive(:summarize).and_call_original

    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

    expect(topic.summaries.last.dynamic_content_hash).to eq(content_hash)
  end

  it "returns identical :result on miss-then-hit (parsed DB JSON matches pipeline output)" do
    allow(stub_client).to receive(:summarize).and_call_original

    miss = service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)
    hit  = service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

    expect(hit.result).to eq(miss.result)
    expect(hit.result).to eq(DiscussionThreadSummarizer::StubModelClient::FIXED_RESPONSE)
  end

  it "emits cache.hit when serving a cached summary" do
    seed_summary
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_cache_hit)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_cache_miss)

    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

    expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_cache_hit)
      .with(account: course.root_account)
    expect(DiscussionThreadSummarizer::Metrics).not_to have_received(:increment_cache_miss)
  end

  it "emits cache.miss when no cached summary exists" do
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_cache_miss)
    allow(DiscussionThreadSummarizer::Metrics).to receive(:increment_cache_hit)
    allow(stub_client).to receive(:summarize).and_call_original

    service.fetch_or_create_summary(discussion_topic: topic, viewer:, locale:)

    expect(DiscussionThreadSummarizer::Metrics).to have_received(:increment_cache_miss)
      .with(account: course.root_account)
    expect(DiscussionThreadSummarizer::Metrics).not_to have_received(:increment_cache_hit)
  end
end
