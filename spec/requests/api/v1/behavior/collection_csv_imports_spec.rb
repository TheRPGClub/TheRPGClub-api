# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the collection CSV import job endpoints (#163):
# owner-only create (with inline bulk item insert), the active-import resume
# lookup, show/update of the session, the status/reason summary, and the
# test_mode dry-run rollback (see TestModeRollback).
RSpec.describe "api/v1/collection_csv_imports behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "POST /api/v1/users/:user_id/collection_csv_imports" do
    let(:payload) do
      { data: {
        source_file_name: "collection.csv",
        source_file_size: 2048,
        template_version: "v2",
        test_mode: false,
        items: [
          { raw_title: "Chrono Trigger", raw_platform: "SNES", raw_ownership_type: "physical",
            raw_note: "boxed copy", raw_gamedb_id: 11, raw_igdb_id: 22 },
          { raw_title: "Suikoden II" }
        ]
      } }
    end

    it "refuses to start a second import while one is active or paused (one open import per kind)" do
      create(:collection_csv_import, user: owner, status: "paused")

      expect {
        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubCollectionCsvImport, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("user already has an active or paused import")
    end

    it "creates the import job and all row items for the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(RpgClubCollectionCsvImport, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "status" => "active",
        "current_index" => 0,
        "total_count" => 2,
        "source_file_name" => "collection.csv",
        "source_file_size" => 2048,
        "template_version" => "v2",
        "test_mode" => false
      )

      import = RpgClubCollectionCsvImport.find(json.dig("data", "import_id"))
      items = import.items.order(:row_index)
      expect(items.map(&:row_index)).to eq([ 0, 1 ])
      expect(items.map(&:status).uniq).to eq([ "pending" ])
      expect(items.first).to have_attributes(
        raw_title: "Chrono Trigger", raw_platform: "SNES", raw_ownership_type: "physical",
        raw_note: "boxed copy", raw_gamedb_id: 11, raw_igdb_id: 22
      )
    end

    it "honors an explicit row_index over the array position" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
        params: { data: { test_mode: false,
                          items: [ { raw_title: "A", row_index: 5 }, { raw_title: "B", row_index: 9 } ] } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      import = RpgClubCollectionCsvImport.find(json.dig("data", "import_id"))
      expect(import.items.order(:row_index).map(&:row_index)).to eq([ 5, 9 ])
    end

    it "persists the session row but rolls back the item inserts in test_mode" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
        params: payload.deep_merge(data: { test_mode: true }),
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("test_mode" => true, "total_count" => 2)

      import = RpgClubCollectionCsvImport.find(json.dig("data", "import_id"))
      expect(import.test_mode).to be(true)
      expect(import.total_count).to eq(2)
      expect(import.items.count).to eq(0)
    end

    it "allows the service to create on behalf of the user" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
        params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user_id")).to eq(owner.user_id)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(RpgClubCollectionCsvImport, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    # insert_all (non-bang) emits ON CONFLICT DO NOTHING, so a row_index
    # collision inside the batch is silently dropped rather than rejected;
    # total_count still reflects the submitted batch size.
    it "silently skips item rows whose row_index collides within the batch" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
        params: { data: { test_mode: false,
                          items: [ { raw_title: "First", row_index: 3 }, { raw_title: "Second", row_index: 3 } ] } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      import = RpgClubCollectionCsvImport.find(json.dig("data", "import_id"))
      expect(import.items.count).to eq(1)
      expect(import.items.sole.raw_title).to eq("First")
      expect(import.total_count).to eq(2)
    end

    it "422s when source_file_name exceeds the column limit" do
      expect {
        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: { data: { test_mode: false, source_file_name: "f" * 300 } },
          headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubCollectionCsvImport, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "defaults test_mode to false when omitted" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
        params: { data: { items: [ { raw_title: "A" } ] } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "test_mode")).to be(false)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
        params: { source_file_name: "bare.csv" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/collection_csv_imports", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context "with csv_text (server-side parsing, #290)" do
      let!(:platform) { create(:platform, platform_name: "Csvcreate Box #{SecureRandom.hex(3)}") }
      let(:csv_text) do
        "title,platform,ownership_type,note,gamedb_id,igdb_id\n" \
          "Chrono Trigger,#{platform.platform_name},physical,boxed,,\n" \
          "Example,,,EXAMPLE ROW - DELETE BEFORE IMPORT,,\n" \
          "Suikoden II,,,,42,\n"
      end

      it "parses the file and creates one pending item per importable row" do
        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: { data: { csv_text: csv_text, source_file_name: "mine.csv", test_mode: false } },
          headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:created)
        expect(json.fetch("data")).to include(
          "user_id" => owner.user_id, "status" => "active", "total_count" => 2,
          "source_file_name" => "mine.csv", "source_file_size" => csv_text.bytesize, "template_version" => "1.0"
        )

        items = RpgClubCollectionCsvImport.find(json.dig("data", "import_id")).items.order(:row_index)
        expect(items.map { |item| [ item.row_index, item.raw_title, item.status ] })
          .to eq([ [ 2, "Chrono Trigger", "pending" ], [ 4, "Suikoden II", "pending" ] ])
        expect(items.first).to have_attributes(
          raw_platform: platform.platform_name, platform_id: platform.platform_id,
          raw_ownership_type: "physical", ownership_type: "Physical", raw_note: "boxed", note: "boxed"
        )
        expect(items.second).to have_attributes(raw_gamedb_id: 42, ownership_type: "Digital", platform_id: nil)
      end

      it "422s with every row error and creates nothing when the file is invalid" do
        bad = "title,platform,gamedb_id\n,,\nGood,,\n,Nowhere Console 9000,x\n"

        expect {
          post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
            params: { data: { csv_text: bad, test_mode: false } }, headers: auth_headers_for(owner), as: :json
        }.not_to change(RpgClubCollectionCsvImport, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          "error" => "invalid_csv",
          "errors" => [
            { "row_index" => 4, "column" => "title", "message" => "Title is required." },
            { "row_index" => 4, "column" => "gamedb_id", "message" => "GameDB id must be a positive number." },
            { "row_index" => 4, "column" => "platform",
              "message" => "Platform not recognized. Use a platform name or id." }
          ]
        )
      end

      it "422s on a file over the size cap" do
        big = "title\n#{"A long title\n" * ((Api::V1::CollectionCsvImportsController::MAX_CSV_BYTES / 13) + 1)}"

        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: { data: { csv_text: big, test_mode: false } }, headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("invalid_csv")
        expect(json.fetch("errors").sole).to include("column" => "file")
      end

      it "forbids another user" do
        post "/api/v1/users/#{owner.user_id}/collection_csv_imports",
          params: { data: { csv_text: csv_text, test_mode: false } }, headers: auth_headers_for(other_user), as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/users/:user_id/collection_csv_imports/active" do
    it "returns the most recent active or paused import, even among legacy duplicates" do
      create(:collection_csv_import, user: owner, status: "completed")
      newest = create(:collection_csv_import, user: owner, status: "paused")
      # A legacy duplicate from before the one-open-import rule (#287):
      # saved without validation, so /active must still pick the newest.
      build(:collection_csv_import, user: owner, status: "active", created_at: 2.hours.ago).save!(validate: false)

      get "/api/v1/users/#{owner.user_id}/collection_csv_imports/active", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("import_id" => newest.import_id, "status" => "paused")
    end

    it "404s when the user has no active or paused import" do
      create(:collection_csv_import, user: owner, status: "completed")

      get "/api/v1/users/#{owner.user_id}/collection_csv_imports/active", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "forbids another user" do
      create(:collection_csv_import, user: owner)

      get "/api/v1/users/#{owner.user_id}/collection_csv_imports/active", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/collection_csv_imports/active"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/collection_csv_imports/:id" do
    it "shows the import to its owner" do
      import = create(:collection_csv_import, user: owner, source_file_name: "mine.csv", total_count: 4)

      get "/api/v1/collection_csv_imports/#{import.import_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "import_id" => import.import_id,
        "user_id" => owner.user_id,
        "source_file_name" => "mine.csv",
        "total_count" => 4
      )
    end

    it "allows the service" do
      import = create(:collection_csv_import, user: owner)

      get "/api/v1/collection_csv_imports/#{import.import_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "forbids another user" do
      import = create(:collection_csv_import, user: owner)

      get "/api/v1/collection_csv_imports/#{import.import_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id as the service" do
      get "/api/v1/collection_csv_imports/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "403s for an unknown id when the caller is a plain user (owner gate resolves first)" do
      get "/api/v1/collection_csv_imports/999999999", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      import = create(:collection_csv_import, user: owner)

      get "/api/v1/collection_csv_imports/#{import.import_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/collection_csv_imports/:id" do
    it "updates status and current_index for the owner" do
      import = create(:collection_csv_import, user: owner)

      patch "/api/v1/collection_csv_imports/#{import.import_id}",
        params: { data: { status: "paused", current_index: 7 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "paused", "current_index" => 7)
      expect(import.reload).to have_attributes(status: "paused", current_index: 7)
    end

    it "responds with the update but rolls it back for a test_mode import" do
      import = create(:collection_csv_import, user: owner, test_mode: true)

      patch "/api/v1/collection_csv_imports/#{import.import_id}",
        params: { data: { status: "paused", current_index: 3 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "paused", "current_index" => 3)
      expect(import.reload).to have_attributes(status: "active", current_index: 0)
    end

    it "422s on an invalid status" do
      import = create(:collection_csv_import, user: owner)

      patch "/api/v1/collection_csv_imports/#{import.import_id}",
        params: { data: { status: "bogus" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(import.reload.status).to eq("active")
    end

    it "forbids another user" do
      import = create(:collection_csv_import, user: owner)

      patch "/api/v1/collection_csv_imports/#{import.import_id}",
        params: { data: { status: "canceled" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(import.reload.status).to eq("active")
    end

    it "404s for an unknown id as the service" do
      patch "/api/v1/collection_csv_imports/999999999",
        params: { data: { status: "paused" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      import = create(:collection_csv_import, user: owner)

      patch "/api/v1/collection_csv_imports/#{import.import_id}",
        params: { data: { status: "paused" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/collection_csv_imports/:id/summary" do
    it "counts items by status and by result_reason" do
      import = create(:collection_csv_import, user: owner)
      create(:collection_csv_import_item, import: import, row_index: 0, status: "added", result_reason: "auto_match")
      create(:collection_csv_import_item, import: import, row_index: 1, status: "added", result_reason: "auto_match")
      create(:collection_csv_import_item, import: import, row_index: 2, status: "skipped", result_reason: "manual_skip")

      get "/api/v1/collection_csv_imports/#{import.import_id}/summary", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "import_id")).to eq(import.import_id)
      expect(json.dig("data", "by_status")).to eq("added" => 2, "skipped" => 1)
      expect(json.dig("data", "by_result_reason")).to eq("auto_match" => 2, "manual_skip" => 1)
    end

    it "forbids another user" do
      import = create(:collection_csv_import, user: owner)

      get "/api/v1/collection_csv_imports/#{import.import_id}/summary", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      import = create(:collection_csv_import, user: owner)

      get "/api/v1/collection_csv_imports/#{import.import_id}/summary"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
