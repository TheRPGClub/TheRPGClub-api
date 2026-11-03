# frozen_string_literal: true

require "rails_helper"

# Live events (web parity 2, #336): a Moderator creates one on the site and a
# `live_event_create` bot job makes the forum thread and the Discord
# scheduled event, recording each id back here so a retry skips what is done.
RSpec.describe "api/v1/live_events behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:moderator) { create(:user, role_moderator: true) }
  let(:moderator_headers) { auth_headers_for(moderator) }
  let(:starts_at) { 2.days.from_now.change(usec: 0) }
  let(:ends_at) { starts_at + 2.hours }

  def event_params(**overrides)
    { topic: "Chrono Trigger speedrun", starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
      image_url: "https://example.com/banner.png" }.merge(overrides)
  end

  def create_event(headers: moderator_headers, **overrides)
    post "/api/v1/live_events", params: { data: event_params(**overrides) }, headers: headers, as: :json
  end

  describe "POST /api/v1/live_events with an image URL" do
    it "saves the event as queued and queues live_event_create with its id" do
      freeze_time do
        create_event

        expect(response).to have_http_status(:created)
        event = LiveEvent.sole
        expect(json.fetch("data")).to eq(
          "id" => event.id, "topic" => "Chrono Trigger speedrun",
          "starts_at" => starts_at.utc.iso8601(3), "ends_at" => ends_at.utc.iso8601(3),
          "image_url" => "https://example.com/banner.png", "status" => "queued",
          "discord_thread_id" => nil, "discord_event_id" => nil,
          "created_by_user_id" => moderator.user_id, "bot_job_id" => BotJob.sole.id,
          "created_at" => Time.current.utc.iso8601(3), "updated_at" => Time.current.utc.iso8601(3)
        )
        job = BotJob.sole
        expect(job).to have_attributes(
          kind: "live_event_create", payload: { "live_event_id" => event.id },
          summary: 'Create the live event "Chrono Trigger speedrun" (forum thread and Discord event)',
          requested_by_user_id: moderator.user_id
        )
      end
    end

    it "takes no image at all, as the bot allows" do
      create_event(image_url: nil)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "image_url")).to be_nil
    end

    it "lets the service create one with no creator" do
      create_event(headers: service_headers)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "created_by_user_id")).to be_nil
      expect(BotJob.sole.requested_by_user_id).to be_nil
    end

    {
      "a blank topic" => [ { topic: "  " }, "Topic can't be blank" ],
      "a topic over 100 characters" => [ { topic: "x" * 101 }, "Topic is too long" ],
      "a missing start" => [ { starts_at: nil }, "Starts at can't be blank" ],
      "an end before the start" => [ { ends_at: 1.day.from_now.iso8601 }, "Ends at must be after the start" ],
      "an end equal to the start" => [ { ends_at: 2.days.from_now.change(usec: 0).iso8601 }, "Ends at must be after the start" ],
      "a start in the past" => [ { starts_at: 1.minute.ago.iso8601, ends_at: 1.hour.from_now.iso8601 },
        "Starts at must be in the future" ],
      "a non-http image URL" => [ { image_url: "ftp://example.com/banner.png" }, "Image url must be an http or https URL" ],
      "an image URL that is not a URL" => [ { image_url: "not a url" }, "Image url must be an http or https URL" ]
    }.each do |label, (overrides, message)|
      it "422s for #{label}, queueing nothing" do
        freeze_time do
          create_event(**overrides)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json.fetch("error")).to include(message)
          expect(LiveEvent.count).to eq(0)
          expect(BotJob.count).to eq(0)
        end
      end
    end

    it "401s without a session" do
      create_event(headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    {
      "a plain member" => {},
      "a Members role holder" => { role_member: true },
      "a Regulars role holder" => { role_regular: true }
    }.each do |label, flags|
      it "403s for #{label}" do
        create_event(headers: auth_headers_for(create(:user, **flags)))

        expect(response).to have_http_status(:forbidden)
        expect(LiveEvent.count).to eq(0)
        expect(BotJob.count).to eq(0)
      end
    end

    {
      "an Admin" => [ { role_admin: true }, {} ],
      "a Superadmin" => [ {}, { is_dev: true } ]
    }.each do |label, (flags, token)|
      it "lets #{label} create one" do
        create_event(headers: auth_headers_for(create(:user, **flags), **token))

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "POST /api/v1/live_events with an uploaded image" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:uploads) { [] }
    let(:authorize_response) do
      [ 200, {}, { authorizationToken: "b2-auth", apiInfo: { storageApi: { apiUrl: "https://b2.example.test" } } }.to_json ]
    end
    let(:upload) do
      Rack::Test::UploadedFile.new(StringIO.new("png-bytes"), "image/png", original_filename: "banner.png")
    end
    let(:backblaze_env) do
      { "BACKBLAZE_KEY_ID" => "key", "BACKBLAZE_APPLICATION_KEY" => "secret", "BACKBLAZE_BUCKET_ID" => "bucket",
        "BACKBLAZE_PUBLIC_BASE_URL" => "https://cdn.example.test/club" }
    end

    # Backblaze is stubbed through Faraday's test adapter, so the real client
    # runs without touching the network.
    around do |example|
      original_env = backblaze_env.keys.to_h { |key| [ key, ENV[key] ] }
      backblaze_env.each { |key, value| ENV[key] = value }
      original_connection = Faraday.default_connection
      Faraday.default_connection = Faraday.new { |builder| builder.adapter(:test, stubs) }

      example.run
    ensure
      Faraday.default_connection = original_connection
      original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    before do
      stubs.get(Backblaze::Client::AUTHORIZE_URL) { authorize_response }
      stubs.get("https://b2.example.test/b2api/v4/b2_get_upload_url") do
        [ 200, {}, { uploadUrl: "https://upload.example.test/up", authorizationToken: "up-auth" }.to_json ]
      end
      stubs.post("https://upload.example.test/up") do |env|
        uploads << { name: env.request_headers["X-Bz-File-Name"], type: env.request_headers["Content-Type"],
                     body: env.request_body }
        [ 200, {}, { fileId: "f1" }.to_json ]
      end
    end

    def upload_event(file: upload, headers: moderator_headers, **overrides)
      post "/api/v1/live_events", params: { data: event_params(image_url: nil, **overrides).compact.merge(image: file) },
        headers: headers
    end

    it "stores the image in Backblaze and saves its public URL" do
      upload_event

      expect(response).to have_http_status(:created)
      expect(uploads.size).to eq(1)
      expect(uploads.sole).to include(type: "image/png", body: "png-bytes")
      object_key = CGI.unescape(uploads.sole[:name])
      expect(object_key).to match(%r{\Alive-events/\d{14}-\h{8}\.png\z})
      expect(json.dig("data", "image_url")).to eq("https://cdn.example.test/club/#{object_key}")
      expect(LiveEvent.sole.image_url).to eq(json.dig("data", "image_url"))
      expect(BotJob.sole.payload).to eq("live_event_id" => LiveEvent.sole.id)
    end

    it "422s for a file that is not an image, uploading nothing" do
      upload_event(file: Rack::Test::UploadedFile.new(StringIO.new("text"), "text/plain", original_filename: "a.txt"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("image must be JPEG, PNG, WebP, or GIF")
      expect(uploads).to be_empty
      expect(LiveEvent.count).to eq(0)
    end

    it "422s for an image URL and a file together" do
      upload_event(image_url: "https://example.com/banner.png")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("Send an image URL or an image file, not both")
      expect(uploads).to be_empty
    end

    it "checks the event before uploading" do
      upload_event(topic: "")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(uploads).to be_empty
    end

    context "when Backblaze refuses the upload" do
      let(:authorize_response) { [ 403, {}, { message: "bad key" }.to_json ] }

      it "502s, saving nothing" do
        upload_event

        expect(response).to have_http_status(:bad_gateway)
        expect(json.fetch("error")).to eq("backblaze_request_failed")
        expect(LiveEvent.count).to eq(0)
        expect(BotJob.count).to eq(0)
      end
    end

    it "422s when Backblaze has no public URL configured" do
      ENV.delete("BACKBLAZE_PUBLIC_BASE_URL")

      upload_event

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("backblaze_not_configured")
      expect(uploads).to be_empty
    end
  end

  # Saved directly: the start-in-future rule only applies on create.
  def saved_event(**attrs)
    LiveEvent.create!({ topic: "Stream", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour,
                        created_by_user_id: moderator.user_id }.merge(attrs))
  end

  staff_readers = {
    "a Moderator" => [ { role_moderator: true }, {} ],
    "an Admin" => [ { role_admin: true }, {} ],
    "a Superadmin" => [ {}, { is_dev: true } ]
  }
  non_staff = {
    "a plain member" => {},
    "a Members role holder" => { role_member: true },
    "a Regulars role holder" => { role_regular: true }
  }

  describe "GET /api/v1/live_events" do
    it "lists events newest first, paginated" do
      older = travel_to(2.days.ago) { saved_event(topic: "Older") }
      newer = saved_event(topic: "Newer", status: "created", discord_thread_id: "111", discord_event_id: "222")

      get "/api/v1/live_events", headers: moderator_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").pluck("id")).to eq([ newer.id, older.id ])
      expect(json.fetch("data").first).to include(
        "topic" => "Newer", "status" => "created", "discord_thread_id" => "111", "discord_event_id" => "222"
      )
      expect(json.fetch("meta")).to include("page" => 1)

      get "/api/v1/live_events?per=1&page=2", headers: moderator_headers
      expect(json.fetch("data").pluck("id")).to eq([ older.id ])
    end

    (staff_readers.merge("the service" => nil)).each do |label, (flags, token)|
      it "lets #{label} list them" do
        saved_event
        headers = flags.nil? ? service_headers : auth_headers_for(create(:user, **flags), **token)

        get "/api/v1/live_events", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data").size).to eq(1)
      end
    end

    it "401s without a session" do
      get "/api/v1/live_events"

      expect(response).to have_http_status(:unauthorized)
    end

    non_staff.each do |label, flags|
      it "403s for #{label}" do
        get "/api/v1/live_events", headers: auth_headers_for(create(:user, **flags))

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/live_events/:id" do
    let(:event) { saved_event(discord_thread_id: "111", status: "thread_created") }

    (staff_readers.merge("the service" => nil)).each do |label, (flags, token)|
      it "lets #{label} read one" do
        headers = flags.nil? ? service_headers : auth_headers_for(create(:user, **flags), **token)

        get "/api/v1/live_events/#{event.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("id" => event.id, "status" => "thread_created",
          "discord_thread_id" => "111", "discord_event_id" => nil)
      end
    end

    it "404s for an unknown event" do
      get "/api/v1/live_events/0", headers: moderator_headers

      expect(response).to have_http_status(:not_found)
    end

    it "401s without a session" do
      get "/api/v1/live_events/#{event.id}"

      expect(response).to have_http_status(:unauthorized)
    end

    non_staff.each do |label, flags|
      it "403s for #{label}" do
        get "/api/v1/live_events/#{event.id}", headers: auth_headers_for(create(:user, **flags))

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/live_events/:id" do
    let(:event) { saved_event }

    def record(data, headers: service_headers)
      patch "/api/v1/live_events/#{event.id}", params: { data: data }, headers: headers, as: :json
    end

    it "lets the bot record the thread, then the event, so a retry can skip them" do
      record({ discord_thread_id: "1300000000000000001", status: "thread_created" })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("discord_thread_id" => "1300000000000000001",
        "discord_event_id" => nil, "status" => "thread_created")

      record({ discord_event_id: "1300000000000000002", status: "created" })

      expect(json.fetch("data")).to include("discord_thread_id" => "1300000000000000001",
        "discord_event_id" => "1300000000000000002", "status" => "created")
      expect(event.reload).to have_attributes(status: "created", discord_event_id: "1300000000000000002")
    end

    it "records a failure" do
      record({ status: "failed" })

      expect(response).to have_http_status(:ok)
      expect(event.reload.status).to eq("failed")
    end

    it "updates an event whose start has passed" do
      past = travel_to(2.days.ago) { saved_event }
      patch "/api/v1/live_events/#{past.id}", params: { data: { status: "created" } }, headers: service_headers,
        as: :json

      expect(response).to have_http_status(:ok)
    end

    it "ignores fields other than the ids and status" do
      record({ topic: "Renamed", discord_thread_id: "5" })

      expect(response).to have_http_status(:ok)
      expect(event.reload).to have_attributes(topic: "Stream", discord_thread_id: "5")
    end

    {
      "an unknown status" => { status: "done" },
      "a thread id that is not a snowflake" => { discord_thread_id: "abc" }
    }.each do |label, data|
      it "422s for #{label}" do
        record(data)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "404s for an unknown event" do
      patch "/api/v1/live_events/0", params: { data: { status: "created" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "401s without a session" do
      record({ status: "created" }, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    staff_readers.merge(non_staff.transform_values { |flags| [ flags, {} ] }).each do |label, (flags, token)|
      it "403s for #{label}" do
        record({ status: "created" }, headers: auth_headers_for(create(:user, **flags), **token))

        expect(response).to have_http_status(:forbidden)
        expect(event.reload.status).to eq("queued")
      end
    end
  end

  # The site shows a failed event with its bot job's error (bot_job_id).
  describe "when the bot job fails" do
    include ActiveSupport::Testing::TimeHelpers

    before { FileUtils.rm_f(BotJob::WorkSignal.path) }

    let!(:event) do
      create_event
      LiveEvent.sole
    end
    let(:job) { BotJob.find(event.bot_job_id) }

    def claim
      post "/api/v1/bot_jobs/claim", headers: service_headers
    end

    it "marks the event failed when the bot acks the job failed" do
      claim
      post "/api/v1/bot_jobs/#{job.id}/failed", params: { data: { error_message: "Forum channel missing" } },
        headers: service_headers, as: :json

      get "/api/v1/live_events/#{event.id}", headers: moderator_headers
      expect(json.fetch("data")).to include("status" => "failed", "bot_job_id" => job.id)
      get "/api/v1/bot_jobs/#{job.id}", headers: moderator_headers
      expect(json.dig("data", "error_message")).to eq("Forum channel missing")
    end

    it "marks the event failed when the job's last lease runs out" do
      BotJob::MAX_ATTEMPTS.times { |attempt| travel((BotJob::LEASE + 1.second) * attempt) { claim } }
      travel((BotJob::LEASE + 1.second) * BotJob::MAX_ATTEMPTS) { claim }

      expect(job.reload.status).to eq("failed")
      expect(event.reload.status).to eq("failed")
    end

    it "leaves the event alone while the job is only retried" do
      claim
      travel(BotJob::LEASE + 1.second) { claim }

      expect(event.reload.status).to eq("queued")
    end

    it "leaves another kind's failure alone" do
      other = BotJob.enqueue!(kind: "say", summary: "Say hi", payload: { live_event_id: event.id })
      claim
      post "/api/v1/bot_jobs/#{other.id}/failed", params: { data: { error_message: "nope" } },
        headers: service_headers, as: :json

      expect(event.reload.status).to eq("queued")
    end
  end
end
