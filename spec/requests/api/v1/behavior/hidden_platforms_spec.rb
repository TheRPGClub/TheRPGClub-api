# frozen_string_literal: true

require "rails_helper"

# Hidden Platforms (spec api#421, ticket api#427; GLOSSARY.md "Hidden
# Platform"): the platforms a member leaves out of their own Release Calendar
# and Upcoming Releases panel. Only the member themself may read or change
# their list; GET /upcoming_releases leaves them out for that member.
RSpec.describe "api/v1/hidden_platforms behavior", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:ps5) { create(:platform, platform_name: "PlayStation 5", platform_abbreviation: "PS5") }
  let(:switch) { create(:platform, platform_name: "Nintendo Switch", platform_abbreviation: "Switch") }
  let(:pc) { create(:platform, platform_name: "PC", platform_abbreviation: "PC") }

  def path_for(user) = "/api/v1/users/#{user.user_id}/hidden_platforms"

  def hidden_for(user, headers = auth_headers_for(user))
    get path_for(user), headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def hide(user, platform_ids, headers = auth_headers_for(user))
    put path_for(user), params: { data: { platform_ids: platform_ids } }, headers: headers, as: :json
  end

  describe "GET /api/v1/users/:user_id/hidden_platforms" do
    it "is empty for a member who hid nothing" do
      expect(hidden_for(member)).to eq("user_id" => member.user_id, "platform_ids" => [], "platforms" => [])
    end
  end

  describe "PUT /api/v1/users/:user_id/hidden_platforms" do
    it "saves the member's Hidden Platforms and reads them back by platform name" do
      hide(member, [ ps5.platform_id, switch.platform_id ])

      expect(response).to have_http_status(:ok)
      expected = {
        "user_id" => member.user_id,
        "platform_ids" => [ switch.platform_id, ps5.platform_id ],
        "platforms" => [
          { "platform_id" => switch.platform_id, "platform_name" => "Nintendo Switch", "platform_abbreviation" => "Switch" },
          { "platform_id" => ps5.platform_id, "platform_name" => "PlayStation 5", "platform_abbreviation" => "PS5" }
        ]
      }
      expect(json.fetch("data")).to eq(expected)
      expect(hidden_for(member)).to eq(expected)
    end

    it "replaces the whole set" do
      hide(member, [ ps5.platform_id, switch.platform_id ])
      hide(member, [ pc.platform_id ])

      expect(hidden_for(member)["platform_ids"]).to eq([ pc.platform_id ])
    end

    it "clears the set with an empty list" do
      hide(member, [ ps5.platform_id ])
      hide(member, [])

      expect(response).to have_http_status(:ok)
      expect(hidden_for(member)["platform_ids"]).to eq([])
    end

    it "takes an id sent twice once" do
      hide(member, [ ps5.platform_id, ps5.platform_id ])

      expect(response).to have_http_status(:ok)
      expect(hidden_for(member)["platform_ids"]).to eq([ ps5.platform_id ])
    end

    it "refuses an unknown platform, changing nothing" do
      hide(member, [ ps5.platform_id ])
      known = pc.platform_id
      missing = GamedbPlatform.maximum(:platform_id).to_i + 1
      hide(member, [ known, missing ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("unknown platform: #{missing}")
      expect(hidden_for(member)["platform_ids"]).to eq([ ps5.platform_id ])
    end

    it "refuses something other than a list of platform ids" do
      hide(member, "PS5")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("platform_ids must be a list of platform ids")

      hide(member, [ "PS5" ])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("platform_ids must be a list of platform ids")
    end

    it "refuses a missing platform_ids" do
      put path_for(member), params: { data: { platforms: [ 1 ] } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("platform_ids must be a list of platform ids")
    end
  end

  describe "who may read and change the list" do
    let(:other) { create(:user, role_member: true) }

    it "refuses another member, reading or saving" do
      get path_for(member), headers: auth_headers_for(other)
      expect(response).to have_http_status(:forbidden)

      hide(member, [ ps5.platform_id ], auth_headers_for(other))
      expect(response).to have_http_status(:forbidden)
      expect(hidden_for(member)["platform_ids"]).to eq([])
    end

    it "refuses staff on another member's list" do
      admin = create(:user, role_admin: true)

      get path_for(member), headers: auth_headers_for(admin)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses the service token" do
      get path_for(member), headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "is a 404 for a member who cannot use the Release Calendar" do
      set_feature_flag("release_calendar", "off")

      get path_for(member), headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end
  end
  describe "GET /api/v1/upcoming_releases" do
    include ActiveSupport::Testing::TimeHelpers

    let(:na) { GamedbRegion.create_with(region_name: "North America").find_or_create_by!(region_code: "NA") }
    let(:both) { create(:game, title: "Both") }
    let(:ps5_only) { create(:game, title: "PS5 Only") }

    around { |example| travel_to(Time.utc(2027, 3, 10, 12)) { example.run } }

    before do
      release(both, "2027-04-02", ps5)
      release(both, "2027-04-02", switch)
      release(ps5_only, "2027-04-03", ps5)
      hide(member, [ ps5.platform_id ])
    end

    def release(game, on, platform)
      create(:release, game: game, platform: platform, region: na, release_date: Date.parse(on), date_precision: "day")
    end

    def calendar(headers = auth_headers_for(member), **params)
      get "/api/v1/upcoming_releases", params: params, headers: headers
      expect(response).to have_http_status(:ok)
      json.fetch("data").map do |listed|
        [ listed.dig("game", "title"), listed["date"], listed.fetch("releases").pluck("platform_id") ]
      end
    end

    it "leaves out the member's Hidden Platforms, dropping an Upcoming Release left with no Releases" do
      expect(calendar).to eq([ [ "Both", "2027-04-02", [ switch.platform_id ] ] ])
      expect(json.dig("meta", "count")).to eq(1)
      expect(json.dig("meta", "hidden_platform_ids")).to eq([ ps5.platform_id ])
    end

    it "picks each game's next Upcoming Release among the platforms left" do
      later = create(:game, title: "Later")
      release(later, "2027-04-01", ps5)
      release(later, "2027-06-01", switch)

      expect(calendar(per_game: "next")).to eq([
        [ "Both", "2027-04-02", [ switch.platform_id ] ],
        [ "Later", "2027-06-01", [ switch.platform_id ] ]
      ])
    end

    it "lists everything with show_hidden=1" do
      expect(calendar(show_hidden: "1")).to eq([
        [ "Both", "2027-04-02", [ switch.platform_id, ps5.platform_id ] ],
        [ "PS5 Only", "2027-04-03", [ ps5.platform_id ] ]
      ])
      expect(json.dig("meta", "hidden_platform_ids")).to eq([])
    end

    it "is not filtered when platform_id is given, even for a Hidden Platform" do
      expect(calendar(platform_id: ps5.platform_id).map(&:first)).to eq([ "Both", "PS5 Only" ])
      expect(json.dig("meta", "hidden_platform_ids")).to eq([])
    end

    it "is never filtered for the service token" do
      expect(calendar(service_headers).map(&:first)).to eq([ "Both", "PS5 Only" ])
    end

    it "does not filter another member's calendar" do
      other = create(:user, role_member: true)

      expect(calendar(auth_headers_for(other)).map(&:first)).to eq([ "Both", "PS5 Only" ])
    end
  end
end
