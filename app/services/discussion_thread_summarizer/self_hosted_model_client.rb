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

require "net/http"
require "json"
require "uri"

module DiscussionThreadSummarizer
  # ModelClient implementation that routes summarization requests to an
  # institution-operated HTTP endpoint configured via SUMMARIZER_ENDPOINT_URL.
  #
  # Uses Net::HTTP directly (not CanvasHttp) because operator-configured
  # endpoints are trusted infrastructure — CanvasHttp's SSRF guards are
  # designed for user-supplied URLs, not operator deployment config.
  #
  # Required env vars:
  #   SUMMARIZER_ENDPOINT_URL   — full URL, e.g. https://llm.example.edu/summarize
  # Optional:
  #   SUMMARIZER_ENDPOINT_TOKEN — bearer token; omit if your endpoint uses
  #                                network-level authentication instead
  class SelfHostedModelClient < ModelClient
    OPEN_TIMEOUT = 5   # seconds — connection establishment
    READ_TIMEOUT = 30  # seconds — response body read

    def summarize(payload)
      url   = endpoint_url!
      token = ENV["SUMMARIZER_ENDPOINT_TOKEN"]
      uri   = URI.parse(url)

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request                   = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"]   = "application/json"
      request["Authorization"]  = "Bearer #{token}" if token.present?
      request.body              = payload.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise TransportError, "self-hosted endpoint returned HTTP #{response.code}"
      end

      JSON.parse(response.body, symbolize_names: true)
    rescue JSON::ParserError => e
      raise TransportError, "self-hosted endpoint returned invalid JSON: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TransportError, "self-hosted endpoint timed out: #{e.message}"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise TransportError, "self-hosted endpoint unreachable: #{e.message}"
    end

    # Returns "self-hosted:<host><path>" — the endpoint's host and path without
    # scheme, credentials, or query string so audit logs never capture secrets.
    def model_identifier
      url = ENV.fetch("SUMMARIZER_ENDPOINT_URL", "")
      return "self-hosted:unknown" if url.blank?

      uri  = URI.parse(url)
      host = uri.host || "unknown"
      "self-hosted:#{host}#{uri.path}"
    rescue URI::InvalidURIError
      "self-hosted:unknown"
    end

    private

    def endpoint_url!
      url = ENV["SUMMARIZER_ENDPOINT_URL"]
      raise TransportError, "SUMMARIZER_ENDPOINT_URL is not configured" if url.blank?

      url
    end
  end
end
