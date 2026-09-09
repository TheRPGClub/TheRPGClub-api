# frozen_string_literal: true

require "rails_helper"

# ApplicationController maps database *reachability* failures to 503 so callers
# can retry, while genuine faults -- including a slow-but-alive database -- stay
# 500. That split is load-bearing for the Discord bot, which retries no-response
# and 502/503/504 but not 500: as a 500, a Neon cold start surfaced as a hard
# failure on the first command after any idle period instead of a retried,
# invisible one.
#
# /api/v1/health is the probe because it queries the database directly and skips
# authentication, leaving the rescue path as the only thing under test.
RSpec.describe "database availability behavior", type: :request do
  # Under transactional fixtures the connection is leased for the whole example,
  # so stubbing the one query the health check runs raises from inside the action
  # without disturbing the surrounding test transaction.
  def stub_health_query_to_raise(error)
    allow(ActiveRecord::Base.connection).to receive(:select_value).and_raise(error)
  end

  describe "when the database is unreachable" do
    it "renders 503 when a connection cannot be established" do
      stub_health_query_to_raise(ActiveRecord::ConnectionNotEstablished.new("connection to server failed"))

      get "/api/v1/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(json.fetch("error")).to eq("service_unavailable")
    end

    it "advertises Retry-After so callers know to come back" do
      stub_health_query_to_raise(ActiveRecord::ConnectionNotEstablished.new("connection to server failed"))

      get "/api/v1/health"

      expect(response.headers["Retry-After"]).to eq("1")
    end

    it "renders 503 when an established connection drops mid-query" do
      stub_health_query_to_raise(ActiveRecord::ConnectionFailed.new("server closed the connection unexpectedly"))

      get "/api/v1/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(json.fetch("error")).to eq("service_unavailable")
    end
  end

  describe "when the database is slow but alive" do
    # Deliberately NOT 503: a statement_timeout cancellation means the database
    # is overloaded, and that is exactly when retries pile on more load.
    it "leaves a cancelled statement as a non-retryable 500" do
      stub_health_query_to_raise(ActiveRecord::QueryCanceled.new("canceling statement due to statement timeout"))

      get "/api/v1/health"

      expect(response).to have_http_status(:internal_server_error)
      expect(json.fetch("error")).to eq("internal_server_error")
    end
  end
end
