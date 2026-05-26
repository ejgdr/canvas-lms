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

module DiscussionThreadSummarizer
  # Raised when the model's response fails schema validation. Declared at the
  # namespace level (alongside TransportError) so callers can rescue
  # DiscussionThreadSummarizer::SchemaViolationError without knowing the
  # validator class. Mirrors the TransportError precedent from Cycle 6.
  SchemaViolationError = Class.new(StandardError)

  # Pure raise-on-invalid schema guard for model output hashes.
  # Mirrors the guard-before-persist pattern in DiscussionTopicInsight#validate_llm_response
  # (app/models/discussion_topic_insight.rb:167).
  #
  # .call(result) raises SchemaViolationError or returns nil (silent pass).
  # No transformation, coercion, or normalization — only structural checks.
  #
  # Metric emission on rejection lives in SummarizationService#summarize (the
  # boundary where the account is already in scope), not here.
  class OutputSchemaValidator
    MAX_ARRAY_LENGTH    = 20
    MAX_STRING_LENGTH   = 500
    MAX_SCOPE_MODE_LENGTH = 50

    ARRAY_KEYS = %i[themes viewpoints open_questions].freeze

    def self.call(result)
      new.call(result)
    end

    def call(result)
      validate_hash_type(result)
      validate_array_keys(result)
      validate_scope_mode(result)
      nil
    end

    private

    def validate_hash_type(result)
      return if result.is_a?(Hash)

      raise SchemaViolationError, "response must be a Hash, got #{result.class}"
    end

    def validate_array_keys(result)
      ARRAY_KEYS.each do |key|
        value = result[key]

        raise SchemaViolationError, ":#{key} is required" if value.nil?
        raise SchemaViolationError, ":#{key} must be an Array, got #{value.class}" unless value.is_a?(Array)
        if value.size > MAX_ARRAY_LENGTH
          raise SchemaViolationError, ":#{key} exceeds maximum length of #{MAX_ARRAY_LENGTH} items"
        end

        value.each_with_index do |element, i|
          unless element.is_a?(String)
            raise SchemaViolationError, ":#{key}[#{i}] must be a String, got #{element.class}"
          end
          if element.length > MAX_STRING_LENGTH
            raise SchemaViolationError, ":#{key}[#{i}] exceeds maximum string length of #{MAX_STRING_LENGTH}"
          end
        end
      end
    end

    def validate_scope_mode(result)
      sm = result[:scope_mode]

      raise SchemaViolationError, ":scope_mode is required" if sm.nil?
      raise SchemaViolationError, ":scope_mode must be a String, got #{sm.class}" unless sm.is_a?(String)
      if sm.length > MAX_SCOPE_MODE_LENGTH
        raise SchemaViolationError, ":scope_mode exceeds maximum length of #{MAX_SCOPE_MODE_LENGTH}"
      end
    end
  end
end
