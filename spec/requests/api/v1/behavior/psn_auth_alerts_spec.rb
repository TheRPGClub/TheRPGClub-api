# frozen_string_literal: true

require "rails_helper"

# PSN auth alerts (ticket #468): when the club account's PSN login expires the
# API asks the bot to warn staff (psn_auth_expired), reminds them once a day
# from the Sync Window while it stays expired, and says so when a login
# succeeds again (psn_auth_restored). Sony is stubbed with Faraday's test
# adapter; what was queued is read back through the bot's claim.
RSpec.describe "api/v1/psn auth alerts behavior", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:expired_at) { Time.utc(2026, 11, 16, 9, 30) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:http) { Faraday.new { |builder| builder.adapter(:test, stubs) } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:code_redirect) { "com.scee.psxandroid.scecompcall://redirect/?code=v3.AUTHCODE" }
  let(:refused_redirect) { "com.scee.psxandroid.scecompcall://redirect/?error=login_required" }

  # Each example starts as a fresh machine: no signal file, so it reads as up.
  before { FileUtils.rm_f(BotJob::WorkSignal.path) }

  def psn_client = Psn::Client.new(npsso: "test-npsso", http: http, cache: cache)

  # Sony's two auth steps. The authorize step yields a code only while
  # `sony_accepts` is set; without one the NPSSO reads as expired.
  let(:sony) { { accepts: false } }

  before do
    stubs.get(Psn::Client::AUTHORIZE_URL) { [ 302, { "Location" => sony[:accepts] ? code_redirect : refused_redirect }, "" ] }
    stubs.post(Psn::Client::TOKEN_URL) do
      [ 200, { "Content-Type" => "application/json" }, { access_token: "access-1", expires_in: 3599 }.to_json ]
    end
  end

  def sony_accepts = sony[:accepts] = true

  def expire_login_at(time)
    travel_to(time) do
      expect { psn_client.authenticate! }.to raise_error(Achievements::Providers::AuthExpired)
    end
  end

  # The bot's poll: the PSN alert jobs queued since the last one.
  def claim_psn_alerts
    post "/api/v1/bot_jobs/claim", headers: service_headers
    expect(response).to have_http_status(:ok)
    json.fetch("data").select { |job| job["kind"].start_with?("psn_auth_") }
  end

  def run_sync_window_at(time)
    travel_to(time) { Achievements::SyncWindowJob.perform_now }
  end

  describe "the expiry alert" do
    it "queues one psn_auth_expired job, with no Feature key, when the login first expires" do
      expire_login_at(expired_at)

      job = claim_psn_alerts.sole
      expect(job.fetch("kind")).to eq("psn_auth_expired")
      expect(job.fetch("payload")).to eq("expired_at" => expired_at.iso8601, "reminder" => false)
    end

    it "queues nothing more while the login keeps failing" do
      expire_login_at(expired_at)
      claim_psn_alerts

      expire_login_at(expired_at + 1.hour)

      expect(claim_psn_alerts).to be_empty
    end
  end

  describe "the restore alert" do
    it "queues psn_auth_restored with both times once a login succeeds again" do
      expire_login_at(expired_at)
      claim_psn_alerts
      sony_accepts
      restored_at = expired_at + 2.days

      travel_to(restored_at) { psn_client.authenticate! }

      job = claim_psn_alerts.sole
      expect(job.fetch("kind")).to eq("psn_auth_restored")
      expect(job.fetch("payload")).to eq("expired_at" => expired_at.iso8601, "restored_at" => restored_at.iso8601)
    end

    it "queues nothing for a login while nothing had expired" do
      sony_accepts

      psn_client.authenticate!

      expect(claim_psn_alerts).to be_empty
    end
  end

  describe "the daily reminder" do
    let(:psn) { instance_double(Psn::Client) }

    before do
      AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, expired_at.iso8601)
      allow(Achievements::Providers).to receive(:client_for).with("psn").and_return(psn)
      allow(psn).to receive(:authenticate!).and_raise(Achievements::Providers::AuthExpired, "NPSSO expired")
    end

    def window(day, hour) = Time.utc(2026, 11, day, hour, 0, 3)

    it "is not sent by a window less than 24 hours after the expiry" do
      run_sync_window_at(window(17, 6))

      expect(claim_psn_alerts).to be_empty
    end

    it "is sent by the first window at least 24 hours after the expiry, then once per 24 hours" do
      run_sync_window_at(window(17, 12))
      first = claim_psn_alerts.sole
      expect(first.fetch("kind")).to eq("psn_auth_expired")
      expect(first.fetch("payload")).to eq("expired_at" => expired_at.iso8601, "reminder" => true)

      [ window(17, 18), window(18, 0), window(18, 6) ].each { |time| run_sync_window_at(time) }
      expect(claim_psn_alerts).to be_empty

      run_sync_window_at(window(18, 12))
      expect(claim_psn_alerts.sole.dig("payload", "reminder")).to be(true)
    end

    it "is sent while the Achievement Hub is Off too, since the login still needs fixing" do
      set_feature_flag("achievement_hub", "off")

      run_sync_window_at(window(17, 12))

      expect(claim_psn_alerts.sole.dig("payload", "reminder")).to be(true)
    end

    it "is not sent once the window's own login clears the flag" do
      allow(psn).to receive(:authenticate!) { AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, nil) }

      run_sync_window_at(window(17, 12))

      expect(claim_psn_alerts).to be_empty
    end

    it "counts a reminder sent for an earlier expiry as none for a new one" do
      AchievementHubState.set(Achievements::PsnAuthAlerts::REMINDED_KEY, (expired_at - 1.hour).iso8601)

      run_sync_window_at(window(17, 12))

      expect(claim_psn_alerts.sole.dig("payload", "reminder")).to be(true)
    end
  end
end
