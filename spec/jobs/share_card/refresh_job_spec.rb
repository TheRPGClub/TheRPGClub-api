# frozen_string_literal: true

require "rails_helper"

# The Share Card refresh (spec #518): a POST to the website's
# /api/revalidate with the shared secret, retried on failure, skipped
# without the secret. Queuing it is covered with the round decisions
# (spec/services/voting).
RSpec.describe ShareCard::RefreshJob do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:env) { { "REVALIDATE_SECRET" => "s3cret", "DISCORD_OAUTH_SUCCESS_REDIRECT" => "https://therpg.club/auth/callback" } }

  around do |example|
    original_connection = Faraday.default_connection
    Faraday.default_connection = Faraday.new { |builder| builder.adapter(:test, stubs) }
    example.run
  ensure
    Faraday.default_connection = original_connection
  end

  before { stub_const("ENV", ENV.to_h.merge(env)) }

  it "POSTs to the website's revalidate route with the bearer secret" do
    requests = []
    stubs.post("https://therpg.club/api/revalidate") do |request|
      requests << request
      [ 200, {}, "" ]
    end

    described_class.perform_now

    expect(requests.size).to eq(1)
    expect(requests.first.request_headers["Authorization"]).to eq("Bearer s3cret")
    stubs.verify_stubbed_calls
  end

  it "retries a non-2xx answer later" do
    stubs.post("https://therpg.club/api/revalidate") { [ 503, {}, "" ] }

    expect { described_class.perform_now }.to have_enqueued_job(described_class)
  end

  it "retries a network error later" do
    stubs.post("https://therpg.club/api/revalidate") { raise Faraday::ConnectionFailed, "refused" }

    expect { described_class.perform_now }.to have_enqueued_job(described_class)
  end

  it "gives up quietly after its last attempt, logging it" do
    stubs.post("https://therpg.club/api/revalidate") { [ 500, {}, "" ] }
    allow(Rails.logger).to receive(:warn)
    job = described_class.new
    job.exception_executions = { "[ShareCard::RefreshJob::RefreshFailed, Faraday::Error]" => 4 }

    expect { job.perform_now }.not_to have_enqueued_job(described_class)
    expect(Rails.logger).to have_received(:warn).with(/share_card.refresh_gave_up/)
  end

  context "without REVALIDATE_SECRET" do
    let(:env) { { "REVALIDATE_SECRET" => "", "DISCORD_OAUTH_SUCCESS_REDIRECT" => "https://therpg.club/auth/callback" } }

    it "does nothing but log" do
      allow(Rails.logger).to receive(:info)

      expect { described_class.perform_now }.not_to have_enqueued_job(described_class)

      expect(Rails.logger).to have_received(:info).with(/share_card.refresh_skipped/)
      stubs.verify_stubbed_calls
    end
  end
end
