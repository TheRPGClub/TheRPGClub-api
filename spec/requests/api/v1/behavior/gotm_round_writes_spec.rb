# frozen_string_literal: true

require "rails_helper"

# Round-level writes for GOTM and NR-GOTM (#331): an Admin adds a whole round
# in one transaction, and staff creates and edits queue `gotm_cache_reload`
# so the bot reloads its in-memory round data.
RSpec.describe "GOTM and NR-GOTM round writes", type: :request do
  {
    "gotm" => { path: "/api/v1/gotm_entries", model: GotmEntry, id: "gotm_id", label: "GOTM", factory: :gotm_entry },
    "nr_gotm" => { path: "/api/v1/nr_gotm_entries", model: NrGotmEntry, id: "nr_gotm_id", label: "NR-GOTM",
                   factory: :nr_gotm_entry }
  }.each do |category, cfg|
    describe "POST #{cfg[:path]}/rounds" do
      let(:round) { SecureRandom.random_number(1_000_000_000) }
      let(:games) { create_list(:game, 2) }
      let(:payload) do
        { data: { round_number: round, month_year: "November 2026",
                  games: [ { gamedb_game_id: games[0].game_id, reddit_url: "https://reddit.example/r/a" },
                           { gamedb_game_id: games[1].game_id } ] } }
      end

      callers = {
        "anonymous" => [ nil, :unauthorized ],
        "a plain member" => [ -> { auth_headers_for(create(:user)) }, :forbidden ],
        "a Members role holder" => [ -> { auth_headers_for(create(:user, role_member: true)) }, :forbidden ],
        "a Regulars role holder" => [ -> { auth_headers_for(create(:user, role_regular: true)) }, :forbidden ],
        "a Moderator" => [ -> { auth_headers_for(create(:user, role_moderator: true)) }, :forbidden ],
        "an Admin" => [ -> { auth_headers_for(create(:user, :admin)) }, :created ],
        "a Superadmin" => [ -> { auth_headers_for(create(:user), is_dev: true) }, :created ],
        "the service" => [ -> { service_headers }, :created ]
      }

      callers.each do |label, (headers_for, status)|
        it "answers #{status} to #{label}" do
          headers = headers_for ? instance_exec(&headers_for) : {}

          post "#{cfg[:path]}/rounds", params: payload, headers: headers, as: :json

          expect(response).to have_http_status(status)
          expect(cfg[:model].where(round_number: round).count).to eq(status == :created ? 2 : 0)
        end
      end

      it "inserts every game in order and returns the round's entries" do
        post "#{cfg[:path]}/rounds", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

        expect(response).to have_http_status(:created)
        data = json.fetch("data")
        expect(data.map { |e| e.slice("round_number", "month_year", "game_index", "gamedb_game_id", "reddit_url") })
          .to eq([
            { "round_number" => round, "month_year" => "November 2026", "game_index" => 0,
              "gamedb_game_id" => games[0].game_id, "reddit_url" => "https://reddit.example/r/a" },
            { "round_number" => round, "month_year" => "November 2026", "game_index" => 1,
              "gamedb_game_id" => games[1].game_id, "reddit_url" => nil }
          ])
        expect(data.first).to have_key(cfg[:id])
      end

      it "queues gotm_cache_reload for the round, requested by the Admin" do
        admin = create(:user, :admin)

        expect {
          post "#{cfg[:path]}/rounds", params: payload, headers: auth_headers_for(admin), as: :json
        }.to change(BotJob, :count).by(1)

        job = BotJob.last
        expect(json.fetch("meta")).to eq("reload_job_id" => job.id)
        expect(job.kind).to eq("gotm_cache_reload")
        expect(job.payload).to eq("category" => category, "round_number" => round)
        expect(job.summary).to eq("Reload #{cfg[:label]} round #{round} (November 2026) in the bot: round added")
        expect(job.requested_by_user_id).to eq(admin.user_id)
      end

      it "queues the reload with no requester for the service" do
        post "#{cfg[:path]}/rounds", params: payload, headers: service_headers, as: :json

        expect(BotJob.last).to have_attributes(kind: "gotm_cache_reload", requested_by_user_id: nil)
        expect(json.fetch("meta")).to eq("reload_job_id" => BotJob.last.id)
      end

      it "rejects the whole round when one game is invalid" do
        payload[:data][:games] << { gamedb_game_id: 999_999_999 }

        expect {
          post "#{cfg[:path]}/rounds", params: payload, headers: service_headers, as: :json
        }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("Game 3: GameDB game 999999999 does not exist")
        expect(cfg[:model].where(round_number: round)).to be_empty
      end

      it "rolls back the earlier games when a later one fails to save" do
        payload[:data][:games][1][:reddit_url] = "https://reddit.example/#{'x' * 3000}"

        expect {
          post "#{cfg[:path]}/rounds", params: payload, headers: service_headers, as: :json
        }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(cfg[:model].where(round_number: round)).to be_empty
      end

      it "rejects a game without a GameDB id" do
        payload[:data][:games] << { reddit_url: "https://reddit.example/r/x" }

        post "#{cfg[:path]}/rounds", params: payload, headers: service_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("Game 3: gamedb_game_id is required")
        expect(cfg[:model].where(round_number: round)).to be_empty
      end

      it "rejects a round that already has entries" do
        create(cfg[:factory], round_number: round, game_index: 0)

        post "#{cfg[:path]}/rounds", params: payload, headers: service_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("#{cfg[:label]} round #{round} already exists")
        expect(cfg[:model].where(round_number: round).count).to eq(1)
      end

      it "rejects a round with no games" do
        payload[:data][:games] = []

        post "#{cfg[:path]}/rounds", params: payload, headers: service_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("games must be a non-empty list")
      end

      it "rejects a missing month_year or a non-positive round number" do
        post "#{cfg[:path]}/rounds", params: { data: payload[:data].except(:month_year) },
          headers: service_headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("month_year is required")

        post "#{cfg[:path]}/rounds", params: { data: payload[:data].merge(round_number: 0) },
          headers: service_headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("round_number must be a positive integer")
      end

      it "400s when the data envelope is missing" do
        post "#{cfg[:path]}/rounds", params: { round_number: round }, headers: service_headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    describe "POST #{cfg[:path]} (one game)" do
      let(:round_number) { SecureRandom.random_number(1_000_000) + 1 }
      let(:body) do
        { data: { round_number: round_number, month_year: "October 2026", game_index: 1,
                  gamedb_game_id: create(:game).game_id } }
      end

      it "queues the reload for a staff create" do
        admin = create(:user, :admin)

        post cfg[:path], params: body, headers: auth_headers_for(admin), as: :json

        expect(response).to have_http_status(:created)
        expect(BotJob.sole).to have_attributes(kind: "gotm_cache_reload", requested_by_user_id: admin.user_id,
          payload: { "category" => category, "round_number" => round_number },
          summary: "Reload #{cfg[:label]} round #{round_number} (October 2026) in the bot: game 2 added")
      end

      it "queues nothing for the bot's own create through the service" do
        expect { post cfg[:path], params: body, headers: service_headers, as: :json }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:created)
      end
    end

    describe "DELETE #{cfg[:path]}/:id" do
      let!(:entry) { create(cfg[:factory], game_index: 0, month_year: "October 2026") }

      it "queues the reload for a staff delete" do
        admin = create(:user, :admin)

        delete "#{cfg[:path]}/#{entry.public_send(cfg[:id])}", headers: auth_headers_for(admin)

        expect(response).to have_http_status(:ok)
        expect(cfg[:model].exists?(entry.public_send(cfg[:id]))).to be(false)
        expect(BotJob.sole).to have_attributes(kind: "gotm_cache_reload", requested_by_user_id: admin.user_id,
          payload: { "category" => category, "round_number" => entry.round_number },
          summary: "Reload #{cfg[:label]} round #{entry.round_number} (October 2026) in the bot: game 1 removed")
      end

      it "queues nothing for the bot's own delete through the service" do
        expect {
          delete "#{cfg[:path]}/#{entry.public_send(cfg[:id])}", headers: service_headers
        }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH #{cfg[:path]}/:id" do
      let(:entry) { create(cfg[:factory], game_index: 1, month_year: "October 2026") }
      let(:new_game) { create(:game) }

      callers = {
        "anonymous" => [ nil, :unauthorized ],
        "a plain member" => [ -> { auth_headers_for(create(:user)) }, :forbidden ],
        "a Members role holder" => [ -> { auth_headers_for(create(:user, role_member: true)) }, :forbidden ],
        "a Regulars role holder" => [ -> { auth_headers_for(create(:user, role_regular: true)) }, :forbidden ],
        "a Moderator" => [ -> { auth_headers_for(create(:user, role_moderator: true)) }, :forbidden ],
        "an Admin" => [ -> { auth_headers_for(create(:user, :admin)) }, :ok ],
        "a Superadmin" => [ -> { auth_headers_for(create(:user), is_dev: true) }, :ok ],
        "the service" => [ -> { service_headers }, :ok ]
      }

      callers.each do |label, (headers_for, status)|
        it "answers #{status} to #{label}" do
          headers = headers_for ? instance_exec(&headers_for) : {}

          patch "#{cfg[:path]}/#{entry.public_send(cfg[:id])}",
            params: { data: { reddit_url: "https://reddit.example/r/new" } }, headers: headers, as: :json

          expect(response).to have_http_status(status)
          expect(entry.reload.reddit_url == "https://reddit.example/r/new").to be(status == :ok)
        end
      end

      it "keeps the game and Reddit URL fields and queues the reload for a staff edit" do
        admin = create(:user, :admin)

        patch "#{cfg[:path]}/#{entry.public_send(cfg[:id])}",
          params: { data: { gamedb_game_id: new_game.game_id, reddit_url: "https://reddit.example/r/new" } },
          headers: auth_headers_for(admin), as: :json

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("gamedb_game_id" => new_game.game_id,
          "reddit_url" => "https://reddit.example/r/new")
        job = BotJob.last
        expect(json.fetch("meta")).to eq("reload_job_id" => job.id)
        expect(job.kind).to eq("gotm_cache_reload")
        expect(job.payload).to eq("category" => category, "round_number" => entry.round_number)
        expect(job.summary)
          .to eq("Reload #{cfg[:label]} round #{entry.round_number} (October 2026) in the bot: game 2 edited")
        expect(job.requested_by_user_id).to eq(admin.user_id)
      end

      it "queues nothing for the bot's own edits through the service" do
        expect {
          patch "#{cfg[:path]}/#{entry.public_send(cfg[:id])}",
            params: { data: { voting_results_message_id: "123" } }, headers: service_headers, as: :json
        }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("meta")).to eq("reload_job_id" => nil)
      end

      it "returns the reload job id for a PUT too" do
        put "#{cfg[:path]}/#{entry.public_send(cfg[:id])}",
          params: { data: { reddit_url: "https://reddit.example/r/put" } },
          headers: auth_headers_for(create(:user, :admin)), as: :json

        expect(response).to have_http_status(:ok)
        expect(json.fetch("meta")).to eq("reload_job_id" => BotJob.sole.id)
      end

      it "queues nothing when the edit is invalid" do
        expect {
          patch "#{cfg[:path]}/#{entry.public_send(cfg[:id])}",
            params: { data: { reddit_url: "x" * 10_000 } }, headers: auth_headers_for(create(:user, :admin)), as: :json
        }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
