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
end
