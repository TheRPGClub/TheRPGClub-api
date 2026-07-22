# frozen_string_literal: true

require "rails_helper"

RSpec.describe Igdb::Client do
  subject(:client) { described_class.new }

  around do |example|
    keys = %w[IGDB_CLIENT_ID IGDB_CLIENT_SECRET]
    original_values = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["IGDB_CLIENT_ID"] = "test-client-id"
    ENV["IGDB_CLIENT_SECRET"] = "test-client-secret"

    example.run
  ensure
    original_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  describe "network failures" do
    it "wraps Faraday failures while fetching an access token" do
      allow(Faraday).to receive(:post).with(described_class::TOKEN_URL)
        .and_raise(Faraday::ConnectionFailed, "connection refused")

      expect { client.send(:access_token) }
        .to raise_error(described_class::RequestError, "IGDB token request failed: connection refused")
    end

    it "wraps Faraday failures while making an IGDB request" do
      token_response = instance_double(
        Faraday::Response,
        body: '{"access_token":"token","expires_in":3600}',
        success?: true
      )
      allow(Faraday).to receive(:post).with(described_class::TOKEN_URL).and_return(token_response)
      allow(Faraday).to receive(:post).with("#{described_class::API_BASE_URL}/games")
        .and_raise(Faraday::TimeoutError, "execution expired")

      expect { client.search("Chrono Trigger") }
        .to raise_error(described_class::RequestError, "IGDB games request failed: execution expired")
    end
  end
end
