# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::ProviderTickJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 11, 1, 12) }
  let(:client) { double("Provider client") } # rubocop:disable RSpec/VerifiedDoubles

  around { |example| travel_to(now) { example.run } }

  before do
    UserLinkedAccount::PROVIDERS.each do |provider|
      allow(Achievements::Providers).to receive(:client_for).with(provider).and_return(client)
    end
    allow(client).to receive_messages(set_with_progress: nil, played_sets: [])
  end

  def due_account(provider = "steam", due_at: now - 1.minute, **attributes)
    create(:user_linked_account, provider: provider, sync_due_at: due_at, **attributes)
  end

  def pending_set(provider = "steam", pending_at: now - 1.minute)
    account = create(:user_linked_account, provider: provider)
    create(:user_achievement_set_progress, linked_account: account, synced_at: nil, sync_pending_at: pending_at,
      achievement_set: create(:achievement_set, provider: provider))
  end

  def tick(provider = "steam")
    described_class.perform_now(provider)
  end

  describe "one unit per run" do
    it "imports only the oldest pending set and re-enqueues itself with the Provider's spacing" do
      newer = pending_set(pending_at: now - 1.minute)
      oldest = pending_set(pending_at: now - 5.minutes)

      tick

      expect(oldest.reload.sync_pending_at).to be_nil
      expect(newer.reload.sync_pending_at).to eq(now - 1.minute)
      expect(described_class).to have_been_enqueued.with("steam").at(now + 1.second)
    end

    it "drains pending sets before listing the next due account" do
      account = due_account(due_at: now - 1.hour)
      row = pending_set(pending_at: now - 1.minute)

      tick

      expect(row.reload.sync_pending_at).to be_nil
      expect(account.reload.sync_due_at).to eq(now - 1.hour)
      expect(client).not_to have_received(:played_sets)
    end

    it "lists the oldest due account once no set is pending" do
      newer = due_account(due_at: now - 1.minute)
      oldest = due_account(due_at: now - 1.hour)

      tick

      expect(oldest.reload.sync_due_at).to be_nil
      expect(newer.reload.sync_due_at).to eq(now - 1.minute)
      expect(described_class).to have_been_enqueued.with("steam").at(now + 1.second)
    end

    it "spaces each Provider by its own SPACING" do
      { "retroachievements" => 4, "psn" => 3 }.each do |provider, seconds|
        2.times { due_account(provider) }

        tick(provider)

        expect(described_class).to have_been_enqueued.with(provider).at(now + seconds.seconds)
      end
    end

    it "only takes units of its own Provider" do
      other = pending_set("retroachievements")

      tick("steam")

      expect(other.reload.sync_pending_at).not_to be_nil
      expect(described_class).not_to have_been_enqueued
    end

    it "stops without re-enqueueing once the last unit is done" do
      row = pending_set

      tick

      expect(row.reload.sync_pending_at).to be_nil
      expect(described_class).not_to have_been_enqueued
    end

    it "stops at once when nothing is due" do
      due_account(due_at: now + 1.hour)

      tick

      expect(client).not_to have_received(:played_sets)
      expect(described_class).not_to have_been_enqueued
    end
  end

  # Solid Queue enforces the limit (the :test adapter can't run two jobs at
  # once), so this pins the configuration it enforces: one running tick per
  # Provider, and a duplicate tick for a busy Provider is dropped rather than
  # queued behind it, so a window starting twice can't double a chain.
  describe "concurrency" do
    it "lets only one tick per Provider run at a time" do
      expect(described_class.concurrency_limit).to eq(1)
      expect(described_class.new("steam").concurrency_key).to eq(described_class.new("steam").concurrency_key)
      expect(described_class.new("steam").concurrency_key).not_to eq(described_class.new("psn").concurrency_key)
    end

    it "discards a duplicate tick instead of running it after the first" do
      expect(described_class.concurrency_on_conflict).to eq(:discard)
    end

    it "holds the Provider's lock long enough for a slow unit" do
      expect(described_class.concurrency_duration).to be >= 15.minutes
    end
  end

  describe "when the Provider rate limits" do
    it "re-enqueues after the Provider's Retry-After, leaving the unit due" do
      row = pending_set
      allow(client).to receive(:set_with_progress)
        .and_raise(Achievements::Providers::RateLimited.new("slow down", retry_after: 120))

      tick

      expect(row.reload.sync_pending_at).to eq(now - 1.minute)
      expect(described_class).to have_been_enqueued.with("steam").at(now + 120.seconds)
    end

    it "waits 60 seconds when the Provider sent no Retry-After" do
      account = due_account
      allow(client).to receive(:played_sets).and_raise(Achievements::Providers::RateLimited)

      tick

      expect(account.reload.sync_due_at).to eq(now - 1.minute)
      expect(described_class).to have_been_enqueued.with("steam").at(now + 60.seconds)
    end
  end

  describe "when a Provider is not configured" do
    it "re-raises and logs it, leaving the account's sync state untouched and the chain stopped" do
      account = due_account
      allow(client).to receive(:played_sets).and_raise(Steam::Client::ConfigurationError, "STEAM_WEB_API_KEY must be set")
      allow(Rails.logger).to receive(:error)

      expect { tick }.to raise_error(Steam::Client::ConfigurationError)

      expect(account.reload).to have_attributes(sync_status: "ok", sync_error: nil, sync_due_at: now - 1.minute)
      expect(Rails.logger).to have_received(:error).with(/steam.*STEAM_WEB_API_KEY must be set/)
      expect(described_class).not_to have_been_enqueued
    end

    it "treats a missing RetroAchievements key the same way on a set import" do
      row = pending_set("retroachievements")
      allow(client).to receive(:set_with_progress)
        .and_raise(Retroachievements::Client::ConfigurationError, "RETROACHIEVEMENTS_API_KEY must be set")

      expect { tick("retroachievements") }.to raise_error(Retroachievements::Client::ConfigurationError)

      expect(row.reload.sync_pending_at).to eq(now - 1.minute)
      expect(row.linked_account.reload).to have_attributes(sync_status: "ok", sync_error: nil)
    end
  end

  describe "the PSN pause" do
    it "stops the PSN chain at once while PSN auth has expired" do
      row = pending_set("psn")
      AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, (now - 1.hour).iso8601)

      tick("psn")

      expect(client).not_to have_received(:set_with_progress)
      expect(row.reload.sync_pending_at).to eq(now - 1.minute)
      expect(described_class).not_to have_been_enqueued
    end

    it "does not pause the other Providers" do
      row = pending_set("steam")
      AchievementHubState.set(Psn::Client::AUTH_EXPIRED_KEY, (now - 1.hour).iso8601)

      tick("steam")

      expect(row.reload.sync_pending_at).to be_nil
    end

    it "stops the chain when PSN auth expires mid-unit, leaving the unit due" do
      account = due_account("psn")
      2.times { pending_set("psn") }
      allow(client).to receive(:set_with_progress).and_raise(Achievements::Providers::AuthExpired, "NPSSO expired")

      expect { tick("psn") }.not_to raise_error

      expect(UserAchievementSetProgress.sync_pending("psn").count).to eq(2)
      expect(account.reload).to have_attributes(sync_due_at: now - 1.minute, sync_status: "ok")
      expect(described_class).not_to have_been_enqueued
    end
  end
end
