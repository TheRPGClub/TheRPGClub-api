# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::ListAccount do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 11, 1, 12) }
  let(:client) { instance_double(Steam::Client) }
  let(:account) do
    create(:user_linked_account, provider: "steam", sync_status: "pending", sync_mode: "backfill",
      sync_due_at: now - 1.minute)
  end

  before { allow(Achievements::Providers).to receive(:client_for).with("steam").and_return(client) }

  around { |example| travel_to(now) { example.run } }

  def played(external_id, **attributes)
    Achievements::Providers::PlayedSet.new(external_id: external_id, title: "Game #{external_id}", **attributes)
  end

  describe "a Backfill listing" do
    before do
      allow(client).to receive(:played_sets).with(account.external_id, since: nil).and_return([
        played("10", platform_label: "PC", icon_url: "https://img/10.jpg", playtime_minutes: 90),
        played("20")
      ])
    end

    it "creates the sets with the listing's title, platform and icon" do
      described_class.call(account)

      set = AchievementSet.find_by!(provider: "steam", external_id: "10")
      expect(set).to have_attributes(title: "Game 10", platform_label: "PC", icon_url: "https://img/10.jpg")
      expect(AchievementSet.where(provider: "steam").pluck(:external_id)).to contain_exactly("10", "20")
    end

    it "queues a placeholder progress row per set, carrying the listed playtime" do
      described_class.call(account)

      rows = account.set_progress.joins(:achievement_set).index_by { |row| row.achievement_set.external_id }
      expect(rows.keys).to contain_exactly("10", "20")
      expect(rows["10"]).to have_attributes(sync_pending_at: now, synced_at: nil, playtime_minutes: 90,
        user_id: account.user_id)
    end

    it "enqueues the GameDB link for each newly created set, after commit" do
      create(:achievement_set, provider: "steam", external_id: "20")

      expect { described_class.call(account) }
        .to have_enqueued_job(Achievements::LinkSetToGameJob).exactly(:once)
      expect(Achievements::LinkSetToGameJob).to have_been_enqueued
        .with(AchievementSet.find_by!(provider: "steam", external_id: "10"))
    end

    it "clears sync_due_at but leaves the account pending until its sets are imported" do
      described_class.call(account)

      expect(account.reload).to have_attributes(sync_due_at: nil, sync_status: "pending", backfilled_at: nil)
    end
  end

  describe "an incremental listing" do
    let(:last_synced_at) { now - 6.hours }
    let(:account) do
      create(:user_linked_account, provider: "steam", sync_mode: "incremental", sync_due_at: now,
        last_synced_at: last_synced_at, backfilled_at: now - 2.days)
    end
    let(:known_set) { create(:achievement_set, provider: "steam", external_id: "10") }
    let!(:known_row) do
      create(:user_achievement_set_progress, linked_account: account, achievement_set: known_set,
        synced_at: now - 6.hours, playtime_minutes: 30)
    end

    it "asks only for sets with activity since the last sync and re-queues them, keeping them readable" do
      allow(client).to receive(:played_sets).with(account.external_id, since: last_synced_at)
        .and_return([ played("10", playtime_minutes: 45) ])

      described_class.call(account)

      expect(known_row.reload).to have_attributes(sync_pending_at: now, synced_at: now - 6.hours, playtime_minutes: 45)
      expect(account.reload.sync_due_at).to be_nil
    end

    it "keeps a stored playtime when the listing carries none" do
      allow(client).to receive(:played_sets).and_return([ played("10") ])

      described_class.call(account)

      expect(known_row.reload.playtime_minutes).to eq(30)
    end

    it "finishes at once when nothing changed" do
      allow(client).to receive(:played_sets).and_return([])

      described_class.call(account)

      expect(account.reload).to have_attributes(last_synced_at: now, sync_status: "ok", sync_due_at: nil)
    end
  end

  it "finishes a Backfill with no played sets, so the account joins the Sync Windows" do
    allow(client).to receive(:played_sets).and_return([])

    described_class.call(account)

    expect(account.reload).to have_attributes(backfilled_at: now, last_synced_at: now, sync_status: "ok",
      sync_mode: "incremental")
  end

  describe "errors" do
    let!(:pending_row) { create(:user_achievement_set_progress, linked_account: account, sync_pending_at: now) }

    it "stops a private account: status, message, and every pending marker cleared" do
      allow(client).to receive(:played_sets).and_raise(Achievements::Providers::Private, "Steam game details are private.")

      described_class.call(account)

      expect(account.reload).to have_attributes(sync_status: "private", sync_error: "Steam game details are private.",
        sync_due_at: nil)
      expect(pending_row.reload.sync_pending_at).to be_nil
    end

    it "stops an account the Provider no longer knows" do
      allow(client).to receive(:played_sets).and_raise(Achievements::Providers::NotFound, "gone")

      described_class.call(account)

      expect(account.reload).to have_attributes(sync_status: "not_found", sync_error: "gone", sync_due_at: nil)
      expect(pending_row.reload.sync_pending_at).to be_nil
    end

    [ Achievements::Providers::RateLimited.new(retry_after: 30), Achievements::Providers::AuthExpired.new("npsso") ]
      .each do |error|
      it "re-raises #{error.class.name.demodulize} and leaves the state unchanged" do
        allow(client).to receive(:played_sets).and_raise(error)
        before = account.reload.attributes

        expect { described_class.call(account) }.to raise_error(error.class)
        expect(account.reload.attributes).to eq(before)
        expect(pending_row.reload.sync_pending_at).to eq(now)
      end
    end

    it "marks any other failure as an error and clears only the listing marker" do
      allow(client).to receive(:played_sets).and_raise(Steam::Client::Error.new("api_unavailable", "Steam API returned HTTP 500."))

      described_class.call(account)

      expect(account.reload).to have_attributes(sync_status: "error", sync_error: "Steam API returned HTTP 500.",
        sync_due_at: nil)
      expect(pending_row.reload.sync_pending_at).to eq(now)
    end
  end
end
