# frozen_string_literal: true

require "rails_helper"

# The News Mark (spec api#494, ticket api#495): the moment up to which a
# member has seen the News Hub's News Items. The website reads it to split
# new from seen, moves it forward when the member leaves /news, and moves it
# to now for Mark all seen. It never moves backwards and never past now.
RSpec.describe "api/v1/news_mark behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:now) { Time.zone.parse("2026-11-26 18:00:00 UTC") }

  around { |example| travel_to(now) { example.run } }

  def path_for(user) = "/api/v1/users/#{user.user_id}/news_mark"

  def mark_for(user)
    get path_for(user), headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def put_mark(user, data, headers = auth_headers_for(user))
    put path_for(user), params: { data: data }, headers: headers, as: :json
  end

  describe "GET /api/v1/users/:user_id/news_mark" do
    it "has no News Mark until one is set" do
      expect(mark_for(member)).to eq("user_id" => member.user_id, "news_mark" => nil)
    end

    it "reads back the News Mark once set" do
      put_mark(member, { news_mark: "2026-11-24T21:40:00.123Z" })

      expect(mark_for(member)).to eq("user_id" => member.user_id, "news_mark" => "2026-11-24T21:40:00.123000Z")
    end

    it "forbids another member" do
      get path_for(member), headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids the bot's service token, since the News Mark only shapes the website" do
      get path_for(member), headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "is not found when the News Hub Feature is Off" do
      set_feature_flag("news_hub", "off")
      get path_for(member), headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get path_for(member)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/users/:user_id/news_mark" do
    it "sets a first News Mark" do
      put_mark(member, { news_mark: "2026-11-24T21:40:00Z" })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => member.user_id, "news_mark" => "2026-11-24T21:40:00.000000Z")
    end

    it "moves the News Mark forward" do
      put_mark(member, { news_mark: "2026-11-24T21:40:00Z" })
      put_mark(member, { news_mark: "2026-11-25T08:15:00Z" })

      expect(json.dig("data", "news_mark")).to eq("2026-11-25T08:15:00.000000Z")
      expect(mark_for(member)["news_mark"]).to eq("2026-11-25T08:15:00.000000Z")
    end

    it "never moves the News Mark backwards: it keeps the stored one and answers with it" do
      put_mark(member, { news_mark: "2026-11-25T08:15:00Z" })
      put_mark(member, { news_mark: "2026-11-24T21:40:00Z" })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "news_mark")).to eq("2026-11-25T08:15:00.000000Z")
      expect(mark_for(member)["news_mark"]).to eq("2026-11-25T08:15:00.000000Z")
    end

    it "clamps an instant past now to now" do
      put_mark(member, { news_mark: "2026-12-01T00:00:00Z" })

      expect(json.dig("data", "news_mark")).to eq("2026-11-26T18:00:00.000000Z")
    end

    it "takes an offset instant" do
      put_mark(member, { news_mark: "2026-11-24T16:40:00-05:00" })

      expect(json.dig("data", "news_mark")).to eq("2026-11-24T21:40:00.000000Z")
    end

    it "moves the News Mark to now for Mark all seen" do
      put_mark(member, { news_mark: "2026-11-24T21:40:00Z" })
      put_mark(member, { all_seen: true })

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "news_mark")).to eq("2026-11-26T18:00:00.000000Z")
    end

    it "keeps a later News Mark when Mark all seen arrives with an earlier now" do
      put_mark(member, { all_seen: true })
      travel_back
      travel_to(now - 1.hour)
      put_mark(member, { all_seen: true })

      expect(json.dig("data", "news_mark")).to eq("2026-11-26T18:00:00.000000Z")
    end

    [
      [ { other: 1 }, "news_mark or all_seen required" ],
      [ { news_mark: "yesterday" }, "news_mark must be an ISO 8601 instant" ],
      [ { news_mark: 5 }, "news_mark must be an ISO 8601 instant" ],
      [ { all_seen: false }, "all_seen must be true" ],
      [ { all_seen: true, news_mark: "2026-11-24T21:40:00Z" }, "give either news_mark or all_seen, not both" ]
    ].each do |data, error|
      it "refuses #{data.inspect} with 422 and keeps the News Mark" do
        put_mark(member, { news_mark: "2026-11-24T21:40:00Z" })
        put_mark(member, data)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to eq(error)
        expect(mark_for(member)["news_mark"]).to eq("2026-11-24T21:40:00.000000Z")
      end
    end

    it "forbids another member and leaves the News Mark unset" do
      put_mark(member, { all_seen: true }, auth_headers_for(create(:user, role_member: true)))

      expect(response).to have_http_status(:forbidden)
      expect(mark_for(member)["news_mark"]).to be_nil
    end

    it "forbids the bot's service token" do
      put_mark(member, { all_seen: true }, service_headers)

      expect(response).to have_http_status(:forbidden)
      expect(mark_for(member)["news_mark"]).to be_nil
    end

    it "refuses a request without data with 400" do
      put path_for(member), params: {}, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "is not found when the News Hub Feature is Off" do
      set_feature_flag("news_hub", "off")
      put_mark(member, { all_seen: true })

      expect(response).to have_http_status(:not_found)
    end
  end
end
