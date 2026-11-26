# frozen_string_literal: true

require "rails_helper"

# Staff editing of the Roadmap (spec api#505, ticket api#507): Milestones and
# Roadmap Items, Shipped and Reached. Admins and Superadmins only.
RSpec.describe "api/v1/roadmap editing behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :admin, role_member: true) }

  def call(verb, path, data = nil, user: admin, headers: nil)
    send(verb, "/api/v1/roadmap#{path}", params: data && { data: data }, as: :json,
      headers: headers || auth_headers_for(user))
  end

  def roadmap
    get "/api/v1/roadmap", headers: auth_headers_for(admin)
    json.fetch("data")
  end

  def open_ids = roadmap["milestones"].map { |m| m["id"] }
  def item_ids(milestone) = milestone.reload.items.map(&:id)

  describe "Milestones" do
    it "creates a Milestone at the end of the order" do
      create(:roadmap_milestone, position: 4)

      call :post, "/milestones", { name: " Launch ", blurb: "First things", target_date: "2026-12-15",
                                   date_precision: "month" }

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("name" => "Launch", "blurb" => "First things", "target_date" => "2026-12-01",
        "date_precision" => "month", "position" => 5, "reached_at" => nil, "items" => [])
    end

    it "creates a TBA Milestone by default and refuses a dated TBA one" do
      call :post, "/milestones", { name: "In The Future" }
      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("target_date" => nil, "date_precision" => "tba", "position" => 1)

      call :post, "/milestones", { name: "Odd", target_date: "2027-01-01" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates a Milestone's name, blurb and date, and nothing else" do
      milestone = create(:roadmap_milestone, name: "Launch", position: 2)

      call :patch, "/milestones/#{milestone.id}", { name: "Launch day", blurb: "Soon", target_date: "2027-02-10",
                                                     date_precision: "quarter", position: 9,
                                                     reached_at: "2026-11-01T00:00:00Z" }

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("name" => "Launch day", "blurb" => "Soon", "target_date" => "2027-01-01",
        "date_precision" => "quarter", "position" => 2, "reached_at" => nil)
    end

    it "deletes an empty Milestone" do
      milestone = create(:roadmap_milestone)

      call :delete, "/milestones/#{milestone.id}"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq("id" => milestone.id, "deleted" => true)
      expect(RoadmapMilestone.exists?(milestone.id)).to be(false)
    end

    it "refuses to delete a Milestone that still has Roadmap Items" do
      milestone = create(:roadmap_milestone)
      create(:roadmap_item, milestone: milestone)

      call :delete, "/milestones/#{milestone.id}"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("milestone_has_items")
      expect(json["message"]).to match(/move or delete its Roadmap Items first/i)
      expect(RoadmapMilestone.exists?(milestone.id)).to be(true)
    end

    it "reorders the open Milestones from the full id list, keeping Reached ones' places" do
      a = create(:roadmap_milestone, position: 1)
      reached = create(:roadmap_milestone, position: 2, reached_at: 1.day.ago)
      b = create(:roadmap_milestone, position: 3)
      c = create(:roadmap_milestone, position: 4)

      call :put, "/milestones/order", { milestone_ids: [ c.id, a.id, b.id ] }

      expect(response).to have_http_status(:ok)
      expect(json["data"]["milestones"].map { |m| m["id"] }).to eq([ c.id, a.id, b.id ])

      call :delete, "/milestones/#{reached.id}/reach"
      expect(open_ids).to eq([ c.id, reached.id, a.id, b.id ])
    end

    it "refuses a Milestone order that does not name every open Milestone exactly once" do
      a = create(:roadmap_milestone, position: 1)
      b = create(:roadmap_milestone, position: 2)
      reached = create(:roadmap_milestone, position: 3, reached_at: 1.day.ago)

      [ [ a.id ], [ a.id, a.id ], [ a.id, b.id, reached.id ], [ a.id, "x" ] ].each do |ids|
        call :put, "/milestones/order", { milestone_ids: ids }

        expect(response).to have_http_status(:unprocessable_content), "accepted #{ids.inspect}"
        expect(json["error"]).to eq("invalid_order")
      end
      expect(open_ids).to eq([ a.id, b.id ])
    end
  end

  describe "Roadmap Items" do
    let(:launch) { create(:roadmap_milestone, name: "Launch", position: 1) }
    let(:later) { create(:roadmap_milestone, name: "Later", position: 2) }

    it "creates an item at the end of its Milestone" do
      create(:roadmap_item, milestone: launch, position: 3)

      call :post, "/items", { milestone_id: launch.id, title: "Roadmap page", blurb: "See what's coming.",
                              area: "website", github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-api/issues/505",
                              shipped_at: "2026-11-01T00:00:00Z" }

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("milestone_id" => launch.id, "title" => "Roadmap page", "area" => "website",
        "github_issue_url" => "https://github.com/TheRPGClub/TheRPGClub-api/issues/505", "position" => 4,
        "shipped_at" => nil)
    end

    it "refuses an item without a blurb, or in a missing or Reached Milestone" do
      call :post, "/items", { milestone_id: launch.id, title: "No blurb" }
      expect(response).to have_http_status(:unprocessable_content)

      call :post, "/items", { milestone_id: 0, title: "Lost", blurb: "Nowhere." }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("milestone_not_found")

      reached = create(:roadmap_milestone, reached_at: 1.day.ago)
      call :post, "/items", { milestone_id: reached.id, title: "Late", blurb: "Too late." }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("milestone_reached")
    end

    it "updates an item's words, area and GitHub issue, and nothing else" do
      item = create(:roadmap_item, milestone: launch, position: 1, area: "bot")

      call :patch, "/items/#{item.id}", { title: "New title", blurb: "New blurb.", area: nil,
                                          github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-www/issues/1",
                                          milestone_id: later.id, position: 7, shipped_at: "2026-11-01T00:00:00Z" }

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("title" => "New title", "blurb" => "New blurb.", "area" => nil,
        "github_issue_url" => "https://github.com/TheRPGClub/TheRPGClub-www/issues/1", "milestone_id" => launch.id,
        "position" => 1, "shipped_at" => nil)
    end

    it "deletes an item" do
      item = create(:roadmap_item, milestone: launch)

      call :delete, "/items/#{item.id}"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq("id" => item.id, "deleted" => true)
      expect(item_ids(launch)).to eq([])
    end

    it "reorders a Milestone's items from the full id list" do
      a = create(:roadmap_item, milestone: launch, position: 1)
      b = create(:roadmap_item, milestone: launch, position: 2)
      c = create(:roadmap_item, milestone: launch, position: 3)

      call :put, "/milestones/#{launch.id}/items/order", { item_ids: [ c.id, a.id, b.id ] }

      expect(response).to have_http_status(:ok)
      expect(json["data"]["milestones"].first["items"].map { |i| i["id"] }).to eq([ c.id, a.id, b.id ])
    end

    it "refuses an item order that does not name every item of the Milestone exactly once" do
      a = create(:roadmap_item, milestone: launch, position: 1)
      b = create(:roadmap_item, milestone: launch, position: 2)
      elsewhere = create(:roadmap_item, milestone: later)

      [ [ a.id ], [ a.id, a.id ], [ a.id, b.id, elsewhere.id ] ].each do |ids|
        call :put, "/milestones/#{launch.id}/items/order", { item_ids: ids }

        expect(response).to have_http_status(:unprocessable_content), "accepted #{ids.inspect}"
        expect(json["error"]).to eq("invalid_order")
      end
      expect(item_ids(launch)).to eq([ a.id, b.id ])
    end

    it "moves an item to another open Milestone at a position" do
      moving = create(:roadmap_item, milestone: launch, position: 1)
      stay = create(:roadmap_item, milestone: launch, position: 2)
      x = create(:roadmap_item, milestone: later, position: 1)
      y = create(:roadmap_item, milestone: later, position: 2)

      call :put, "/items/#{moving.id}/move", { milestone_id: later.id, position: 2 }

      expect(response).to have_http_status(:ok)
      expect(item_ids(later)).to eq([ x.id, moving.id, y.id ])
      expect(item_ids(launch)).to eq([ stay.id ])
      expect(later.reload.items.map(&:position)).to eq([ 1, 2, 3 ])
    end

    it "moves an item within its Milestone, and past the end to the end" do
      a = create(:roadmap_item, milestone: launch, position: 1)
      b = create(:roadmap_item, milestone: launch, position: 2)
      c = create(:roadmap_item, milestone: launch, position: 3)

      call :put, "/items/#{a.id}/move", { milestone_id: launch.id, position: 2 }
      expect(item_ids(launch)).to eq([ b.id, a.id, c.id ])

      call :put, "/items/#{b.id}/move", { milestone_id: launch.id, position: 99 }
      expect(item_ids(launch)).to eq([ a.id, c.id, b.id ])
    end

    it "refuses moving an item into a Reached Milestone, or to a bad position" do
      item = create(:roadmap_item, milestone: launch, position: 1, shipped_at: 1.day.ago)
      reached = create(:roadmap_milestone, reached_at: 1.day.ago)

      call :put, "/items/#{item.id}/move", { milestone_id: reached.id, position: 1 }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("milestone_reached")

      call :put, "/items/#{item.id}/move", { milestone_id: later.id, position: 0 }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_position")

      expect(item.reload.milestone_id).to eq(launch.id)
    end

    it "ships and un-ships an item" do
      item = create(:roadmap_item, milestone: launch)

      freeze_time do
        call :post, "/items/#{item.id}/ship"
        expect(response).to have_http_status(:ok)
        expect(json["data"]["shipped_at"]).to eq(Time.current.as_json)
      end

      shipped_at = item.reload.shipped_at
      travel 1.day do
        call :post, "/items/#{item.id}/ship"
        expect(item.reload.shipped_at).to eq(shipped_at)
      end

      call :delete, "/items/#{item.id}/ship"
      expect(response).to have_http_status(:ok)
      expect(json["data"]["shipped_at"]).to be_nil
    end

    it "refuses un-shipping an item of a Reached Milestone" do
      reached = create(:roadmap_milestone, reached_at: 1.day.ago)
      item = create(:roadmap_item, milestone: reached, shipped_at: 2.days.ago)

      call :delete, "/items/#{item.id}/ship"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("milestone_reached")
      expect(item.reload.shipped_at).to be_present
    end
  end

  describe "Reaching a Milestone" do
    let!(:launch) { create(:roadmap_milestone, name: "Launch", position: 1) }
    let!(:later) { create(:roadmap_milestone, name: "Later", position: 2) }
    let!(:future) { create(:roadmap_milestone, name: "In The Future", position: 3) }

    it "moves unshipped items to the end of the next open Milestone and keeps only Shipped ones" do
      shipped = create(:roadmap_item, milestone: launch, position: 1, shipped_at: 1.day.ago)
      late_a = create(:roadmap_item, milestone: launch, position: 2)
      late_b = create(:roadmap_item, milestone: launch, position: 3)
      waiting = create(:roadmap_item, milestone: later, position: 1)

      freeze_time do
        call :post, "/milestones/#{launch.id}/reach"

        expect(response).to have_http_status(:ok)
        expect(json["data"]["milestones"].map { |m| m["id"] }).to eq([ later.id, future.id ])
        expect(json["data"]["reached"].first).to include("id" => launch.id, "reached_at" => Time.current.as_json)
      end
      expect(item_ids(launch)).to eq([ shipped.id ])
      expect(item_ids(later)).to eq([ waiting.id, late_a.id, late_b.id ])
    end

    it "moves unshipped items to the chosen Milestone" do
      late = create(:roadmap_item, milestone: launch)

      call :post, "/milestones/#{launch.id}/reach", { destination_milestone_id: future.id }

      expect(response).to have_http_status(:ok)
      expect(item_ids(future)).to eq([ late.id ])
    end

    it "defaults to an earlier open Milestone when none comes after it" do
      late = create(:roadmap_item, milestone: future)

      call :post, "/milestones/#{future.id}/reach"

      expect(response).to have_http_status(:ok)
      expect(item_ids(later)).to eq([ late.id ])
    end

    it "refuses a destination that is itself, Reached or missing" do
      create(:roadmap_item, milestone: launch)
      reached = create(:roadmap_milestone, position: 4, reached_at: 1.day.ago)

      [ launch.id, reached.id, 0 ].each do |destination|
        call :post, "/milestones/#{launch.id}/reach", { destination_milestone_id: destination }

        expect(response).to have_http_status(:unprocessable_content), "accepted #{destination}"
        expect(json["error"]).to eq("invalid_destination")
      end
      expect(launch.reload.reached_at).to be_nil
    end

    it "refuses a bad destination even when nothing would move" do
      create(:roadmap_item, milestone: launch, shipped_at: 1.day.ago)

      call :post, "/milestones/#{launch.id}/reach", { destination_milestone_id: 0 }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_destination")
      expect(launch.reload.reached_at).to be_nil
    end

    it "refuses a body whose data isn't an object" do
      call :post, "/milestones/#{launch.id}/reach", "soon"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_data")
      expect(launch.reload.reached_at).to be_nil
    end

    it "refuses when unshipped items have no open Milestone to go to" do
      later.destroy!
      future.destroy!
      create(:roadmap_item, milestone: launch)

      call :post, "/milestones/#{launch.id}/reach"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("no_destination")
      expect(launch.reload.reached_at).to be_nil
    end

    it "reaches the last Milestone when all its items are Shipped" do
      later.destroy!
      future.destroy!
      create(:roadmap_item, milestone: launch, shipped_at: 1.day.ago)

      call :post, "/milestones/#{launch.id}/reach"

      expect(response).to have_http_status(:ok)
      expect(launch.reload.reached_at).to be_present
    end

    it "refuses reaching a Reached Milestone, and un-reaching an open one" do
      launch.update!(reached_at: 1.day.ago)

      call :post, "/milestones/#{launch.id}/reach"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("already_reached")

      call :delete, "/milestones/#{later.id}/reach"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("not_reached")
    end

    it "un-reaches a Milestone back to its place, its items keeping their Shipped dates" do
      shipped_at = Time.utc(2026, 11, 20)
      item = create(:roadmap_item, milestone: later, shipped_at: shipped_at)
      call :post, "/milestones/#{later.id}/reach"

      call :delete, "/milestones/#{later.id}/reach"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["milestones"].map { |m| m["id"] }).to eq([ launch.id, later.id, future.id ])
      expect(json["data"]["reached"]).to eq([])
      expect(item.reload.shipped_at).to eq(shipped_at)
    end
  end

  describe "who may edit" do
    let(:milestone) { create(:roadmap_milestone) }
    let(:item) { create(:roadmap_item, milestone: milestone) }

    def every_write
      [
        [ :post, "/milestones", { name: "New" } ],
        [ :patch, "/milestones/#{milestone.id}", { name: "Renamed" } ],
        [ :delete, "/milestones/#{milestone.id}" ],
        [ :put, "/milestones/order", { milestone_ids: [ milestone.id ] } ],
        [ :post, "/milestones/#{milestone.id}/reach" ],
        [ :delete, "/milestones/#{milestone.id}/reach" ],
        [ :put, "/milestones/#{milestone.id}/items/order", { item_ids: [ item.id ] } ],
        [ :post, "/items", { milestone_id: milestone.id, title: "New", blurb: "New." } ],
        [ :patch, "/items/#{item.id}", { title: "Renamed" } ],
        [ :delete, "/items/#{item.id}" ],
        [ :put, "/items/#{item.id}/move", { milestone_id: milestone.id, position: 1 } ],
        [ :post, "/items/#{item.id}/ship" ],
        [ :delete, "/items/#{item.id}/ship" ]
      ]
    end

    it "forbids Moderators and members every write" do
      moderator = create(:user, role_member: true, role_moderator: true)
      member = create(:user, role_member: true)

      [ moderator, member ].each do |user|
        every_write.each do |(verb, path, data)|
          call verb, path, data, user: user

          expect(response).to have_http_status(:forbidden), "#{verb} #{path} gave #{response.status}"
        end
      end
      expect(milestone.reload.name).not_to eq("Renamed")
      expect(item.reload.title).not_to eq("Renamed")
    end

    it "lets a Superadmin edit" do
      superadmin = create(:user, role_member: true)
      headers = auth_headers_for(superadmin, is_dev: true)

      call :patch, "/milestones/#{milestone.id}", { name: "Renamed" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["data"]["name"]).to eq("Renamed")
    end

    it "is not found for a member while the Feature is in Preview, and open to an Admin" do
      set_feature_flag("roadmap", "preview")

      call :post, "/milestones", { name: "New" }, user: create(:user, role_member: true)
      expect(response).to have_http_status(:not_found)

      call :post, "/milestones", { name: "New" }
      expect(response).to have_http_status(:created)
    end
  end
end
