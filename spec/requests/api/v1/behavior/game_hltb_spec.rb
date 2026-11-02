# frozen_string_literal: true

require "rails_helper"

# POST /api/v1/games/:id/hltb/lookup: a member's on-demand HowLongToBeat
# lookup (web parity 2). Hltb::Client is stubbed at its constructor; its own
# Google and HLTB traffic is covered by spec/services/hltb/client_spec.rb.
RSpec.describe "api/v1/games/:id/hltb/lookup behavior", type: :request do
  let(:client) { instance_double(Hltb::Client) }
  let(:game) { create(:game, title: "Chrono Trigger", initial_release_date: Time.utc(1995, 3, 11)) }
  let(:member) { auth_headers_for(create(:user, role_member: true)) }
  let(:scraped) do
    Hltb::Client::Result.new(
      name: "Chrono Trigger", url: "https://howlongtobeat.com/game/10270",
      image_url: "https://howlongtobeat.com/games/10270.jpg",
      main: "23 Hours", main_sides: "30 Hours", completionist: "41 Hours",
      single_player: nil, co_op: nil, vs: nil
    )
  end

  before { allow(Hltb::Client).to receive(:new).and_return(client) }

  def lookup(headers)
    post "/api/v1/games/#{game.game_id}/hltb/lookup", headers: headers, as: :json
  end

  context "when the game released more than six months ago" do
    it "searches HLTB by the game's title, saves the times and returns them" do
      allow(client).to receive(:search).with("Chrono Trigger").and_return(scraped)

      expect { lookup(member) }.to change(RpgClubHltbCache, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "name" => "Chrono Trigger", "url" => "https://howlongtobeat.com/game/10270",
        "image_url" => "https://howlongtobeat.com/games/10270.jpg",
        "main" => "23 Hours", "main_sides" => "30 Hours", "completionist" => "41 Hours",
        "single_player" => nil, "source_query" => "Chrono Trigger"
      )
      expect(json.fetch("meta")).to eq("source" => "hltb", "saved" => true)

      get "/api/v1/games/#{game.game_id}/profile", headers: member
      expect(json.dig("data", "hltb", "main")).to eq("23 Hours")
    end
  end

  context "when the game released within the last six months" do
    let(:game) { create(:game, title: "Brand New", initial_release_date: 2.months.ago) }

    it "returns the times without saving them" do
      allow(client).to receive(:search).and_return(scraped)

      expect { lookup(member) }.not_to change(RpgClubHltbCache, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("main" => "23 Hours")
      expect(json.fetch("meta")).to eq("source" => "hltb", "saved" => false)
    end
  end

  context "when the game has no release date" do
    let(:game) { create(:game, title: "Undated", initial_release_date: nil) }

    it "returns the times without saving them, as the bot does" do
      allow(client).to receive(:search).and_return(scraped)

      expect { lookup(member) }.not_to change(RpgClubHltbCache, :count)
      expect(json.fetch("meta")).to include("saved" => false)
    end
  end

  context "when the game already has saved times" do
    before { RpgClubHltbCache.create!(gamedb_game_id: game.game_id, hltb_name: "Chrono Trigger", main: "22 Hours") }

    it "returns the saved times without scraping HLTB" do
      expect(client).not_to receive(:search)

      lookup(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("name" => "Chrono Trigger", "main" => "22 Hours")
      expect(json.fetch("meta")).to eq("source" => "cache", "saved" => true)
    end
  end

  it "404s with hltb_no_match when HLTB has no page for the game" do
    allow(client).to receive(:search).and_return(nil)

    expect { lookup(member) }.not_to change(RpgClubHltbCache, :count)

    expect(response).to have_http_status(:not_found)
    expect(json).to include("error" => "hltb_no_match")
  end

  it "502s with hltb_lookup_failed when Google or HLTB fails" do
    allow(client).to receive(:search).and_raise(Hltb::Client::RequestError, "HowLongToBeat returned HTTP 503.")

    lookup(member)

    expect(response).to have_http_status(:bad_gateway)
    expect(json).to include("error" => "hltb_lookup_failed")
  end

  it "503s with hltb_not_configured without Google Custom Search credentials" do
    allow(client).to receive(:search).and_raise(Hltb::Client::ConfigurationError, "GOOGLE_CUSTOM_SEARCH_API_KEY must be set")

    lookup(member)

    expect(response).to have_http_status(:service_unavailable)
    expect(json).to include("error" => "hltb_not_configured")
  end

  it "trims scraped values to the cache's column limits" do
    allow(client).to receive(:search).and_return(scraped.with(main: "9" * 80))

    lookup(member)

    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "main")).to eq("9" * 50)
  end

  it "404s for an unknown game" do
    post "/api/v1/games/999999999/hltb/lookup", headers: member, as: :json

    expect(response).to have_http_status(:not_found)
  end

  describe "gates" do
    before { allow(client).to receive(:search).and_return(scraped) }

    {
      "a Members role holder" => [ { role_member: true }, {} ],
      "a Moderator" => [ { role_moderator: true }, {} ],
      "an Admin" => [ { role_admin: true }, {} ],
      "a Superadmin" => [ {}, { is_dev: true } ]
    }.each do |label, (flags, token_flags)|
      it "lets #{label} look up times" do
        lookup(auth_headers_for(create(:user, **flags), **token_flags))

        expect(response).to have_http_status(:ok)
      end
    end

    it "lets the service look up times" do
      lookup(service_headers)

      expect(response).to have_http_status(:ok)
    end

    it "refuses a signed-in user without the Members role" do
      expect(client).not_to receive(:search)

      lookup(auth_headers_for(create(:user, role_regular: true)))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      lookup({})

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
