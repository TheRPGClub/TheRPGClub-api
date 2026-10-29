# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the server-side Completionator import workflow (#291):
# CSV upload on create, advance (match, auto-add, auto-skip), and the item
# endpoints match / add_completion / update_completion / skip /
# igdb_candidates. Ports the bot's completionator-workflow.service.ts.
RSpec.describe "api/v1/completionator import workflow", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "POST /api/v1/users/:user_id/completionator_imports with csv_text" do
    let(:csv_text) do
      "Name,Platform,Region,Type,Time,Date\n" \
        "Chrono Trigger,Super Nintendo,North America,Core Game,25h:30m:00s,3/7/2021\n" \
        "\"Final Fantasy VII, Remake\",PlayStation 4,,Completionated,,\n"
    end

    it "parses the export server-side into pending items" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: csv_text, source_filename: "export.csv" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("total_count" => 2, "source_filename" => "export.csv", "status" => "active")

      items = RpgClubCompletionatorImport.find(json.dig("data", "import_id")).items.order(:row_index)
      expect(items.map(&:row_index)).to eq([ 1, 2 ])
      expect(items.first).to have_attributes(
        game_title: "Chrono Trigger", platform_name: "Super Nintendo", region_name: "North America",
        source_type: "Core Game", time_text: "25h:30m:00s", completion_type: "Main Story", status: "pending"
      )
      expect(items.first.playtime_hrs).to eq(25.5)
      expect(items.first.completed_at.to_date).to eq(Date.new(2021, 3, 7))
      expect(items.second).to have_attributes(game_title: "Final Fantasy VII, Remake", completion_type: "Completionist")
    end

    it "422s with invalid_csv on a malformed or empty export, creating nothing" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completionator_imports",
          params: { data: { csv_text: "Name,Platform,Region,Type,Time,Date\n\"broken,PC,,,,\n" } },
          headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubCompletionatorImport, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "invalid_csv")
      expect(json.fetch("message")).to be_present

      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: "Name,Platform,Region,Type,Time,Date\n" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "invalid_csv")
    end

    it "forbids another user" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: csv_text } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
