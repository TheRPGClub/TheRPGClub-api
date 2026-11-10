# frozen_string_literal: true

require "rails_helper"

# News Category Preferences (spec #355, ticket #357): a member switches News
# Categories off to leave them out of their own default view of the News Hub.
# Only switched-off categories are stored, so every News Category is in the
# default view to begin with. Only the member themself may read or change
# their preferences, and a preference never blocks a request: asking for a
# switched-off category by name still returns it.
RSpec.describe "api/v1/news_category_preferences behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def path_for(user) = "/api/v1/users/#{user.user_id}/news_category_preferences"

  def preferences_for(user, headers = auth_headers_for(user))
    get path_for(user), headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  describe "GET /api/v1/users/:user_id/news_category_preferences" do
    it "has every News Category switched on by default, listed in order" do
      expect(preferences_for(member)).to eq(
        "user_id" => member.user_id,
        "hidden" => [],
        "categories" => [
          { "key" => "announcements", "name" => "Announcements & Trailers", "position" => 1, "hidden" => false },
          { "key" => "releases", "name" => "Releases & Updates", "position" => 2, "hidden" => false },
          { "key" => "emulation", "name" => "Emulation & Preservation", "position" => 3, "hidden" => false },
          { "key" => "industry", "name" => "Industry", "position" => 4, "hidden" => false },
          { "key" => "hardware", "name" => "Hardware & Platforms", "position" => 5, "hidden" => false },
          { "key" => "rumours", "name" => "Rumours & Leaks", "position" => 6, "hidden" => false },
          { "key" => "general", "name" => "General", "position" => 7, "hidden" => false }
        ]
      )
    end

    it "ignores a stored preference for a key that is no longer a News Category" do
      create(:member_news_category_preference, user: member, category_key: "industry")
      MemberNewsCategoryPreference.insert({ user_id: member.user_id, category_key: "retired", created_at: Time.current })

      expect(preferences_for(member)["hidden"]).to eq([ "industry" ])
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

  describe "PATCH /api/v1/users/:user_id/news_category_preferences" do
    def patch_preferences(user, data, headers = auth_headers_for(user))
      patch path_for(user), params: { data: data }, headers: headers, as: :json
    end

    it "switches a News Category off and reads it back" do
      patch_preferences(member, { hidden: { rumours: true } })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "hidden")).to eq([ "rumours" ])
      expect(preferences_for(member)["hidden"]).to eq([ "rumours" ])
      expect(preferences_for(member)["categories"].find { |c| c["key"] == "rumours" }).to include("hidden" => true)
    end

    it "lists switched-off News Categories in News Category order" do
      patch_preferences(member, { hidden: { general: true, announcements: true, industry: true } })

      expect(preferences_for(member)["hidden"]).to eq(%w[announcements industry general])
    end

    it "switches a News Category on again" do
      patch_preferences(member, { hidden: { rumours: true, industry: true } })

      patch_preferences(member, { hidden: { rumours: false } })

      expect(response).to have_http_status(:ok)
      expect(preferences_for(member)["hidden"]).to eq([ "industry" ])
    end

    it "changes only the News Categories named, and repeating a change is a no-op" do
      patch_preferences(member, { hidden: { rumours: true } })
      patch_preferences(member, { hidden: { industry: true } })
      patch_preferences(member, { hidden: { industry: true } })

      expect(response).to have_http_status(:ok)
      expect(preferences_for(member)["hidden"]).to eq(%w[industry rumours])
    end

    it "refuses an unknown News Category with 422 and changes nothing" do
      patch_preferences(member, { hidden: { rumours: true, piracy: true } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "unknown News Category: piracy")
      expect(preferences_for(member)["hidden"]).to eq([])
    end

    it "422s when a value is not true or false" do
      patch_preferences(member, { hidden: { rumours: "yes" } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "hidden.rumours must be true or false")
    end

    it "422s when hidden is not an object" do
      patch_preferences(member, { hidden: [ "rumours" ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "hidden must be an object of News Category keys to true or false")
    end

    it "422s when there is nothing to change" do
      patch_preferences(member, { other: true })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "hidden required")
    end

    it "400s when the data envelope is missing" do
      patch path_for(member), params: { hidden: { rumours: true } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids another member and changes nothing" do
      patch_preferences(member, { hidden: { rumours: true } }, auth_headers_for(create(:user)))

      expect(response).to have_http_status(:forbidden)
      expect(preferences_for(member)["hidden"]).to eq([])
    end

    it "forbids the bot's service token" do
      patch_preferences(member, { hidden: { rumours: true } }, service_headers)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      patch path_for(member), params: { data: { hidden: { rumours: true } } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "behind the News Hub Feature" do
    it "is not found for a member while the News Hub is in Preview or Off" do
      %w[preview off].each do |state|
        set_feature_flag("news_hub", state)

        get path_for(member), headers: auth_headers_for(member)
        expect(response).to have_http_status(:not_found), "GET got #{response.status} in #{state}"

        patch path_for(member), params: { data: { hidden: { rumours: true } } }, headers: auth_headers_for(member),
          as: :json
        expect(response).to have_http_status(:not_found), "PATCH got #{response.status} in #{state}"
      end
    end

    it "answers staff in Preview" do
      set_feature_flag("news_hub", "preview")
      admin = create(:user, :admin)

      expect(preferences_for(admin)["hidden"]).to eq([])
    end

    it "keeps a preference through any flag change" do
      patch path_for(member), params: { data: { hidden: { rumours: true } } }, headers: auth_headers_for(member),
        as: :json

      %w[off preview live].each { |state| set_feature_flag("news_hub", state) }

      expect(preferences_for(member)["hidden"]).to eq([ "rumours" ])
    end
  end
end
