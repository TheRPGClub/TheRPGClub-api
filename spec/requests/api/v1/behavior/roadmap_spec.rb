# frozen_string_literal: true

require "rails_helper"

# The Roadmap read (spec api#505, ticket api#506): open Milestones in staff
# order with their Roadmap Items in order, then the Reached Milestones,
# newest Reached first. Members only, behind the `roadmap` Feature.
RSpec.describe "api/v1/roadmap behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def roadmap(user = member)
    get "/api/v1/roadmap", headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  it "returns open Milestones and their Roadmap Items in staff order" do
    later = create(:roadmap_milestone, name: "After launch", position: 2,
      target_date: Date.new(2027, 1, 1), date_precision: "quarter")
    launch = create(:roadmap_milestone, name: "Launch", position: 1, blurb: "What members get first",
      target_date: Date.new(2026, 12, 1), date_precision: "month")
    future = create(:roadmap_milestone, name: "In The Future", position: 3)
    second = create(:roadmap_item, milestone: launch, title: "Roadmap page", position: 2, area: "website")
    first = create(:roadmap_item, milestone: launch, title: "Feedback Board", position: 1, area: "both",
      github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-api/issues/498", shipped_at: Time.utc(2026, 11, 20))
    create(:roadmap_item, milestone: later, title: "Bot command", position: 1, area: "bot")

    data = roadmap

    expect(data["milestones"].map { |m| m["name"] }).to eq([ "Launch", "After launch", "In The Future" ])
    expect(data["milestones"].first).to include(
      "id" => launch.id, "name" => "Launch", "blurb" => "What members get first",
      "target_date" => "2026-12-01", "date_precision" => "month", "position" => 1, "reached_at" => nil
    )
    expect(data["milestones"].first["items"]).to eq([
      { "id" => first.id, "milestone_id" => launch.id, "title" => "Feedback Board", "blurb" => first.blurb,
        "area" => "both", "github_issue_url" => "https://github.com/TheRPGClub/TheRPGClub-api/issues/498",
        "position" => 1, "shipped_at" => "2026-11-20T00:00:00.000Z" },
      { "id" => second.id, "milestone_id" => launch.id, "title" => "Roadmap page", "blurb" => second.blurb,
        "area" => "website", "github_issue_url" => nil, "position" => 2, "shipped_at" => nil }
    ])
    expect(data["milestones"].last).to include("id" => future.id, "target_date" => nil, "date_precision" => "tba",
      "items" => [])
    expect(data["reached"]).to eq([])
  end

  it "returns Reached Milestones separately, newest Reached first, with their Shipped items" do
    open = create(:roadmap_milestone, name: "Next", position: 3)
    older = create(:roadmap_milestone, name: "Beta", position: 1, reached_at: Time.utc(2026, 10, 1))
    newer = create(:roadmap_milestone, name: "Launch", position: 2, reached_at: Time.utc(2026, 11, 1))
    shipped = create(:roadmap_item, milestone: newer, position: 1, shipped_at: Time.utc(2026, 10, 30))

    data = roadmap

    expect(data["milestones"].map { |m| m["id"] }).to eq([ open.id ])
    expect(data["reached"].map { |m| m["id"] }).to eq([ newer.id, older.id ])
    expect(data["reached"].first).to include("reached_at" => "2026-11-01T00:00:00.000Z")
    expect(data["reached"].first["items"].map { |i| i["id"] }).to eq([ shipped.id ])
  end

  it "returns an empty Roadmap" do
    expect(roadmap).to eq("milestones" => [], "reached" => [])
  end

  it "refuses a Visitor" do
    get "/api/v1/roadmap"

    expect(response).to have_http_status(:unauthorized)
  end

  it "is not found for a member while the Feature is in Preview or Off, as other gated Features are" do
    %w[preview off].each do |state|
      set_feature_flag("roadmap", state)
      get "/api/v1/roadmap", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found), "member got #{response.status} in #{state}"
      expect(json).to eq("error" => "not_found")
    end
  end

  it "answers an Admin in Preview" do
    set_feature_flag("roadmap", "preview")

    expect(roadmap(create(:user, :admin))).to eq("milestones" => [], "reached" => [])
  end
end
