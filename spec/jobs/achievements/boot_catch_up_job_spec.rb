# frozen_string_literal: true

require "rails_helper"

# The boot catch-up (ADR 0003, ticket #468): restarts the Provider ticks a
# deploy interrupted and, while the PSN pause is on, first tries one PSN login,
# so a fresh NPSSO set with the deploy ends the pause on its own.
RSpec.describe Achievements::BootCatchUpJob do
  include ActiveJob::TestHelper

  let(:psn) { instance_double(Psn::Client) }

  before do
    allow(Achievements::Providers).to receive(:client_for).with("psn").and_return(psn)
    allow(Psn::Client).to receive(:npsso_configured?).and_return(true)
  end

  def expire_psn = AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, 2.days.ago.iso8601)

  def expect_all_ticks
    UserLinkedAccount::PROVIDERS.each do |provider|
      expect(Achievements::ProviderTickJob).to have_been_enqueued.with(provider).exactly(:once)
    end
  end

  it "enqueues the three Provider ticks and makes no PSN login while PSN auth is fine" do
    allow(psn).to receive(:authenticate!)

    described_class.perform_now

    expect(psn).not_to have_received(:authenticate!)
    expect_all_ticks
  end

  it "logs in to PSN before enqueueing the ticks while the pause is on, so the PSN chain resumes" do
    expire_psn
    allow(psn).to receive(:authenticate!) do
      expect(Achievements::ProviderTickJob).not_to have_been_enqueued
      AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, nil)
    end

    described_class.perform_now

    expect(psn).to have_received(:authenticate!).once
    expect(Achievements::ProviderTickJob.paused?("psn")).to be(false)
    expect_all_ticks
  end

  it "still enqueues the ticks when the PSN login fails, whatever the error" do
    expire_psn
    allow(psn).to receive(:authenticate!).and_raise(Faraday::ConnectionFailed, "down")

    expect { described_class.perform_now }.not_to raise_error

    expect(Achievements::ProviderTickJob.paused?("psn")).to be(true)
    expect_all_ticks
  end

  it "makes no PSN login when no NPSSO is configured" do
    expire_psn
    allow(Psn::Client).to receive(:npsso_configured?).and_return(false)
    allow(psn).to receive(:authenticate!)

    described_class.perform_now

    expect(psn).not_to have_received(:authenticate!)
    expect_all_ticks
  end

  it "makes no PSN login while the Achievement Hub is Off" do
    expire_psn
    set_feature_flag("achievement_hub", "off")
    allow(psn).to receive(:authenticate!)

    described_class.perform_now

    expect(psn).not_to have_received(:authenticate!)
  end
end
