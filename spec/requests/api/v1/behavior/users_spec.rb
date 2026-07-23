# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the users endpoints: the searchable members list, the
# aggregated profile, the service-only Discord member-sync writes
# (update/upsert/mark_departed) and the public image streams.
RSpec.describe "api/v1/users behavior", type: :request do
  # The consumer-audited UserFields column allowlist (#36) — notably WITHOUT
  # the binary avatar_blob/profile_image columns.
  let(:summary_keys) do
    %w[user_id username global_name is_bot role_admin role_moderator role_regular server_left_at]
  end

  describe "GET /api/v1/users" do
    it "lists users with the summary shape (no binary columns) and pagination meta" do
      user = create(:user, global_name: "Global #{SecureRandom.hex(4)}")

      get "/api/v1/users", params: { q: user.username }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      record = json.fetch("data").first
      expect(record).to include(
        "user_id" => user.user_id,
        "username" => user.username,
        "global_name" => user.global_name,
        "is_bot" => false,
        "server_left_at" => nil
      )
      expect(record.keys).to match_array(summary_keys)
      expect(record).not_to have_key("avatar_blob")
      expect(record).not_to have_key("profile_image")
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "requires authentication" do
      get "/api/v1/users"

      expect(response).to have_http_status(:unauthorized)
    end

    it "matches q against global_name case-insensitively" do
      user = create(:user, global_name: "Qglobal #{SecureRandom.hex(4)}")

      get "/api/v1/users", params: { q: user.global_name.upcase }, headers: service_headers

      expect(json.fetch("data").map { |u| u.fetch("user_id") }).to eq([ user.user_id ])
    end

    it "matches q as an exact user_id" do
      user = create(:user)

      get "/api/v1/users", params: { q: user.user_id }, headers: service_headers

      expect(json.fetch("data").map { |u| u.fetch("user_id") }).to eq([ user.user_id ])
    end

    it "filters by a comma-separated discord_id list" do
      a = create(:user)
      b = create(:user)
      create(:user) # excluded

      get "/api/v1/users", params: { discord_id: "#{a.user_id},#{b.user_id}" }, headers: service_headers

      expect(json.fetch("data").map { |u| u.fetch("user_id") }).to contain_exactly(a.user_id, b.user_id)
    end

    it "filters has_emoji_name and serializes the UserService shape" do
      prefix = "emoji#{SecureRandom.hex(4)}"
      with_emoji = create(:user, username: "#{prefix} yes", emoji_name: "blob_#{SecureRandom.hex(3)}")
      create(:user, username: "#{prefix} no")

      get "/api/v1/users", params: { q: prefix, has_emoji_name: true }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      record = json.fetch("data").first
      expect(record).to include("user_id" => with_emoji.user_id, "emoji_name" => with_emoji.emoji_name)
      expect(record.keys).to include("server_joined_at", "last_seen_at")
      expect(record).not_to have_key("avatar_blob")
    end

    it "filters has_platform via canonical tokens and embeds socials" do
      platform = SocialPlatform.create!(label: "Xbox #{SecureRandom.hex(4)}")
      linked = create(:user)
      social = create(:user_social, user: linked, social_platform: platform)
      create(:user) # no socials

      get "/api/v1/users", params: { q: linked.username, has_platform: "xbl" }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      record = json.fetch("data").first
      expect(record.fetch("user_id")).to eq(linked.user_id)
      expect(record.fetch("socials").length).to eq(1)
      expect(record.fetch("socials").first).to include("id" => social.id, "url" => social.url)
      expect(record.dig("socials", 0, "social_platform")).to include("id" => platform.id, "label" => platform.label)
    end

    it "excludes users without a matching platform social" do
      prefix = "plat#{SecureRandom.hex(4)}"
      platform = SocialPlatform.create!(label: "Steam #{SecureRandom.hex(4)}")
      linked = create(:user, username: "#{prefix} linked")
      create(:user_social, user: linked, social_platform: platform)
      create(:user, username: "#{prefix} unlinked")

      get "/api/v1/users", params: { q: prefix, has_platform: "steam" }, headers: service_headers

      expect(json.fetch("data").map { |u| u.fetch("user_id") }).to eq([ linked.user_id ])
    end

    it "paginates with page/per" do
      prefix = "page#{SecureRandom.hex(4)}"
      3.times { |i| create(:user, username: "#{prefix} #{i}") }

      get "/api/v1/users", params: { q: prefix, per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1, "count" => 3, "pages" => 2)
    end
  end

  describe "GET /api/v1/users/:user_id" do
    let(:user) { create(:user) }
    let(:game) { create(:game) }

    it "returns the aggregated profile with membership, socials, previews and counts" do
      social = create(:user_social, user: user)
      favorite = UserGameFavorite.create!(user_id: user.user_id, gamedb_game_id: game.game_id, sort_order: 1)
      create(:backlog_entry, user: user)

      get "/api/v1/users/#{user.user_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data).to include("user_id" => user.user_id, "username" => user.username)
      expect(data).not_to have_key("avatar_blob")
      expect(data).not_to have_key("profile_image")
      expect(data.fetch("membership")).to eq(
        "admin" => false, "moderator" => false, "regular" => false,
        "member" => false, "newcomer" => false, "active" => true
      )
      expect(data.fetch("socials").map { |s| s.fetch("id") }).to eq([ social.id ])
      expect(data.fetch("favorites").length).to eq(1)
      expect(data.fetch("favorites").first).to include(
        "entry_id" => favorite.entry_id,
        "gamedb_game_id" => game.game_id
      )
      expect(data.dig("favorites", 0, "game")).to include("game_id" => game.game_id, "title" => game.title)
      expect(data.fetch("counts")).to eq(
        "now_playing" => 0, "favorites" => 1, "reviews" => 0, "completions" => 0,
        "backlog" => 1, "collections" => 0, "journal" => 0
      )
      expect(data.fetch("now_playing")).to eq([])
      expect(data.fetch("reviews")).to eq([])
      expect(data.fetch("completions")).to eq([])
      expect(data.fetch("journal")).to eq([])
    end

    it "caps each preview list at preview_limit while counts stay totals" do
      UserGameFavorite.create!(user_id: user.user_id, gamedb_game_id: game.game_id, sort_order: 1)
      UserGameFavorite.create!(user_id: user.user_id, gamedb_game_id: create(:game).game_id, sort_order: 2)

      get "/api/v1/users/#{user.user_id}", params: { preview_limit: 1 }, headers: service_headers

      expect(json.dig("data", "favorites").length).to eq(1)
      expect(json.dig("data", "counts", "favorites")).to eq(2)
    end

    it "404s for an unknown user id" do
      get "/api/v1/users/999999999999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      get "/api/v1/users/#{user.user_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/users/:user_id" do
    let(:user) { create(:user) }

    it "updates emoji_name and last_seen as the service" do
      patch "/api/v1/users/#{user.user_id}",
        params: { data: { emoji_name: "blobwave", last_seen: "2026-01-02T03:04:05Z" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("user_id" => user.user_id, "emoji_name" => "blobwave")
      user.reload
      expect(user.emoji_name).to eq("blobwave")
      expect(user.last_seen_at).to eq(Time.utc(2026, 1, 2, 3, 4, 5))
    end

    it "clears emoji_name with an explicit null" do
      user.update!(emoji_name: "old_emoji")

      patch "/api/v1/users/#{user.user_id}",
        params: { data: { emoji_name: nil } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.emoji_name).to be_nil
    end

    it "stamps server_left_at when departed is true" do
      patch "/api/v1/users/#{user.user_id}",
        params: { data: { departed: true } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.server_left_at).to be_present
    end

    it "preserves an existing departure timestamp on a repeated departed=true" do
      original = 2.days.ago
      user.update!(server_left_at: original)

      patch "/api/v1/users/#{user.user_id}",
        params: { data: { departed: true } }, headers: service_headers, as: :json

      expect(user.reload.server_left_at).to be_within(1.second).of(original)
    end

    it "clears server_left_at when departed is false (rejoin)" do
      user.update!(server_left_at: 2.days.ago)

      patch "/api/v1/users/#{user.user_id}",
        params: { data: { departed: false } }, headers: service_headers, as: :json

      expect(user.reload.server_left_at).to be_nil
    end

    it "forbids a user token, even the owner's" do
      patch "/api/v1/users/#{user.user_id}",
        params: { data: { emoji_name: "hijack" } }, headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(user.reload.emoji_name).to be_nil
    end

    it "404s for an unknown user id" do
      patch "/api/v1/users/999999999999999999",
        params: { data: { emoji_name: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      patch "/api/v1/users/#{user.user_id}",
        params: { emoji_name: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      patch "/api/v1/users/#{user.user_id}", params: { data: { emoji_name: "x" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/upsert" do
    let(:discord_id) { SecureRandom.random_number(10**18).to_s }

    it "creates a new user and returns 201 with the UserService shape" do
      expect {
        post "/api/v1/users/upsert",
          params: { data: { discord_id: discord_id, username: "new_member", global_name: "New Member",
                            is_bot: false, server_joined_at: "2026-01-01T00:00:00Z" } },
          headers: service_headers, as: :json
      }.to change(RpgClubUser, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => discord_id,
        "username" => "new_member",
        "global_name" => "New Member",
        "is_bot" => false
      )
      expect(json.fetch("data")).to have_key("server_joined_at")
      expect(RpgClubUser.find(discord_id).server_joined_at).to eq(Time.utc(2026, 1, 1))
    end

    it "updates an existing user (200) and clears a departure with server_left_at: null" do
      user = create(:user, server_left_at: 2.days.ago)

      expect {
        post "/api/v1/users/upsert",
          params: { data: { discord_id: user.user_id, username: "renamed", server_left_at: nil } },
          headers: service_headers, as: :json
      }.not_to change(RpgClubUser, :count)

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.username).to eq("renamed")
      expect(user.server_left_at).to be_nil
    end

    it "422s when discord_id is missing" do
      post "/api/v1/users/upsert",
        params: { data: { username: "no_id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("discord_id")
    end

    it "forbids user tokens, including admins" do
      post "/api/v1/users/upsert",
        params: { data: { discord_id: discord_id } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(RpgClubUser.exists?(discord_id)).to be(false)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/upsert", params: { discord_id: discord_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/upsert", params: { data: { discord_id: discord_id } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/mark_departed" do
    it "marks active users missing from active_ids as departed, preserving prior departures" do
      staying = create(:user)
      leaving = create(:user)
      long_gone = create(:user, server_left_at: 3.days.ago)
      original_departure = long_gone.server_left_at

      post "/api/v1/users/mark_departed",
        params: { active_ids: [ staying.user_id ] }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("count")).to be >= 1
      expect(staying.reload.server_left_at).to be_nil
      expect(leaving.reload.server_left_at).to be_present
      expect(long_gone.reload.server_left_at).to be_within(1.second).of(original_departure)
    end

    it "accepts active_ids nested under the data envelope" do
      staying = create(:user)
      leaving = create(:user)

      post "/api/v1/users/mark_departed",
        params: { data: { active_ids: [ staying.user_id ] } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(staying.reload.server_left_at).to be_nil
      expect(leaving.reload.server_left_at).to be_present
    end

    it "rejects an empty active_ids list" do
      user = create(:user)

      post "/api/v1/users/mark_departed", params: { active_ids: [] }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.server_left_at).to be_nil
    end

    it "forbids user tokens" do
      post "/api/v1/users/mark_departed",
        params: { active_ids: [ "1" ] }, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/users/mark_departed", params: { active_ids: [ "1" ] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/avatar" do
    it "streams the stored PNG without authentication" do
      user = create(:user)
      user.update_column(:avatar_blob, "fake-avatar-bytes")

      get "/api/v1/users/#{user.user_id}/avatar"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.body).to eq("fake-avatar-bytes")
    end

    it "sets public cache headers and 304s on a matching ETag" do
      user = create(:user)
      user.update_column(:avatar_blob, "fake-avatar-bytes")

      get "/api/v1/users/#{user.user_id}/avatar"

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.headers["Cache-Control"]).to include("max-age=86400")
      expect(response.headers["Last-Modified"]).to be_present
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get "/api/v1/users/#{user.user_id}/avatar", headers: { "If-None-Match" => etag }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it "re-streams when the blob changed under the client's ETag" do
      user = create(:user)
      user.update_column(:avatar_blob, "fake-avatar-bytes")

      get "/api/v1/users/#{user.user_id}/avatar"
      stale_etag = response.headers["ETag"]

      user.update_column(:avatar_blob, "new-avatar-bytes")

      get "/api/v1/users/#{user.user_id}/avatar", headers: { "If-None-Match" => stale_etag }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("new-avatar-bytes")
    end

    it "404s when no avatar is stored" do
      user = create(:user)

      get "/api/v1/users/#{user.user_id}/avatar"

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "image_not_found")
    end

    it "404s for an unknown user" do
      get "/api/v1/users/999999999999999999/avatar"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/users/:user_id/profile-image" do
    it "streams the stored profile image without authentication" do
      user = create(:user)
      user.update_column(:profile_image, "fake-profile-bytes")

      get "/api/v1/users/#{user.user_id}/profile-image"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.body).to eq("fake-profile-bytes")
    end

    it "404s when no profile image is stored" do
      user = create(:user)

      get "/api/v1/users/#{user.user_id}/profile-image"

      expect(response).to have_http_status(:not_found)
    end
  end
end
