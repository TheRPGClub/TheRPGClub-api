# frozen_string_literal: true

require "rails_helper"

# Superadmin start and read of the image backfill (web parity 2, #338). The
# job itself is covered by spec/jobs/gamedb/image_backfill_job_spec.rb; here
# it is only queued.
RSpec.describe "api/v1/image_backfill_runs behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:superadmin) { create(:user) }
  let(:superadmin_headers) { auth_headers_for(superadmin, is_dev: true) }

  def start(headers: superadmin_headers)
    post "/api/v1/image_backfill_runs", headers: headers, as: :json
  end

  # Every caller but the Superadmin and the service is refused.
  refused_callers = {
    "a plain member" => {},
    "a Members role holder" => { role_member: true },
    "a Regulars role holder" => { role_regular: true },
    "a Moderator" => { role_moderator: true },
    "an Admin" => { role_admin: true }
  }

  describe "POST /api/v1/image_backfill_runs" do
    it "queues a run started by the Superadmin and its job" do
      freeze_time do
        expect { start }.to have_enqueued_job(Gamedb::ImageBackfillJob)

        expect(response).to have_http_status(:created)
        run = ImageBackfillRun.sole
        expect(json.fetch("data")).to eq(
          "id" => run.id, "status" => "queued", "total" => 0, "done" => 0, "skipped" => 0, "failed" => 0,
          "started_by_user_id" => superadmin.user_id, "started_at" => nil, "finished_at" => nil,
          "last_error" => nil, "created_at" => Time.current.utc.iso8601(3),
          "updated_at" => Time.current.utc.iso8601(3)
        )
        expect(Gamedb::ImageBackfillJob).to have_been_enqueued.with(run.id)
      end
    end

    it "lets the service start a run with no starter" do
      start(headers: service_headers)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "started_by_user_id")).to be_nil
    end

    %w[queued running].each do |status|
      it "409s while a run is #{status}, queueing nothing" do
        ImageBackfillRun.create!(status: status)

        expect { start }.not_to have_enqueued_job(Gamedb::ImageBackfillJob)

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to eq("image_backfill_in_progress")
        expect(ImageBackfillRun.count).to eq(1)
      end
    end

    it "starts again once the previous run has finished" do
      ImageBackfillRun.create!(status: "completed")
      ImageBackfillRun.create!(status: "failed")

      start

      expect(response).to have_http_status(:created)
    end

    it "fails a run that stopped reporting progress and starts a new one" do
      stale = travel_to(31.minutes.ago) { ImageBackfillRun.create!(status: "running") }

      start

      expect(response).to have_http_status(:created)
      expect(stale.reload).to have_attributes(status: "failed", last_error: "Stopped reporting progress")
    end

    it "401s without a session" do
      start(headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    refused_callers.each do |label, flags|
      it "403s for #{label}" do
        expect { start(headers: auth_headers_for(create(:user, **flags))) }
          .not_to have_enqueued_job(Gamedb::ImageBackfillJob)

        expect(response).to have_http_status(:forbidden)
        expect(ImageBackfillRun.count).to eq(0)
      end
    end
  end

  describe "GET /api/v1/image_backfill_runs/latest" do
    it "returns the newest run with its progress" do
      ImageBackfillRun.create!(status: "completed", total: 9, done: 9)
      newest = ImageBackfillRun.create!(status: "running", total: 5, done: 2, skipped: 1, failed: 1,
        last_error: "Game 7: IGDB game 70 was not found", started_by_user_id: superadmin.user_id)

      get "/api/v1/image_backfill_runs/latest", headers: superadmin_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "id" => newest.id, "status" => "running", "total" => 5, "done" => 2, "skipped" => 1, "failed" => 1,
        "last_error" => "Game 7: IGDB game 70 was not found", "started_by_user_id" => superadmin.user_id
      )
    end

    it "404s before any run" do
      get "/api/v1/image_backfill_runs/latest", headers: superadmin_headers

      expect(response).to have_http_status(:not_found)
    end

    it "lets the service read it" do
      ImageBackfillRun.create!

      get "/api/v1/image_backfill_runs/latest", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "401s without a session" do
      get "/api/v1/image_backfill_runs/latest"

      expect(response).to have_http_status(:unauthorized)
    end

    refused_callers.each do |label, flags|
      it "403s for #{label}" do
        ImageBackfillRun.create!

        get "/api/v1/image_backfill_runs/latest", headers: auth_headers_for(create(:user, **flags))

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/image_backfill_runs/:id" do
    let(:run) { ImageBackfillRun.create!(status: "completed", total: 3, done: 1, skipped: 1, failed: 1) }

    it "returns the run" do
      get "/api/v1/image_backfill_runs/#{run.id}", headers: superadmin_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("id" => run.id, "status" => "completed", "total" => 3)
    end

    it "lets the service read it" do
      get "/api/v1/image_backfill_runs/#{run.id}", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "404s for an unknown run" do
      get "/api/v1/image_backfill_runs/0", headers: superadmin_headers

      expect(response).to have_http_status(:not_found)
    end

    it "401s without a session" do
      get "/api/v1/image_backfill_runs/#{run.id}"

      expect(response).to have_http_status(:unauthorized)
    end

    refused_callers.each do |label, flags|
      it "403s for #{label}" do
        get "/api/v1/image_backfill_runs/#{run.id}", headers: auth_headers_for(create(:user, **flags))

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
