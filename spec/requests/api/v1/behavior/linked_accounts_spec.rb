# frozen_string_literal: true

require "rails_helper"

# Behavior specs for a member's Linked Accounts (api-05): list, link, unlink,
# Retry and Sync now under /api/v1/users/:user_id/linked_accounts. Owner-only
# (the bot service counts as the owner); an admin may only unlink. Provider
# clients are stubbed through Achievements::Providers.client_for.
RSpec.describe "api/v1 linked accounts behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:other) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:base) { "/api/v1/users/#{member.user_id}/linked_accounts" }

  def link(user, provider, **attrs)
    create(:user_linked_account, user: user, provider: provider, **attrs)
  end

  describe "GET /api/v1/users/:user_id/linked_accounts" do
    it "lists the owner's Linked Accounts with their sync state" do
      synced = 1.hour.ago.change(usec: 0)
      steam = link(member, "steam", display_name: "SteamName", sync_status: "ok", last_synced_at: synced,
        backfilled_at: synced)
      ra = link(member, "retroachievements", display_name: "RAName", sync_status: "private", sync_error: "hidden")
      link(other, "psn")

      freeze_time do
        get base, headers: auth_headers_for(member)

        expect(response).to have_http_status(:ok)
        rows = json.fetch("data").index_by { |row| row["provider"] }
        expect(rows.keys).to contain_exactly("steam", "retroachievements")
        expect(rows["steam"]).to include(
          "id" => steam.id, "external_id" => steam.external_id, "display_name" => "SteamName",
          "sync_status" => "ok", "sync_error" => nil, "last_synced_at" => synced.iso8601(3),
          "backfilled_at" => synced.iso8601(3), "sync_available_at" => Time.current.iso8601(3)
        )
        expect(rows["retroachievements"]).to include("id" => ra.id, "sync_status" => "private", "sync_error" => "hidden")
      end
    end

    it "reports the end of the Sync now cooldown as sync_available_at" do
      requested = 5.minutes.ago.change(usec: 0)
      link(member, "steam", sync_requested_at: requested)

      get base, headers: auth_headers_for(member)

      expect(json.dig("data", 0, "sync_available_at")).to eq((requested + 15.minutes).iso8601(3))
    end

    it "lets the bot service read it" do
      link(member, "steam")

      get base, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").size).to eq(1)
    end

    it "forbids another member and an admin" do
      link(member, "steam")

      get base, headers: auth_headers_for(other)
      expect(response).to have_http_status(:forbidden)

      get base, headers: auth_headers_for(admin)
      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get base

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/linked_accounts" do
    let(:ra_client) { instance_double(Retroachievements::Client) }
    let(:steam_client) { instance_double(Steam::Client) }
    let(:psn_client) { instance_double(Psn::Client) }

    before do
      allow(Achievements::Providers).to receive(:client_for).with("retroachievements").and_return(ra_client)
      allow(Achievements::Providers).to receive(:client_for).with("steam").and_return(steam_client)
      allow(Achievements::Providers).to receive(:client_for).with("psn").and_return(psn_client)
    end

    def post_link(provider, identifier, headers = auth_headers_for(member))
      post base, params: { data: { provider: provider, identifier: identifier } }, headers: headers, as: :json
    end

    it "links an RA account by its ULID, due now for a Backfill, and kicks the tick" do
      allow(ra_client).to receive(:user_profile).with("Scott")
        .and_return(external_id: "00003EMFWR7XB8SDPEHB3K56ZQ", display_name: "Scott", avatar_url: nil)

      freeze_time do
        expect { post_link("retroachievements", "Scott") }
          .to have_enqueued_job(Achievements::ProviderTickJob).with("retroachievements")

        expect(response).to have_http_status(:created)
        expect(json.fetch("data")).to include(
          "provider" => "retroachievements", "external_id" => "00003EMFWR7XB8SDPEHB3K56ZQ",
          "display_name" => "Scott", "sync_status" => "pending", "sync_mode" => "backfill"
        )
        account = UserLinkedAccount.find(json.dig("data", "id"))
        expect(account).to have_attributes(user_id: member.user_id, sync_due_at: Time.current)
      end
    end

    it "links a Steam account from a profile URL, by SteamID64 and persona name" do
      allow(steam_client).to receive(:resolve_profile).with("https://steamcommunity.com/id/gabe")
        .and_return(steam_id64: "76561197960287930", identifier_kind: "vanity_url")
      allow(steam_client).to receive(:player_summary).with("76561197960287930").and_return(profile_name: "Rabscuttle")

      expect { post_link("steam", "https://steamcommunity.com/id/gabe") }
        .to have_enqueued_job(Achievements::ProviderTickJob).with("steam")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("external_id" => "76561197960287930", "display_name" => "Rabscuttle")
    end

    it "links a PSN account by its accountId" do
      allow(psn_client).to receive(:resolve_account).with("Hakoom")
        .and_return(external_id: "2721710470513416437", display_name: "Hakoom", avatar_url: nil)

      post_link("psn", "Hakoom")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("external_id" => "2721710470513416437", "display_name" => "Hakoom")
    end

    it "surfaces a Steam vanity name Steam can't resolve as not_found" do
      allow(steam_client).to receive(:resolve_profile)
        .and_raise(Steam::Client::Error.new("invalid_identifier", "Steam profile id is not a valid SteamID64."))

      expect { post_link("steam", "nobody-here") }.not_to have_enqueued_job(Achievements::ProviderTickJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "not_found")
      expect(UserLinkedAccount.count).to eq(0)
    end

    it "surfaces a Provider NotFound as a 422 not_found reason" do
      allow(ra_client).to receive(:user_profile)
        .and_raise(Achievements::Providers::NotFound, "RetroAchievements user Ghost was not found.")

      post_link("retroachievements", "Ghost")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "not_found", "message" => "RetroAchievements user Ghost was not found.")
    end

    it "surfaces a Provider Private as a 422 private reason" do
      allow(psn_client).to receive(:resolve_account).and_raise(Achievements::Providers::Private, "hidden")

      post_link("psn", "Shy")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "private")
    end

    it "answers 503 when the Provider is unavailable" do
      allow(ra_client).to receive(:user_profile).and_raise(Achievements::Providers::RateLimited.new("slow down"))

      post_link("retroachievements", "Scott")

      expect(response).to have_http_status(:service_unavailable)
      expect(json).to include("error" => "provider_unavailable")
    end

    it "rejects an identity already claimed by another member" do
      link(other, "psn", external_id: "2721710470513416437")
      allow(psn_client).to receive(:resolve_account)
        .and_return(external_id: "2721710470513416437", display_name: "Hakoom", avatar_url: nil)

      expect { post_link("psn", "Hakoom") }.not_to have_enqueued_job(Achievements::ProviderTickJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "identity_claimed")
      expect(member.linked_accounts.count).to eq(0)
    end

    it "rejects a second Linked Account on the same Provider without asking the Provider" do
      link(member, "steam")

      post_link("steam", "76561197960287930")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "provider_already_linked")
      expect(Achievements::Providers).not_to have_received(:client_for)
    end

    it "rejects an unknown Provider with 422 and a blank identifier with 400" do
      post_link("xbox", "someone")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "invalid_provider")

      post_link("steam", " ")
      expect(response).to have_http_status(:bad_request)
    end

    it "lets the bot service link for the member, and forbids another member and an admin" do
      allow(psn_client).to receive(:resolve_account)
        .and_return(external_id: "2721710470513416437", display_name: "Hakoom", avatar_url: nil)

      post_link("psn", "Hakoom", auth_headers_for(other))
      expect(response).to have_http_status(:forbidden)

      post_link("psn", "Hakoom", auth_headers_for(admin))
      expect(response).to have_http_status(:forbidden)

      post_link("psn", "Hakoom", service_headers)
      expect(response).to have_http_status(:created)
    end
  end
end
