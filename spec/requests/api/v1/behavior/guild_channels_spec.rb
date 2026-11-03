# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the guild channel sync (web parity 2, #313). The bot
# reports the guild's channels (full sync at startup, per-channel upsert and
# delete on create, rename, move and delete); any authenticated caller can
# list the text channels for channel pickers. Channel `channel_type` is
# Discord's numeric ChannelType (0 text, 2 voice, 4 category, 5 announcement).
RSpec.describe "api/v1/guild_channels behavior", type: :request do
  def channel_payload(id, name, type: 0, parent_id: nil, position: 0)
    { channel_id: id, name: name, channel_type: type, parent_id: parent_id, position: position }
  end

  describe "GET /api/v1/guild_channels" do
    it "lists text channels ordered by category position, then channel position" do
      create(:guild_channel, channel_id: "900", name: "Lounge", channel_type: 4, position: 1)
      create(:guild_channel, channel_id: "800", name: "Info", channel_type: 4, position: 0)
      create(:guild_channel, channel_id: "11", name: "chat", parent_id: "900", position: 1)
      create(:guild_channel, channel_id: "12", name: "games", parent_id: "900", position: 0)
      create(:guild_channel, channel_id: "13", name: "news", channel_type: 5, parent_id: "800", position: 3)
      create(:guild_channel, channel_id: "14", name: "rules", parent_id: nil, position: 0)
      create(:guild_channel, channel_id: "15", name: "Voice", channel_type: 2, parent_id: "900", position: 2)

      get "/api/v1/guild_channels", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |c| c.fetch("name") }).to eq(%w[rules news games chat])
      expect(json.fetch("data").second).to eq(
        "channel_id" => "13", "name" => "news", "channel_type" => 5, "parent_id" => "800",
        "position" => 3, "category_name" => "Info"
      )
      expect(json.fetch("data").first).to include("parent_id" => nil, "category_name" => nil)
      expect(json.fetch("meta")).to eq("count" => 4)
    end

    it "requires authentication" do
      get "/api/v1/guild_channels"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/guild_channels/sync" do
    def picker_names
      get "/api/v1/guild_channels", headers: auth_headers_for(create(:user))
      json.fetch("data").map { |c| [ c.fetch("name"), c.fetch("category_name") ] }
    end

    it "replaces the whole channel list" do
      create(:guild_channel, channel_id: "1", name: "old-name")
      create(:guild_channel, channel_id: "2", name: "gone")

      post "/api/v1/guild_channels/sync", headers: service_headers, as: :json, params: {
        data: [
          channel_payload("9", "Club", type: 4, position: 0),
          channel_payload("1", "renamed", parent_id: "9", position: 1),
          channel_payload("3", "new", parent_id: "9", position: 0)
        ]
      }

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => { "synced" => 3, "removed" => 1 })
      expect(picker_names).to eq([ %w[new Club], %w[renamed Club] ])
    end

    it "rejects an invalid entry and keeps the old list" do
      create(:guild_channel, channel_id: "1", name: "kept")

      post "/api/v1/guild_channels/sync", headers: service_headers, as: :json, params: {
        data: [ channel_payload("3", "new"), channel_payload("4", "") ]
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(picker_names).to eq([ [ "kept", nil ] ])
    end

    it "requires a data array" do
      post "/api/v1/guild_channels/sync", headers: service_headers, as: :json, params: { data: { name: "x" } }

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids an admin (service-only)" do
      post "/api/v1/guild_channels/sync", headers: auth_headers_for(create(:user, :admin)), as: :json,
        params: { data: [] }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PUT /api/v1/guild_channels/:channel_id" do
    it "creates a channel the API has not seen" do
      put "/api/v1/guild_channels/21", headers: service_headers, as: :json,
        params: { data: { name: "fresh", channel_type: 0, position: 4 } }

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("channel_id" => "21", "name" => "fresh", "position" => 4)
    end

    it "renames and moves an existing channel, keyed on the path id" do
      create(:guild_channel, channel_id: "21", name: "old")
      create(:guild_channel, channel_id: "9", name: "Club", channel_type: 4)

      put "/api/v1/guild_channels/21", headers: service_headers, as: :json,
        params: { data: { channel_id: "999", name: "new", channel_type: 0, parent_id: "9", position: 2 } }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("channel_id" => "21", "name" => "new", "parent_id" => "9")
      get "/api/v1/guild_channels", headers: auth_headers_for(create(:user))
      expect(json.fetch("data").map { |c| [ c["channel_id"], c["category_name"] ] }).to eq([ %w[21 Club] ])
    end

    it "rejects a channel without a name" do
      put "/api/v1/guild_channels/21", headers: service_headers, as: :json,
        params: { data: { name: "", channel_type: 0 } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids a regular user" do
      put "/api/v1/guild_channels/21", headers: auth_headers_for(create(:user)), as: :json,
        params: { data: { name: "x", channel_type: 0 } }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/guild_channels/:channel_id" do
    it "removes the channel" do
      create(:guild_channel, channel_id: "21")

      delete "/api/v1/guild_channels/21", headers: service_headers

      expect(response).to have_http_status(:no_content)
      get "/api/v1/guild_channels", headers: auth_headers_for(create(:user))
      expect(json.fetch("data")).to eq([])
    end

    it "succeeds for a channel the API never saw, so the bot need not track it" do
      delete "/api/v1/guild_channels/404404", headers: service_headers

      expect(response).to have_http_status(:no_content)
    end

    it "forbids a regular user" do
      create(:guild_channel, channel_id: "21")

      delete "/api/v1/guild_channels/21", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end
  end
end
