# frozen_string_literal: true

require "rails_helper"

# Behavior specs for changing a News Item's News Category (spec #367,
# ticket #369): the bot, acting for a member who used "Change news
# category", asks the API to move the item to another News Category. The
# item's author and staff may; anyone else is refused. Only staff may give
# an unsorted imported News Item its first category.
RSpec.describe "api/v1/news_items/:message_id/category behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:author) { create(:user, role_member: true) }
  let(:admin) { create(:user, role_admin: true) }
  let(:item) do
    create(:news_item, :copied, author_id: author.user_id, category_key: "general", picked_category_key: "general")
  end

  def change_category(message_id, category_key, acting: author)
    put "/api/v1/news_items/#{message_id}/category", headers: service_headers, as: :json,
      params: { data: { acting_user_id: acting.respond_to?(:user_id) ? acting.user_id : acting,
                        category_key: category_key } }
  end

  it "lets the author change their News Item's category, keeping the bot's pick and the News Copy location" do
    change_category(item.message_id, "rumours")

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include(
      "message_id" => item.message_id, "category_key" => "rumours", "picked_category_key" => "general",
      "news_copy" => { "message_id" => item.news_copy_message_id, "thread_id" => item.news_copy_thread_id }
    )
    expect(json.fetch("meta")).to eq("changed" => true, "previous_category_key" => "general")
  end

  it "records who changed the category and when, leaving the bot's pick as it was" do
    freeze_time do
      change_category(item.message_id, "industry")

      expect(item.reload).to have_attributes(category_key: "industry", picked_category_key: "general",
        category_changed_by: author.user_id, category_changed_at: Time.current)
    end
  end

  it "lets an Admin or Superadmin change anyone's News Item" do
    superadmin = create(:user, role_dev: true)

    change_category(item.message_id, "hardware", acting: admin)
    expect(response).to have_http_status(:ok)
    change_category(item.message_id, "emulation", acting: superadmin)
    expect(response).to have_http_status(:ok)

    expect(item.reload).to have_attributes(category_key: "emulation", category_changed_by: superadmin.user_id)
  end

  it "refuses any other member, a Moderator included, and changes nothing" do
    others = [ create(:user, role_member: true), create(:user, role_moderator: true), "999999999999999999" ]

    others.each do |other|
      change_category(item.message_id, "rumours", acting: other)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end
    expect(item.reload).to have_attributes(category_key: "general", category_changed_by: nil,
      category_changed_at: nil)
  end

  describe "the News Hub Feature Flag (docs/adr/0005)" do
    it "refuses everyone while Off, the author and staff included, and changes nothing" do
      set_feature_flag("news_hub", "off")

      [ author, admin ].each do |acting|
        change_category(item.message_id, "rumours", acting: acting)

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq("error" => "feature_unavailable")
      end
      expect(item.reload.category_key).to eq("general")
    end

    it "refuses an author who is not staff while Preview, and lets staff change it" do
      set_feature_flag("news_hub", "preview")

      change_category(item.message_id, "rumours")
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "feature_unavailable")
      expect(item.reload.category_key).to eq("general")

      change_category(item.message_id, "rumours", acting: admin)
      expect(response).to have_http_status(:ok)
      expect(item.reload.category_key).to eq("rumours")
    end

    it "lets the author change it while Live" do
      set_feature_flag("news_hub", "live")

      change_category(item.message_id, "rumours")

      expect(response).to have_http_status(:ok)
    end
  end

  it "changes nothing when the News Item is already in that category" do
    change_category(item.message_id, "rumours", acting: admin)
    changed_at = item.reload.category_changed_at

    change_category(item.message_id, "rumours")

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("category_key" => "rumours")
    expect(json.fetch("meta")).to eq("changed" => false, "previous_category_key" => "rumours")
    expect(item.reload).to have_attributes(category_changed_by: admin.user_id, category_changed_at: changed_at)
  end

  it "answers a News Item with no News Copy with a null location" do
    uncopied = create(:news_item, author_id: author.user_id, category_key: "general")

    change_category(uncopied.message_id, "industry")

    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "news_copy")).to be_nil
  end

  it "lets the author of an imported News Item change its category" do
    imported = create(:news_item, :copied, author_id: author.user_id, origin: "import", category_key: "general")

    change_category(imported.message_id, "emulation")

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("origin" => "import", "category_key" => "emulation",
      "picked_category_key" => nil)
  end

  describe "an imported News Item staff have not sorted" do
    let(:unsorted) { create(:news_item, author_id: author.user_id, origin: "import", category_key: nil) }

    it "refuses its author, since only staff sort the News Import, and changes nothing" do
      change_category(unsorted.message_id, "releases")

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
      expect(unsorted.reload).to have_attributes(category_key: nil, category_changed_by: nil)
    end

    it "lets staff give it its first category" do
      change_category(unsorted.message_id, "releases", acting: admin)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("meta")).to eq("changed" => true, "previous_category_key" => nil)
      expect(unsorted.reload).to have_attributes(category_key: "releases", category_changed_by: admin.user_id)
    end
  end

  it "rejects an unknown News Category and changes nothing" do
    change_category(item.message_id, "piracy")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.fetch("error")).to include("is not a News Category")
    expect(item.reload.category_key).to eq("general")
  end

  it "is not found for a message that is not a recorded News Item" do
    change_category("5500000000000000005", "rumours")

    expect(response).to have_http_status(:not_found)
  end

  it "is a bad request without an acting member or a category" do
    put "/api/v1/news_items/#{item.message_id}/category", headers: service_headers, as: :json,
      params: { data: { category_key: "rumours" } }
    expect(response).to have_http_status(:bad_request)
    expect(json).to eq("error" => "acting_user_id required")

    put "/api/v1/news_items/#{item.message_id}/category", headers: service_headers, as: :json,
      params: { data: { acting_user_id: author.user_id } }
    expect(response).to have_http_status(:bad_request)
    expect(item.reload.category_key).to eq("general")
  end

  it "is service-only, even for the author or staff signed in" do
    [ author, admin ].each do |user|
      put "/api/v1/news_items/#{item.message_id}/category", headers: auth_headers_for(user), as: :json,
        params: { data: { acting_user_id: user.user_id, category_key: "rumours" } }

      expect(response).to have_http_status(:forbidden)
    end
    expect(item.reload.category_key).to eq("general")
  end

  it "lists the News Channel's bot commands in the News Hub Feature's coverage, for staff changing its flag" do
    get "/api/v1/features", headers: auth_headers_for(admin)

    news_hub = json.fetch("data").find { |feature| feature["key"] == "news_hub" }
    expect(news_hub.dig("coverage", "bot")).to eq([ "/news", "Change news category (context menu)", "/news-import" ])
  end
end
