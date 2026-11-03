# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the completion endpoints: reads are open to any
# authenticated principal, writes are gated to the owner (or the service).
RSpec.describe "api/v1/completions behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/completions" do
    it "lists only that user's completions with the embedded game and platform" do
      platform = create(:platform)
      completion = create(:completion, user: owner, platform: platform, note: "beat it")
      create(:completion, user: other_user)

      get "/api/v1/users/#{owner.user_id}/completions", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "completion_id" => completion.completion_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => completion.gamedb_game_id,
        "completion_type" => "Main Story",
        "platform_id" => platform.platform_id,
        "note" => "beat it"
      )
      expect(json.dig("data", 0, "game")).to include("game_id" => completion.gamedb_game_id)
      expect(json.dig("data", 0, "platform")).to include("platform_id" => platform.platform_id)
    end

    it "filters by game_id with an exact meta.count" do
      keeper = create(:completion, user: owner)
      create(:completion, user: owner)

      get "/api/v1/users/#{owner.user_id}/completions",
        params: { game_id: keeper.gamedb_game_id }, headers: service_headers

      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ keeper.completion_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "filters by year, with the literal unknown matching null completed_at" do
      completed_2020 = create(:completion, user: owner, completed_at: Time.utc(2020, 5, 5))
      unknown = create(:completion, user: owner)
      unknown.update_columns(completed_at: nil)

      get "/api/v1/users/#{owner.user_id}/completions", params: { year: "2020" }, headers: service_headers
      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ completed_2020.completion_id ])

      get "/api/v1/users/#{owner.user_id}/completions", params: { year: "unknown" }, headers: service_headers
      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ unknown.completion_id ])
    end

    it "filters by q on the game title, case-insensitively" do
      game = create(:game, title: "cmplq secret quest #{SecureRandom.hex(4)}")
      match = create(:completion, user: owner, game: game)
      create(:completion, user: owner)

      get "/api/v1/users/#{owner.user_id}/completions", params: { q: "CMPLQ SECRET" }, headers: service_headers

      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ match.completion_id ])
    end

    it "filters by exact platform_id with an exact meta.count" do
      platform = create(:platform)
      match = create(:completion, user: owner, platform: platform)
      create(:completion, user: owner, platform: create(:platform))
      create(:completion, user: owner)

      get "/api/v1/users/#{owner.user_id}/completions",
        params: { platform_id: platform.platform_id }, headers: service_headers

      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ match.completion_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/completions"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/completions/export" do
    let(:header_row) { "ID,Game ID,Title,Type,Platform ID,Completed Date,Playtime (Hours),Note,Created At" }

    it "sends the owner a CSV attachment with the bot's columns, newest completion first" do
      platform = create(:platform)
      game = create(:game, title: "Chrono Trigger")
      older = create(:completion, user: owner, game: game, platform: platform,
        completed_at: Time.utc(2021, 3, 4, 22, 0), final_playtime_hrs: 25.5, note: "great")
      older.update_columns(created_at: Time.utc(2021, 3, 5, 10, 11, 12.345))
      newer = create(:completion, user: owner, game: game, completion_type: "Completionist",
        completed_at: Time.utc(2022, 1, 2), final_playtime_hrs: 40)
      newer.update_columns(created_at: Time.utc(2022, 1, 2, 8, 0, 0))
      create(:completion, user: other_user)

      get "/api/v1/users/#{owner.user_id}/completions/export", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("attachment", 'filename="completions.csv"')
      expect(response.body.lines(chomp: true)).to eq([
        header_row,
        "#{newer.completion_id},#{game.game_id},Chrono Trigger,Completionist,,2022-01-02,40,,2022-01-02T08:00:00.000Z",
        "#{older.completion_id},#{game.game_id},Chrono Trigger,Main Story,#{platform.platform_id},2021-03-04,25.5,great,2021-03-05T10:11:12.345Z"
      ])
    end

    it "forbids another member from exporting someone else's completions" do
      create(:completion, user: owner)

      get "/api/v1/users/#{owner.user_id}/completions/export", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "lets the service export on a member's behalf" do
      get "/api/v1/users/#{owner.user_id}/completions/export", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "returns just the header row when the user has no completions" do
      get "/api/v1/users/#{owner.user_id}/completions/export", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("#{header_row}\n")
    end

    it "quotes titles and notes that contain commas, quotes or line breaks" do
      game = create(:game, title: 'Tom Clancy\'s "Ghost Recon", Wildlands')
      completion = create(:completion, user: owner, game: game, note: "line one\r\nline two")

      get "/api/v1/users/#{owner.user_id}/completions/export", headers: auth_headers_for(owner)

      row = response.body.delete_prefix("#{header_row}\n")
      expect(row).to start_with(%(#{completion.completion_id},#{game.game_id},"Tom Clancy's ""Ghost Recon"", Wildlands",Main Story,))
      expect(row).to include(%("line one\r\nline two"))
      expect(CSV.parse(response.body, headers: true).first.to_h).to include(
        "Title" => 'Tom Clancy\'s "Ghost Recon", Wildlands', "Note" => "line one\r\nline two"
      )
    end
  end

  describe "GET /api/v1/games/:id/completions" do
    it "lists a game's completions with the completing user embedded" do
      game = create(:game)
      entry = create(:completion, user: owner, game: game)
      create(:completion, user: owner)

      get "/api/v1/games/#{game.game_id}/completions", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |c| c.fetch("completion_id") }).to eq([ entry.completion_id ])
      expect(json.dig("data", 0, "user")).to include("user_id" => owner.user_id)
    end
  end

  describe "GET /api/v1/completions/leaderboard" do
    it "ranks active members by matching completion count, excluding departed members" do
      prefix = "ldbq #{SecureRandom.hex(4)}"
      top = create(:user)
      runner_up = create(:user)
      departed = create(:user, server_left_at: Time.current)
      3.times { create(:completion, user: top, game: create(:game, title: "#{prefix} #{SecureRandom.hex(4)}")) }
      create(:completion, user: runner_up, game: create(:game, title: "#{prefix} #{SecureRandom.hex(4)}"))
      create(:completion, user: departed, game: create(:game, title: "#{prefix} #{SecureRandom.hex(4)}"))

      get "/api/v1/completions/leaderboard", params: { q: prefix }, headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      rows = json.fetch("data")
      expect(rows.map { |r| r.fetch("user_id") }).to eq([ top.user_id, runner_up.user_id ])
      expect(rows.first).to include("username" => top.username, "completion_count" => 3)
      expect(json.dig("meta", "count")).to eq(2)
    end

    it "requires authentication" do
      get "/api/v1/completions/leaderboard"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/completions" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", note: "done" } } }

    it "creates a completion for the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completions",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameCompletion.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "completion_type" => "Main Story",
        "note" => "done"
      )
      expect(json.dig("data", "game", "game_id")).to eq(game.game_id)
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/completions", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completions",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserGameCompletion, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/completions",
        params: { data: { gamedb_game_id: 999_999_999, completion_type: "Main Story" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when completion_type is missing" do
      post "/api/v1/users/#{owner.user_id}/completions",
        params: { data: { gamedb_game_id: game.game_id } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/completions",
        params: { gamedb_game_id: game.game_id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/completions", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    describe "for another member" do
      callers = {
        "anonymous" => [ nil, :unauthorized ],
        "a plain member" => [ -> { auth_headers_for(create(:user)) }, :forbidden ],
        "a Members role holder" => [ -> { auth_headers_for(create(:user, role_member: true)) }, :forbidden ],
        "a Regulars role holder" => [ -> { auth_headers_for(create(:user, role_regular: true)) }, :forbidden ],
        "a Moderator" => [ -> { auth_headers_for(create(:user, role_moderator: true)) }, :forbidden ],
        "an Admin" => [ -> { auth_headers_for(create(:user, :admin)) }, :forbidden ],
        "a Superadmin" => [ -> { auth_headers_for(create(:user), is_dev: true) }, :created ],
        "the service" => [ -> { service_headers }, :created ]
      }

      callers.each do |label, (headers_for, status)|
        it "answers #{status} to #{label}" do
          headers = headers_for ? instance_exec(&headers_for) : {}

          post "/api/v1/users/#{owner.user_id}/completions", params: payload, headers: headers, as: :json

          expect(response).to have_http_status(status)
          expect(UserGameCompletion.where(user_id: owner.user_id).count).to eq(status == :created ? 1 : 0)
        end
      end

      let(:superadmin) { create(:user, username: "boss") }

      it "takes the game off the member's Now Playing when a Superadmin logs it" do
        create(:now_playing_entry, user: owner, game: game)
        other_game = create(:game)
        create(:now_playing_entry, user: owner, game: other_game)
        create(:now_playing_entry, user: superadmin, game: game)

        post "/api/v1/users/#{owner.user_id}/completions",
          params: payload, headers: auth_headers_for(superadmin, is_dev: true), as: :json

        expect(response).to have_http_status(:created)
        expect(UserNowPlaying.where(user_id: owner.user_id).pluck(:gamedb_game_id)).to eq([ other_game.game_id ])
        expect(UserNowPlaying.where(user_id: superadmin.user_id).count).to eq(1)
      end

      it "404s when a Superadmin logs one for an unknown member" do
        expect {
          post "/api/v1/users/999999999999/completions",
            params: payload, headers: auth_headers_for(superadmin, is_dev: true), as: :json
        }.not_to change(UserGameCompletion, :count)

        expect(response).to have_http_status(:not_found)
      end

      it "leaves Now Playing alone when the owner logs their own" do
        create(:now_playing_entry, user: owner, game: game)

        post "/api/v1/users/#{owner.user_id}/completions", params: payload, headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:created)
        expect(UserNowPlaying.where(user_id: owner.user_id).count).to eq(1)
      end

      it "leaves Now Playing alone when the create fails" do
        create(:now_playing_entry, user: owner, game: game)

        post "/api/v1/users/#{owner.user_id}/completions",
          params: { data: { gamedb_game_id: game.game_id } },
          headers: auth_headers_for(superadmin, is_dev: true), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(UserNowPlaying.where(user_id: owner.user_id).count).to eq(1)
      end

      it "queues completion_announce with the completion, member and actor when announce is set" do
        owner.update!(global_name: "Alice")
        game.update!(title: "Chrono Trigger")

        expect {
          post "/api/v1/users/#{owner.user_id}/completions",
            params: { data: payload[:data].merge(announce: true) },
            headers: auth_headers_for(superadmin, is_dev: true), as: :json
        }.to change(BotJob, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json.fetch("data")).not_to have_key("announce")
        job = BotJob.last
        expect(job.kind).to eq("completion_announce")
        expect(job.payload).to eq(
          "completion_id" => json.dig("data", "completion_id"),
          "user_id" => owner.user_id,
          "game_id" => game.game_id,
          "actor_user_id" => superadmin.user_id
        )
        expect(job.summary).to eq(%(Announce Alice's Game Completion of "Chrono Trigger"))
        expect(job.requested_by_user_id).to eq(superadmin.user_id)
      end

      it "queues nothing without the announce flag, or with it false" do
        expect {
          post "/api/v1/users/#{owner.user_id}/completions",
            params: payload, headers: auth_headers_for(superadmin, is_dev: true), as: :json
          post "/api/v1/users/#{owner.user_id}/completions",
            params: { data: payload[:data].merge(announce: false) },
            headers: auth_headers_for(superadmin, is_dev: true), as: :json
        }.not_to change(BotJob, :count)
      end

      it "queues nothing when the create fails" do
        expect {
          post "/api/v1/users/#{owner.user_id}/completions",
            params: { data: { gamedb_game_id: game.game_id, announce: true } },
            headers: auth_headers_for(superadmin, is_dev: true), as: :json
        }.not_to change(BotJob, :count)
      end

      it "422s for an announce flag that is not a boolean" do
        expect {
          post "/api/v1/users/#{owner.user_id}/completions",
            params: { data: payload[:data].merge(announce: "loudly") },
            headers: auth_headers_for(superadmin, is_dev: true), as: :json
        }.not_to change(UserGameCompletion, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "lets the owner announce their own, with themselves as the actor" do
        post "/api/v1/users/#{owner.user_id}/completions",
          params: { data: payload[:data].merge(announce: true) }, headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:created)
        expect(BotJob.last.payload).to include("user_id" => owner.user_id, "actor_user_id" => owner.user_id)
        expect(BotJob.last.requested_by_user_id).to eq(owner.user_id)
      end

      it "queues the service's announce with no actor or requester" do
        post "/api/v1/users/#{owner.user_id}/completions",
          params: { data: payload[:data].merge(announce: true) }, headers: service_headers, as: :json

        expect(response).to have_http_status(:created)
        expect(BotJob.last.payload).to include("actor_user_id" => nil)
        expect(BotJob.last.requested_by_user_id).to be_nil
      end
    end
  end

  describe "GET /api/v1/completions/:id" do
    it "shows a completion to any authenticated user" do
      completion = create(:completion, user: owner)

      get "/api/v1/completions/#{completion.completion_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("completion_id" => completion.completion_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/completions/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/completions/:id" do
    it "updates the owner's completion" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { note: "updated note" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "note")).to eq("updated note")
      expect(completion.reload.note).to eq("updated note")
    end

    it "allows the service" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { note: "service note" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(completion.reload.note).to eq("service note")
    end

    it "forbids a non-owner" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { note: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(completion.reload.note).not_to eq("hijacked")
    end

    it "404s for an unknown id (as the service)" do
      patch "/api/v1/completions/999999999",
        params: { data: { note: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "422s when completion_type is blanked" do
      completion = create(:completion, user: owner)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { completion_type: "" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/completions/:id" do
    it "deletes the owner's completion" do
      completion = create(:completion, user: owner)

      delete "/api/v1/completions/#{completion.completion_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameCompletion.exists?(completion.completion_id)).to be(false)
    end

    it "forbids a non-owner" do
      completion = create(:completion, user: owner)

      delete "/api/v1/completions/#{completion.completion_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameCompletion.exists?(completion.completion_id)).to be(true)
    end
  end
end
