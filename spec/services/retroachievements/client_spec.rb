# frozen_string_literal: true

require "rails_helper"

RSpec.describe Retroachievements::Client do
  subject(:client) { described_class.new(api_key: "test-key", http: http, sleeper: sleeper) }

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:http) { Faraday.new(url: described_class::API_BASE_URL) { |builder| builder.adapter(:test, stubs) } }
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:ulid) { "00003EMFWR7XB8SDPEHB3K56ZQ" }

  def json(body, status: 200, headers: {})
    [ status, { "Content-Type" => "application/json" }.merge(headers), body.to_json ]
  end

  describe "#user_profile" do
    let(:profile) do
      {
        "User" => "NewName", "ULID" => ulid, "UserPic" => "/UserPic/NewName.png",
        "MemberSince" => "2013-02-01 05:41:36", "TotalPoints" => 1200, "Untracked" => 0, "ID" => 1
      }
    end

    it "resolves a username to the ULID, current username and avatar" do
      stubs.get("/API/API_GetUserProfile.php") do |env|
        expect(env.params).to eq("u" => "OldName", "y" => "test-key")
        json(profile)
      end

      expect(client.user_profile("OldName")).to eq(
        external_id: ulid,
        display_name: "NewName",
        avatar_url: "https://media.retroachievements.org/UserPic/NewName.png"
      )
    end

    it "resolves a renamed member by ULID" do
      stubs.get("/API/API_GetUserProfile.php") do |env|
        expect(env.params["u"]).to eq(ulid)
        json(profile)
      end

      expect(client.user_profile(ulid)).to include(external_id: ulid, display_name: "NewName")
    end

    it "raises NotFound when RetroAchievements answers 404" do
      stubs.get("/API/API_GetUserProfile.php") { json({}, status: 404) }

      expect { client.user_profile("nobody") }.to raise_error(Achievements::Providers::NotFound)
    end

    it "raises NotFound when the profile has no ULID" do
      stubs.get("/API/API_GetUserProfile.php") { json({}) }

      expect { client.user_profile("nobody") }.to raise_error(Achievements::Providers::NotFound)
    end

    it "raises NotFound for an untracked (banned) user" do
      stubs.get("/API/API_GetUserProfile.php") { json(profile.merge("Untracked" => 1)) }

      expect { client.user_profile("cheater") }.to raise_error(Achievements::Providers::NotFound)
    end
  end
end
