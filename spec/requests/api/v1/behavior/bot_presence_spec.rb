# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot presence history endpoints (#94, #335): every
# action is open to Moderator and up and the service, and `id`/`set_at` are
# server-managed. A staff create takes the setter from the session and queues
# `presence_set` so the bot applies it at once.
RSpec.describe "api/v1/bot_presence behavior", type: :request do
  callers = {
    "anonymous" => [ nil, :unauthorized ],
    "a plain member" => [ -> { auth_headers_for(create(:user)) }, :forbidden ],
    "a Members role holder" => [ -> { auth_headers_for(create(:user, role_member: true)) }, :forbidden ],
    "a Regulars role holder" => [ -> { auth_headers_for(create(:user, role_regular: true)) }, :forbidden ],
    "a Moderator" => [ -> { auth_headers_for(create(:user, role_moderator: true)) }, :allowed ],
    "an Admin" => [ -> { auth_headers_for(create(:user, :admin)) }, :allowed ],
    "a Superadmin" => [ -> { auth_headers_for(create(:user), is_dev: true) }, :allowed ],
    "the service" => [ -> { service_headers }, :allowed ]
  }

  describe "access by role" do
    callers.each do |label, (headers_for, outcome)|
      context "as #{label}" do
        let(:headers) { headers_for ? instance_exec(&headers_for) : {} }
        let(:allowed) { outcome == :allowed }

        it "#{outcome == :allowed ? 'lists' : 'cannot list'} the presence history" do
          create(:bot_presence_entry)

          get "/api/v1/bot_presence", headers: headers

          expect(response).to have_http_status(allowed ? :ok : outcome)
          expect(json.fetch("data").length).to be >= 1 if allowed
        end

        it "#{outcome == :allowed ? 'reads' : 'cannot read'} the latest presence" do
          create(:bot_presence_entry)

          get "/api/v1/bot_presence/latest", headers: headers

          expect(response).to have_http_status(allowed ? :ok : outcome)
        end

        it "#{outcome == :allowed ? 'sets' : 'cannot set'} the presence" do
          expect {
            post "/api/v1/bot_presence", params: { data: { activity_name: "Chrono Trigger" } },
              headers: headers, as: :json
          }.to change(BotPresenceHistory, :count).by(allowed ? 1 : 0)

          expect(response).to have_http_status(allowed ? :created : outcome)
        end
      end
    end
  end

  describe "POST /api/v1/bot_presence as staff" do
    let(:moderator) { create(:user, role_moderator: true, username: "modname") }

    it "records the setter from the session, never the body" do
      post "/api/v1/bot_presence",
        params: { data: { activity_name: "Golden Sun", set_by_user_id: "999", set_by_username: "spoof" } },
        headers: auth_headers_for(moderator), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "activity_name" => "Golden Sun",
        "set_by_user_id" => moderator.user_id,
        "set_by_username" => "modname"
      )
    end

    it "queues presence_set for the bot with a plain summary" do
      expect {
        post "/api/v1/bot_presence", params: { data: { activity_name: "Golden Sun" } },
          headers: auth_headers_for(moderator), as: :json
      }.to change(BotJob, :count).by(1)

      job = BotJob.last
      expect(job.kind).to eq("presence_set")
      expect(job.payload).to eq("activity_name" => "Golden Sun")
      expect(job.summary).to eq('Set the bot\'s presence to "Golden Sun"')
      expect(job.requested_by_user_id).to eq(moderator.user_id)
      expect(json.fetch("meta")).to eq("presence_job_id" => job.id)
    end

    {
      "a blank activity_name" => { activity_name: "   " },
      "no activity_name" => { set_by_username: "spoof" },
      "an activity_name over Discord's #{BotPresenceHistory::STAFF_NAME_MAX} characters" =>
        { activity_name: "x" * (BotPresenceHistory::STAFF_NAME_MAX + 1) }
    }.each do |label, data|
      it "422s for #{label}, queueing nothing" do
        expect {
          post "/api/v1/bot_presence", params: { data: data }, headers: auth_headers_for(moderator), as: :json
        }.not_to change(BotPresenceHistory, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(BotJob.count).to eq(0)
      end
    end

    it "accepts a #{BotPresenceHistory::STAFF_NAME_MAX} character name, trimmed" do
      name = "x" * BotPresenceHistory::STAFF_NAME_MAX
      post "/api/v1/bot_presence", params: { data: { activity_name: "  #{name}  " } },
        headers: auth_headers_for(moderator), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "activity_name")).to eq(name)
      expect(BotJob.sole.payload).to eq("activity_name" => name)
    end

    it "queues nothing when the write fails" do
      expect {
        post "/api/v1/bot_presence", params: { data: { activity_name: "x" * 2000 } },
          headers: auth_headers_for(moderator), as: :json
      }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/bot_presence as the service" do
    it "queues no job, since the bot already applied it" do
      expect {
        post "/api/v1/bot_presence", params: { data: { activity_name: "Bot side" } },
          headers: service_headers, as: :json
      }.not_to change(BotJob, :count)

      expect(json.fetch("meta")).to eq("presence_job_id" => nil)
    end
  end
  describe "GET /api/v1/bot_presence" do
    it "lists entries newest first without the surrogate id" do
      BotPresenceHistory.delete_all
      older = create(:bot_presence_entry, set_at: 2.hours.ago)
      newer = create(:bot_presence_entry, set_at: 1.hour.ago)

      get "/api/v1/bot_presence", headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |e| e.fetch("activity_name") }
      expect(names).to eq([ newer.activity_name, older.activity_name ])
      expect(json.fetch("data").first).to include(
        "activity_name" => newer.activity_name,
        "set_by_user_id" => nil,
        "set_by_username" => nil
      )
      expect(json.fetch("data").first).not_to have_key("id")
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "caps the page size at 50 even when more is requested" do
      create(:bot_presence_entry)

      get "/api/v1/bot_presence", params: { per: 100 }, headers: service_headers

      expect(json.dig("meta", "per")).to eq(50)
    end

    it "supports the bot's limit alias" do
      BotPresenceHistory.delete_all
      create(:bot_presence_entry, set_at: 2.hours.ago)
      create(:bot_presence_entry, set_at: 1.hour.ago)

      get "/api/v1/bot_presence", params: { limit: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("meta")).to include("per" => 1, "pages" => 2)
    end

    it "forbids a regular user" do
      get "/api/v1/bot_presence", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/bot_presence"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/bot_presence/latest" do
    it "returns the most recent entry" do
      BotPresenceHistory.delete_all
      create(:bot_presence_entry, set_at: 2.hours.ago)
      newest = create(:bot_presence_entry, set_at: 1.hour.ago)

      get "/api/v1/bot_presence/latest", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("activity_name" => newest.activity_name)
    end

    it "returns null when no entries exist" do
      BotPresenceHistory.delete_all

      get "/api/v1/bot_presence/latest", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => nil)
    end

    it "forbids a regular user" do
      get "/api/v1/bot_presence/latest", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/bot_presence/latest"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/bot_presence" do
    let(:payload) { { data: { activity_name: "Golden Sun", set_by_user_id: "42", set_by_username: "iso" } } }

    it "records an entry with a server-stamped set_at" do
      expect {
        post "/api/v1/bot_presence", params: payload, headers: service_headers, as: :json
      }.to change(BotPresenceHistory, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "activity_name" => "Golden Sun",
        "set_by_user_id" => "42",
        "set_by_username" => "iso"
      )
      expect(json.dig("data", "set_at")).to be_present
    end

    it "ignores client-sent id and set_at (server-managed)" do
      post "/api/v1/bot_presence",
        params: { data: { activity_name: "Stamped", id: 424_242, set_at: "2000-01-01T00:00:00Z" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      record = BotPresenceHistory.find_by!(activity_name: "Stamped")
      expect(record.id).not_to eq(424_242)
      expect(record.set_at).to be > 1.day.ago
    end

    it "422s when activity_name exceeds the column limit" do
      post "/api/v1/bot_presence",
        params: { data: { activity_name: "x" * 2000 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s without an activity_name" do
      post "/api/v1/bot_presence", params: { data: { set_by_user_id: "42" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/bot_presence", params: { activity_name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/bot_presence", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(BotPresenceHistory, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/bot_presence", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
