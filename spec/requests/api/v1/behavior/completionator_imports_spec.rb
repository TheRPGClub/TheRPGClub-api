# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Completionator import job endpoints (#164): the same
# owner-only session shape as collection_csv_imports — create with inline
# bulk item insert, active-import resume lookup, show/update, a by-status
# summary — plus the test_mode dry-run rollback (see TestModeRollback).
RSpec.describe "api/v1/completionator_imports behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "POST /api/v1/users/:user_id/completionator_imports" do
    let(:payload) do
      { data: {
        source_filename: "completionator_export.csv",
        test_mode: false,
        items: [
          { game_title: "Final Fantasy VI", platform_name: "SNES", region_name: "North America",
            source_type: "Collection", time_text: "35h 30m", completed_at: "2024-03-01T00:00:00Z",
            completion_type: "Finished", playtime_hrs: 35.5 },
          { game_title: "Persona 3" }
        ]
      } }
    end

    it "creates the import job and all row items for the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completionator_imports",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(RpgClubCompletionatorImport, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "status" => "active",
        "current_index" => 0,
        "total_count" => 2,
        "source_filename" => "completionator_export.csv",
        "test_mode" => false
      )

      import = RpgClubCompletionatorImport.find(json.dig("data", "import_id"))
      items = import.items.order(:row_index)
      expect(items.map(&:row_index)).to eq([ 0, 1 ])
      expect(items.map(&:status).uniq).to eq([ "pending" ])
      expect(items.first).to have_attributes(
        game_title: "Final Fantasy VI", platform_name: "SNES", region_name: "North America",
        source_type: "Collection", time_text: "35h 30m", completion_type: "Finished", playtime_hrs: 35.5
      )
      expect(items.first.completed_at).to be_present
    end

    it "honors an explicit row_index over the array position" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { test_mode: false,
                          items: [ { game_title: "A", row_index: 4 }, { game_title: "B", row_index: 8 } ] } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      import = RpgClubCompletionatorImport.find(json.dig("data", "import_id"))
      expect(import.items.order(:row_index).map(&:row_index)).to eq([ 4, 8 ])
    end

    it "persists the session row but rolls back the item inserts in test_mode" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: payload.deep_merge(data: { test_mode: true }),
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("test_mode" => true, "total_count" => 2)

      import = RpgClubCompletionatorImport.find(json.dig("data", "import_id"))
      expect(import.test_mode).to be(true)
      expect(import.total_count).to eq(2)
      expect(import.items.count).to eq(0)
    end

    it "allows the service to create on behalf of the user" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user_id")).to eq(owner.user_id)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completionator_imports",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(RpgClubCompletionatorImport, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when source_filename exceeds the column limit" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completionator_imports",
          params: { data: { test_mode: false, source_filename: "f" * 300 } },
          headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubCompletionatorImport, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "defaults test_mode to false when omitted" do
      pending "possible bug: omitting test_mode inserts NULL (PG::NotNullViolation -> 500) " \
              "instead of applying the documented false default"

      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { items: [ { game_title: "A" } ] } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "test_mode")).to be(false)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { source_filename: "bare.csv" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/completionator_imports/active" do
    it "returns the most recent active or paused import" do
      create(:completionator_import, user: owner, status: "canceled")
      create(:completionator_import, user: owner, status: "paused", created_at: 2.hours.ago)
      newest = create(:completionator_import, user: owner, status: "active")

      get "/api/v1/users/#{owner.user_id}/completionator_imports/active", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("import_id" => newest.import_id, "status" => "active")
    end

    it "404s when the user has no active or paused import" do
      create(:completionator_import, user: owner, status: "completed")

      get "/api/v1/users/#{owner.user_id}/completionator_imports/active", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "forbids another user" do
      create(:completionator_import, user: owner)

      get "/api/v1/users/#{owner.user_id}/completionator_imports/active", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/completionator_imports/active"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/completionator_imports/:id" do
    it "shows the import to its owner" do
      import = create(:completionator_import, user: owner, source_filename: "mine.csv", total_count: 3)

      get "/api/v1/completionator_imports/#{import.import_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "import_id" => import.import_id,
        "user_id" => owner.user_id,
        "source_filename" => "mine.csv",
        "total_count" => 3
      )
    end

    it "allows the service" do
      import = create(:completionator_import, user: owner)

      get "/api/v1/completionator_imports/#{import.import_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "forbids another user" do
      import = create(:completionator_import, user: owner)

      get "/api/v1/completionator_imports/#{import.import_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id as the service" do
      get "/api/v1/completionator_imports/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      import = create(:completionator_import, user: owner)

      get "/api/v1/completionator_imports/#{import.import_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/completionator_imports/:id" do
    it "updates status and current_index for the owner" do
      import = create(:completionator_import, user: owner)

      patch "/api/v1/completionator_imports/#{import.import_id}",
        params: { data: { status: "paused", current_index: 11 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "paused", "current_index" => 11)
      expect(import.reload).to have_attributes(status: "paused", current_index: 11)
    end

    it "responds with the update but rolls it back for a test_mode import" do
      import = create(:completionator_import, user: owner, test_mode: true)

      patch "/api/v1/completionator_imports/#{import.import_id}",
        params: { data: { status: "completed", current_index: 9 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "completed", "current_index" => 9)
      expect(import.reload).to have_attributes(status: "active", current_index: 0)
    end

    it "422s on an invalid status" do
      import = create(:completionator_import, user: owner)

      patch "/api/v1/completionator_imports/#{import.import_id}",
        params: { data: { status: "bogus" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(import.reload.status).to eq("active")
    end

    it "forbids another user" do
      import = create(:completionator_import, user: owner)

      patch "/api/v1/completionator_imports/#{import.import_id}",
        params: { data: { status: "canceled" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(import.reload.status).to eq("active")
    end

    it "404s for an unknown id as the service" do
      patch "/api/v1/completionator_imports/999999999",
        params: { data: { status: "paused" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      import = create(:completionator_import, user: owner)

      patch "/api/v1/completionator_imports/#{import.import_id}",
        params: { data: { status: "paused" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/completionator_imports/:id/summary" do
    it "counts items by status" do
      import = create(:completionator_import, user: owner)
      create(:completionator_import_item, import: import, row_index: 0, status: "added")
      create(:completionator_import_item, import: import, row_index: 1, status: "added")
      create(:completionator_import_item, import: import, row_index: 2, status: "failed")

      get "/api/v1/completionator_imports/#{import.import_id}/summary", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "import_id")).to eq(import.import_id)
      expect(json.dig("data", "by_status")).to eq("added" => 2, "failed" => 1)
    end

    it "forbids another user" do
      import = create(:completionator_import, user: owner)

      get "/api/v1/completionator_imports/#{import.import_id}/summary", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      import = create(:completionator_import, user: owner)

      get "/api/v1/completionator_imports/#{import.import_id}/summary"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
