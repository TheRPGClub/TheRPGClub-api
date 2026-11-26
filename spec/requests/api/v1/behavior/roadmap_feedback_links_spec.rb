# frozen_string_literal: true

require "rails_helper"

# Feedback linked to Roadmap Items (spec api#505, ticket api#508): staff set
# an item's linked Feedback; a Feedback sits on at most one item; the Roadmap
# lists each item's Feedback and the Feedback Board shows the badge.
RSpec.describe "api/v1/roadmap feedback links behavior", type: :request do
  let(:admin) { create(:user, :admin, role_member: true) }
  let(:member) { create(:user, role_member: true) }
  let(:launch) { create(:roadmap_milestone, name: "Launch", position: 1) }
  let(:item) { create(:roadmap_item, milestone: launch) }

  def link(target, ids, user: admin)
    patch "/api/v1/roadmap/items/#{target.id}", params: { data: { feedback_ids: ids } }, as: :json,
      headers: auth_headers_for(user)
  end

  def roadmap_items(user = admin)
    get "/api/v1/roadmap", headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
    json.dig("data", "milestones").flat_map { |m| m["items"] } + json.dig("data", "reached").flat_map { |m| m["items"] }
  end

  def feedback_row(feedback, user = member)
    get "/api/v1/feedback/#{feedback.feedback_id}", headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  describe "linking" do
    it "sets an item's linked Feedback and lists it on the Roadmap" do
      bug = create(:feedback, kind: "bug_report", title: "Crash on save")
      idea = create(:feedback, title: "Dark mode", status: "approved")

      link(item, [ idea.feedback_id, bug.feedback_id ])

      expect(response).to have_http_status(:ok)
      expected = [
        { "id" => bug.feedback_id, "title" => "Crash on save", "kind" => "bug_report", "status" => "pending",
          "done" => false },
        { "id" => idea.feedback_id, "title" => "Dark mode", "kind" => "suggestion", "status" => "approved",
          "done" => false }
      ]
      expect(json.dig("data", "feedback")).to eq(expected)
      expect(roadmap_items(member).find { |i| i["id"] == item.id }["feedback"]).to eq(expected)
    end

    it "replaces the links with the list sent, and an empty list clears them" do
      kept = create(:feedback)
      dropped = create(:feedback)
      link(item, [ kept.feedback_id, dropped.feedback_id ])

      link(item, [ kept.feedback_id ])
      expect(json.dig("data", "feedback").map { |f| f["id"] }).to eq([ kept.feedback_id ])

      link(item, [])
      expect(json.dig("data", "feedback")).to eq([])
    end

    it "leaves the links alone when feedback_ids isn't sent" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])

      patch "/api/v1/roadmap/items/#{item.id}", params: { data: { title: "Renamed" } }, as: :json,
        headers: auth_headers_for(admin)

      expect(json.dig("data", "feedback").map { |f| f["id"] }).to eq([ feedback.feedback_id ])
    end

    it "moves a Feedback already linked to another item, so it is never on two" do
      feedback = create(:feedback)
      other = create(:roadmap_item, milestone: launch)
      link(other, [ feedback.feedback_id ])

      link(item, [ feedback.feedback_id ])

      expect(response).to have_http_status(:ok)
      items = roadmap_items
      expect(items.find { |i| i["id"] == item.id }["feedback"].map { |f| f["id"] }).to eq([ feedback.feedback_id ])
      expect(items.find { |i| i["id"] == other.id }["feedback"]).to eq([])
    end

    it "refuses unknown Feedback and a malformed list, changing nothing" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])

      link(item, [ feedback.feedback_id, 0 ])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("feedback_not_found")

      link(item, "nope")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_feedback_ids")

      expect(roadmap_items.find { |i| i["id"] == item.id }["feedback"].map { |f| f["id"] })
        .to eq([ feedback.feedback_id ])
    end

    it "links Feedback when an item is created" do
      feedback = create(:feedback)

      post "/api/v1/roadmap/items", params: { data: { milestone_id: launch.id, title: "Roadmap", blurb: "A page.",
                                                       feedback_ids: [ feedback.feedback_id ] } },
        as: :json, headers: auth_headers_for(admin)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "feedback").map { |f| f["id"] }).to eq([ feedback.feedback_id ])
    end

    it "lets only Admins and Superadmins link" do
      feedback = create(:feedback)

      link(item, [ feedback.feedback_id ], user: member)

      expect(response).to have_http_status(:forbidden)
      expect(roadmap_items.find { |i| i["id"] == item.id }["feedback"]).to eq([])
    end

    it "removes an item's links when the item is deleted" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])

      delete "/api/v1/roadmap/items/#{item.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(feedback_row(feedback)["roadmap"]).to be_nil
      link(create(:roadmap_item, milestone: launch), [ feedback.feedback_id ])
      expect(response).to have_http_status(:ok)
    end

    it "sends no notices" do
      feedback = create(:feedback)

      expect { link(item, [ feedback.feedback_id ]) }.not_to change(BotJob, :count)
    end
  end

  describe "the Feedback badge" do
    it "names the item's current Milestone" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])

      expect(feedback_row(feedback)["roadmap"]).to eq(
        "item_id" => item.id, "milestone_name" => "Launch", "shipped" => false
      )

      later = create(:roadmap_milestone, name: "After launch", position: 2)
      put "/api/v1/roadmap/items/#{item.id}/move", params: { data: { milestone_id: later.id, position: 1 } },
        as: :json, headers: auth_headers_for(admin)
      expect(feedback_row(feedback)["roadmap"]).to include("milestone_name" => "After launch")
    end

    it "says shipped once the item is Shipped" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])

      post "/api/v1/roadmap/items/#{item.id}/ship", headers: auth_headers_for(admin)

      expect(feedback_row(feedback)["roadmap"]).to include("shipped" => true)
    end

    it "is on every row of the Feedback list, null for unlinked Feedback" do
      linked = create(:feedback)
      unlinked = create(:feedback)
      link(item, [ linked.feedback_id ])

      get "/api/v1/feedback", params: { per: 500 }, headers: auth_headers_for(member)

      rows = json.fetch("data").index_by { |row| row["feedback_id"] }
      expect(rows[linked.feedback_id]["roadmap"]).to eq(
        "item_id" => item.id, "milestone_name" => "Launch", "shipped" => false
      )
      expect(rows[unlinked.feedback_id]).to include("roadmap" => nil)
    end

    it "is null for a member while the Feature is Preview or Off, and for everyone when Off" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])

      set_feature_flag("roadmap", "preview")
      expect(feedback_row(feedback)["roadmap"]).to be_nil
      expect(feedback_row(feedback, admin)["roadmap"]).to include("item_id" => item.id)

      set_feature_flag("roadmap", "off")
      expect(feedback_row(feedback, admin)["roadmap"]).to be_nil
      get "/api/v1/feedback", headers: auth_headers_for(member)
      expect(json.fetch("data").find { |row| row["feedback_id"] == feedback.feedback_id }["roadmap"]).to be_nil
    end

    it "is null for a member who hid the Roadmap" do
      feedback = create(:feedback)
      link(item, [ feedback.feedback_id ])
      patch "/api/v1/users/#{member.user_id}/feature_preferences", params: { data: { hidden: { roadmap: true } } },
        as: :json, headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)

      expect(feedback_row(feedback)["roadmap"]).to be_nil
    end
  end
end
