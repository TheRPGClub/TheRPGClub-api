# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the public reminders endpoints: CRUD is open to any
# authenticated caller; the `due` poll endpoint is service-only.
RSpec.describe "api/v1/public_reminders behavior", type: :request do
  describe "GET /api/v1/public_reminders" do
    it "lists reminders ordered by due_at with the documented fields" do
      later = create(:public_reminder, due_at: 3.days.from_now)
      sooner = create(:public_reminder, due_at: 1.day.from_now)

      get "/api/v1/public_reminders", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |r| r.fetch("reminder_id") }
      expect(ids.index(sooner.reminder_id)).to be < ids.index(later.reminder_id)
      body = json.fetch("data").find { |r| r["reminder_id"] == sooner.reminder_id }
      expect(body).to include(
        "channel_id" => sooner.channel_id,
        "message" => sooner.message,
        "enabled" => true,
        "recur_every" => nil,
        "recur_unit" => nil
      )
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "filters by enabled" do
      on = create(:public_reminder, enabled: true)
      off = create(:public_reminder, enabled: false)

      get "/api/v1/public_reminders", params: { enabled: "false" }, headers: service_headers

      ids = json.fetch("data").map { |r| r.fetch("reminder_id") }
      expect(ids).to include(off.reminder_id)
      expect(ids).not_to include(on.reminder_id)
    end

    it "requires authentication" do
      get "/api/v1/public_reminders"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/public_reminders/due" do
    it "returns only enabled, past-due reminders, oldest first, unpaginated" do
      RpgClubPublicReminder.delete_all
      due_old = create(:public_reminder, due_at: 2.days.ago)
      due_new = create(:public_reminder, due_at: 1.hour.ago)
      create(:public_reminder, due_at: 1.day.from_now)
      create(:public_reminder, due_at: 2.days.ago, enabled: false)

      get "/api/v1/public_reminders/due", headers: service_headers

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |r| r.fetch("reminder_id") }
      expect(ids).to eq([ due_old.reminder_id, due_new.reminder_id ])
      expect(json).not_to have_key("meta")
    end

    it "forbids a regular user" do
      get "/api/v1/public_reminders/due", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids even an admin (service-only)" do
      get "/api/v1/public_reminders/due", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/public_reminders/due"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/public_reminders/:id" do
    it "returns the reminder" do
      reminder = create(:public_reminder)

      get "/api/v1/public_reminders/#{reminder.reminder_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "reminder_id" => reminder.reminder_id,
        "message" => reminder.message
      )
    end

    it "404s for an unknown id" do
      get "/api/v1/public_reminders/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/public_reminders" do
    let(:payload) do
      { data: { channel_id: "123456", message: "Weekly vote!", due_at: 2.days.from_now.iso8601,
        recur_every: 7, recur_unit: "days", created_by: "42" } }
    end

    it "creates a reminder for any authenticated caller" do
      expect {
        post "/api/v1/public_reminders", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.to change(RpgClubPublicReminder, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "channel_id" => "123456",
        "message" => "Weekly vote!",
        "recur_every" => 7,
        "recur_unit" => "days",
        "created_by" => "42",
        "enabled" => true
      )
      expect(json.dig("data", "reminder_id")).to be_present
    end

    it "422s when the message exceeds the column limit" do
      post "/api/v1/public_reminders",
        params: { data: { channel_id: "1", message: "x" * 3000, due_at: 1.day.from_now.iso8601 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when a required column is missing" do
      pending "possible bug: RpgClubPublicReminder has no presence validations, so a missing " \
        "NOT NULL column (message/due_at) surfaces as an unrescued NotNullViolation (500) " \
        "instead of the documented 422"

      post "/api/v1/public_reminders",
        params: { data: { channel_id: "123456" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/public_reminders", params: { message: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/public_reminders", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/public_reminders/:id" do
    it "partially updates the reminder" do
      reminder = create(:public_reminder)

      patch "/api/v1/public_reminders/#{reminder.reminder_id}",
        params: { data: { message: "updated text", enabled: false } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("message" => "updated text", "enabled" => false)
      expect(reminder.reload.message).to eq("updated text")
      expect(reminder.enabled).to be(false)
    end

    it "supports PUT as an alias" do
      reminder = create(:public_reminder)

      put "/api/v1/public_reminders/#{reminder.reminder_id}",
        params: { data: { message: "via put" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(reminder.reload.message).to eq("via put")
    end

    it "404s for an unknown id" do
      patch "/api/v1/public_reminders/999999999",
        params: { data: { message: "nope" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/public_reminders/:id" do
    it "deletes the reminder" do
      reminder = create(:public_reminder)

      delete "/api/v1/public_reminders/#{reminder.reminder_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubPublicReminder.exists?(reminder.reminder_id)).to be(false)
    end

    it "404s for an unknown id" do
      delete "/api/v1/public_reminders/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
