# frozen_string_literal: true

require "rails_helper"

# Feature Preferences (spec #347, ticket #352): a member hides hideable
# Features from their own view of the website. Only hidden Features are
# stored, so everything is shown by default; Core Features cannot be hidden.
# Staff also have a "show Preview features" setting, on by default. Only the
# member themself may read or change their preferences.
RSpec.describe "api/v1/feature_preferences behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def path_for(user) = "/api/v1/users/#{user.user_id}/feature_preferences"

  def preferences_for(user, headers = auth_headers_for(user))
    get path_for(user), headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  describe "GET /api/v1/users/:user_id/feature_preferences" do
    it "shows every Feature by default, listing the Live hideable Features the member can hide" do
      set_all_feature_flags("live")

      expect(preferences_for(member)).to eq(
        "user_id" => member.user_id,
        "hidden" => [],
        "show_preview_features" => nil,
        "features" => [
          { "key" => "reviews", "name" => "Reviews", "state" => "live", "preview" => false, "hidden" => false,
            "website" => [ "Game page Reviews tab", "Profile reviews" ] },
          { "key" => "achievement_hub", "name" => "Achievement Hub", "state" => "live", "preview" => false,
            "hidden" => false, "website" => [ "Achievements", "Profile Achievements" ] },
          { "key" => "giveaways", "name" => "Giveaways", "state" => "live", "preview" => false, "hidden" => false,
            "website" => [ "Giveaways", "Dashboard Giveaways panel" ] },
          { "key" => "journals", "name" => "Journals", "state" => "live", "preview" => false, "hidden" => false,
            "website" => [ "Journals", "Profile Journal" ] },
          { "key" => "suggestions", "name" => "Suggestions", "state" => "live", "preview" => false,
            "hidden" => false, "website" => [ "Suggestions" ] }
        ]
      )
    end

    it "lists staff the Preview hideable Features too, badged, but never an Off one" do
      set_all_feature_flags("live")
      set_feature_flag("journals", "preview")
      set_feature_flag("giveaways", "off")
      admin = create(:user, :admin)

      data = preferences_for(admin)

      expect(data["show_preview_features"]).to be(true)
      expect(data["features"].map { |f| [ f["key"], f["state"], f["preview"] ] }).to eq([
        [ "reviews", "live", false ],
        [ "achievement_hub", "live", false ],
        [ "journals", "preview", true ],
        [ "suggestions", "live", false ]
      ])
    end

    it "lists a member no Features when no hideable Feature is Live" do
      set_all_feature_flags("live")
      %w[reviews achievement_hub giveaways].each { |key| set_feature_flag(key, "off") }
      %w[journals suggestions].each { |key| set_feature_flag(key, "preview") }

      expect(preferences_for(member)["features"]).to eq([])
    end

    it "forbids another member" do
      get path_for(member), headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids staff reading another member's preferences" do
      get path_for(member), headers: auth_headers_for(create(:user, :admin), is_dev: true)

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids the bot's service token, since preferences only shape the website" do
      get path_for(member), headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get path_for(member)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/users/:user_id/feature_preferences" do
    def patch_preferences(user, data, headers = auth_headers_for(user))
      patch path_for(user), params: { data: data }, headers: headers, as: :json
    end

    before { set_all_feature_flags("live") }

    it "hides a Feature and reads it back" do
      patch_preferences(member, { hidden: { journals: true } })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "hidden")).to eq([ "journals" ])
      expect(preferences_for(member)["hidden"]).to eq([ "journals" ])
      expect(preferences_for(member)["features"].find { |f| f["key"] == "journals" }).to include("hidden" => true)
    end

    it "shows a hidden Feature again" do
      patch_preferences(member, { hidden: { journals: true, reviews: true } })

      patch_preferences(member, { hidden: { journals: false } })

      expect(response).to have_http_status(:ok)
      expect(preferences_for(member)["hidden"]).to eq([ "reviews" ])
    end

    it "changes only the Features named, leaving the others as they were" do
      patch_preferences(member, { hidden: { giveaways: true } })

      patch_preferences(member, { hidden: { suggestions: true } })

      expect(preferences_for(member)["hidden"]).to eq([ "giveaways", "suggestions" ])
    end

    it "treats hiding an already hidden Feature as a no-op" do
      patch_preferences(member, { hidden: { journals: true } })
      patch_preferences(member, { hidden: { journals: true } })

      expect(response).to have_http_status(:ok)
      expect(preferences_for(member)["hidden"]).to eq([ "journals" ])
    end

    it "refuses to hide a Core Feature with 422 and changes nothing" do
      patch_preferences(member, { hidden: { reviews: true, game_index: true } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "game_index is a Core Feature and cannot be hidden")
      expect(preferences_for(member)["hidden"]).to eq([])
    end

    it "422s for a key that is not a Feature" do
      patch_preferences(member, { hidden: { dashboard: true } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "unknown Feature: dashboard")
    end

    it "422s when a value is not true or false" do
      patch_preferences(member, { hidden: { journals: "yes" } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "hidden.journals must be true or false")
    end

    it "422s when hidden is not an object" do
      patch_preferences(member, { hidden: [ "journals" ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "hidden must be an object of Feature keys to true or false")
    end

    it "422s when there is nothing to change" do
      patch_preferences(member, { other: true })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "hidden or show_preview_features required")
    end

    it "400s when the data envelope is missing" do
      patch path_for(member), params: { hidden: { journals: true } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids another member and changes nothing" do
      patch_preferences(member, { hidden: { journals: true } }, auth_headers_for(create(:user)))

      expect(response).to have_http_status(:forbidden)
      expect(preferences_for(member)["hidden"]).to eq([])
    end

    it "forbids the bot's service token" do
      patch_preferences(member, { hidden: { journals: true } }, service_headers)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      patch path_for(member), params: { data: { hidden: { journals: true } } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "keeps a preference through any flag change" do
      patch_preferences(member, { hidden: { journals: true } })

      set_feature_flag("journals", "off")
      set_feature_flag("journals", "preview")
      set_feature_flag("journals", "live")

      expect(preferences_for(member)["hidden"]).to eq([ "journals" ])
    end
  end

  describe "the staff show-Preview setting" do
    def patch_preferences(user, data, headers = auth_headers_for(user))
      patch path_for(user), params: { data: data }, headers: headers, as: :json
    end

    let(:admin) { create(:user, :admin) }

    it "is on by default for staff" do
      expect(preferences_for(admin)["show_preview_features"]).to be(true)
    end

    it "is turned off and back on by the staff member" do
      patch_preferences(admin, { show_preview_features: false })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "show_preview_features")).to be(false)
      expect(preferences_for(admin)["show_preview_features"]).to be(false)

      patch_preferences(admin, { show_preview_features: true })

      expect(preferences_for(admin)["show_preview_features"]).to be(true)
    end

    it "is saved alongside hidden Features in one request" do
      set_all_feature_flags("live")

      patch_preferences(admin, { hidden: { reviews: true }, show_preview_features: false })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("hidden" => [ "reviews" ], "show_preview_features" => false)
    end

    it "is available to a Superadmin" do
      superadmin = create(:user)

      patch_preferences(superadmin, { show_preview_features: false }, auth_headers_for(superadmin, is_dev: true))

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "show_preview_features")).to be(false)
    end

    it "is refused for a member who is not staff, with 422" do
      patch_preferences(member, { show_preview_features: false })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "show_preview_features is only for Admins and Superadmins")
    end

    it "is refused for a Moderator" do
      moderator = create(:user, role_moderator: true)

      patch_preferences(moderator, { show_preview_features: false })

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when it is not true or false" do
      patch_preferences(admin, { show_preview_features: "no" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "show_preview_features must be true or false")
    end
  end
end
