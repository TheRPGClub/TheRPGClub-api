# frozen_string_literal: true

require "rails_helper"

# The bot's Feature access lookup (spec #347, ticket #350): for a Discord user,
# every Feature's state and whether that user can use it. Staff (Admin or
# Superadmin) is read from the member's stored roles, so the API stays the only
# authority on who is staff even when the user acts through the bot (ADR 0005).
RSpec.describe "feature access lookup", type: :request do
  let(:dev_role) { "1500977607473103039" }
  let(:members_role) { "747520789003239530" }

  def access_for(user_id, headers: service_headers)
    get "/api/v1/users/#{user_id}/feature_access", headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def entry(data, key)
    data.fetch("features").find { |feature| feature["key"] == key }
  end

  before do
    set_all_feature_flags("live")
    set_feature_flag("journals", "preview")
    set_feature_flag("giveaways", "off")
  end

  describe "for a member" do
    let(:member) { create(:user, role_member: true) }

    it "lists all 11 Features in registry order with their state" do
      data = access_for(member.user_id)

      expect(data.fetch("features").map { |f| [ f["key"], f["state"] ] }).to eq([
        [ "game_index", "live" ],
        [ "voting_gotm", "live" ],
        [ "backlog", "live" ],
        [ "collection", "live" ],
        [ "now_playing", "live" ],
        [ "game_completions", "live" ],
        [ "reviews", "live" ],
        [ "achievement_hub", "live" ],
        [ "giveaways", "off" ],
        [ "journals", "preview" ],
        [ "suggestions", "live" ]
      ])
    end

    it "can use Live Features only" do
      data = access_for(member.user_id)

      expect(data).to include("user_id" => member.user_id, "staff" => false)
      expect(entry(data, "reviews")).to eq(
        "key" => "reviews", "name" => "Reviews", "state" => "live", "can_use" => true, "preview" => false
      )
      expect(entry(data, "journals")).to include("can_use" => false, "preview" => false)
      expect(entry(data, "giveaways")).to include("can_use" => false, "preview" => false)
    end
  end

  describe "for a Moderator" do
    it "is not staff, so cannot use a Preview Feature" do
      moderator = create(:user, role_moderator: true, role_member: true)

      data = access_for(moderator.user_id)

      expect(data).to include("staff" => false)
      expect(entry(data, "journals")).to include("can_use" => false, "preview" => false)
      expect(entry(data, "reviews")).to include("can_use" => true)
    end
  end

  describe "for an Admin" do
    let(:admin) { create(:user, :admin) }

    it "can use Live and Preview Features, marking Preview ones" do
      data = access_for(admin.user_id)

      expect(data).to include("staff" => true)
      expect(entry(data, "reviews")).to include("can_use" => true, "preview" => false)
      expect(entry(data, "journals")).to include("state" => "preview", "can_use" => true, "preview" => true)
    end

    it "cannot use an Off Feature" do
      expect(entry(access_for(admin.user_id), "giveaways")).to include("state" => "off", "can_use" => false)
    end
  end

  describe "for a Superadmin who holds only the dev role" do
    let(:superadmin) { create(:user, role_dev: true) }

    it "is staff, so can use a Preview Feature" do
      data = access_for(superadmin.user_id)

      expect(data).to include("staff" => true)
      expect(entry(data, "journals")).to include("can_use" => true, "preview" => true)
      expect(entry(data, "giveaways")).to include("can_use" => false)
    end
  end

  describe "with the dev role kept current by the member role sync" do
    def report_roles(user, role_ids)
      put "/api/v1/users/#{user.user_id}/roles", params: { data: { role_ids: role_ids } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "makes a member staff once the bot reports the dev role" do
      member = create(:user, role_member: true)

      report_roles(member, [ members_role, dev_role ])

      expect(access_for(member.user_id)).to include("staff" => true)
    end

    it "stops treating a member as staff once the dev role is gone" do
      superadmin = create(:user, role_dev: true)

      report_roles(superadmin, [ members_role ])

      data = access_for(superadmin.user_id)
      expect(data).to include("staff" => false)
      expect(entry(data, "journals")).to include("can_use" => false)
    end

    it "takes the dev role from a member upsert's role_ids too" do
      member = create(:user)

      post "/api/v1/users/upsert", params: { data: { discord_id: member.user_id, role_ids: [ dev_role ] } },
        headers: service_headers, as: :json

      expect(access_for(member.user_id)).to include("staff" => true)
    end
  end

  describe "for a Discord user with no member record" do
    it "is not staff and can use Live Features only" do
      data = access_for("999999999999999999")

      expect(data).to include("user_id" => "999999999999999999", "staff" => false)
      expect(entry(data, "reviews")).to include("can_use" => true)
      expect(entry(data, "journals")).to include("can_use" => false)
    end
  end

  describe "access" do
    let(:member) { create(:user, role_member: true) }

    it "is restricted to the bot's service token" do
      get "/api/v1/users/#{member.user_id}/feature_access", headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/users/#{member.user_id}/feature_access", headers: auth_headers_for(create(:user, :admin))
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/users/#{member.user_id}/feature_access", headers: auth_headers_for(member, is_dev: true)
      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/users/#{member.user_id}/feature_access"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
