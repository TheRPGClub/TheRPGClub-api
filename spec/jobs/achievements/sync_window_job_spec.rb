# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::SyncWindowJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 11, 1, 12) }

  around { |example| travel_to(now) { example.run } }

  def account(provider: "steam", **attributes)
    create(:user_linked_account, provider: provider, sync_status: "ok", sync_mode: "incremental",
      backfilled_at: now - 2.days, last_synced_at: now - 6.hours, **attributes)
  end

  def marked?(linked_account)
    linked_account.reload.sync_due_at == now && linked_account.incremental?
  end

  it "marks every backfilled account that is ok, pending or errored as due for an incremental sync" do
    ok = account
    pending = account(provider: "retroachievements", sync_status: "pending", sync_mode: "backfill")
    errored = account(provider: "psn", sync_status: "error", sync_error: "HTTP 500")

    described_class.perform_now

    expect([ ok, pending, errored ].map { |linked| marked?(linked) }).to all(be(true))
  end

  it "resumes a Backfill whose listing failed (error, never backfilled), keeping it a Backfill" do
    errored = account(sync_status: "error", sync_error: "HTTP 500", sync_mode: "backfill", backfilled_at: nil,
      last_synced_at: nil)

    described_class.perform_now

    expect(errored.reload).to have_attributes(sync_due_at: now, sync_mode: "backfill")
  end

  it "skips accounts waiting for Retry, never backfilled, already due or of departed members" do
    skipped = [
      account(sync_status: "private"),
      account(sync_status: "not_found"),
      account(sync_status: "pending", sync_mode: "backfill", backfilled_at: nil, sync_due_at: now - 1.hour),
      account(sync_due_at: now - 1.hour),
      account(user: create(:user, server_left_at: now - 1.day)),
      account(user: create(:user, is_bot: true))
    ]
    before = skipped.map { |linked| linked.reload.attributes }

    described_class.perform_now

    expect(skipped.map { |linked| linked.reload.attributes }).to eq(before)
  end

  it "enqueues the three Provider ticks" do
    described_class.perform_now

    UserLinkedAccount::PROVIDERS.each do |provider|
      expect(Achievements::ProviderTickJob).to have_been_enqueued.with(provider).exactly(:once)
    end
  end

  describe "while the Achievement Hub is Off" do
    before { set_feature_flag("achievement_hub", "off") }

    it "marks the accounts due but starts no Provider tick" do
      linked = account

      described_class.perform_now

      expect(marked?(linked)).to be(true)
      expect(Achievements::ProviderTickJob).not_to have_been_enqueued
    end

    it "leaves the window's work due for the restart once the Achievement Hub is back on" do
      linked = account
      described_class.perform_now

      Features::ChangeFlag.call("achievement_hub", "live", by: create(:user, role_admin: true).user_id)

      expect(marked?(linked)).to be(true)
      expect(Achievements::ProviderTickJob).to have_been_enqueued.with("steam")
    end

    it "makes no PSN auth attempt while PSN auth has expired, and marks no PSN account" do
      AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, (now - 1.day).iso8601)
      allow(Achievements::Providers).to receive(:client_for)
      psn = account(provider: "psn")
      steam = account

      described_class.perform_now

      expect(Achievements::Providers).not_to have_received(:client_for)
      expect(psn.reload.sync_due_at).to be_nil
      expect(marked?(steam)).to be(true)
    end
  end

  describe "while PSN auth has expired" do
    let(:psn_client) { instance_double(Psn::Client) }

    before do
      AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, (now - 1.day).iso8601)
      allow(Achievements::Providers).to receive(:client_for).with("psn").and_return(psn_client)
    end

    it "marks no PSN account, but still marks the other Providers" do
      allow(psn_client).to receive(:authenticate!).and_raise(Achievements::Providers::AuthExpired, "NPSSO expired")
      psn = account(provider: "psn")
      steam = account

      described_class.perform_now

      expect(psn.reload.sync_due_at).to be_nil
      expect(marked?(steam)).to be(true)
    end

    it "marks PSN accounts again once the club account authenticates" do
      allow(psn_client).to receive(:authenticate!) { AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, nil) }
      psn = account(provider: "psn")

      described_class.perform_now

      expect(marked?(psn)).to be(true)
    end
  end

  it "does not try to authenticate PSN while its auth is fine" do
    allow(Achievements::Providers).to receive(:client_for)

    described_class.perform_now

    expect(Achievements::Providers).not_to have_received(:client_for)
  end
end
