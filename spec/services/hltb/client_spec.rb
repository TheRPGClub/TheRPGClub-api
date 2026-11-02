# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hltb::Client do
  subject(:client) do
    described_class.new(api_key: "google-key", search_engine_id: "engine-id", google_http: google_http, page_http: page_http)
  end

  let(:google_stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:page_stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:google_http) { Faraday.new(url: described_class::GOOGLE_SEARCH_URL) { |builder| builder.adapter(:test, google_stubs) } }
  let(:page_http) { Faraday.new { |builder| builder.adapter(:test, page_stubs) } }
  let(:page_url) { "https://howlongtobeat.com/game/10270" }

  # The parts of an HLTB game page the bot's cheerio selectors read.
  let(:page_html) do
    <<~HTML
      <html><body>
        <img src="https://howlongtobeat.com/games/10270_Chrono_Trigger.jpg">
        <div class="GameHeader_profile_header__q_PID"> Chrono Trigger </div>
        <ul>
          <li><h4>Main Story</h4><h5>23 Hours</h5></li>
          <li><h4>Main + Sides</h4><h5>30 Hours</h5></li>
          <li><h4>Completionist</h4><h5>41½ Hours</h5></li>
        </ul>
      </body></html>
    HTML
  end

  def google_results(*links)
    [ 200, { "Content-Type" => "application/json" }, { items: links.map { |link| { link: link, title: "x" } } }.to_json ]
  end

  describe "#search" do
    it "finds the page through Google Custom Search and parses its times" do
      google_stubs.get("/customsearch/v1") do |env|
        expect(env.params).to eq("key" => "google-key", "cx" => "engine-id", "q" => "How long is Chrono Trigger?")
        google_results(page_url, "https://howlongtobeat.com/game/999")
      end
      page_stubs.get(page_url) { [ 200, { "Content-Type" => "text/html" }, page_html ] }

      result = client.search("Chrono Trigger")

      expect(result.to_h).to eq(
        name: "Chrono Trigger",
        url: page_url,
        image_url: "https://howlongtobeat.com/games/10270_Chrono_Trigger.jpg",
        main: "23 Hours",
        main_sides: "30 Hours",
        completionist: "41½ Hours",
        single_player: nil,
        co_op: nil,
        vs: nil
      )
      google_stubs.verify_stubbed_calls
      page_stubs.verify_stubbed_calls
    end

    it "reads the multiplayer times of a multiplayer game" do
      google_stubs.get("/customsearch/v1") { google_results(page_url) }
      page_stubs.get(page_url) do
        [ 200, {}, <<~HTML ]
          <div class="GameHeader_profile_header__q_PID">Halo</div>
          <li><h4>Single-Player</h4><h5>10 Hours</h5></li>
          <li><h4>Co-Op</h4><h5>12 Hours</h5></li>
          <li><h4>Vs.</h4><h5>100 Hours</h5></li>
        HTML
      end

      expect(client.search("Halo").to_h).to include(single_player: "10 Hours", co_op: "12 Hours", vs: "100 Hours", main: nil)
    end

    it "returns nil when Google finds nothing" do
      google_stubs.get("/customsearch/v1") { [ 200, { "Content-Type" => "application/json" }, { searchInformation: {} }.to_json ] }

      expect(client.search("No Such Game")).to be_nil
    end

    it "returns nil when the first result is not an HLTB page, without fetching it" do
      google_stubs.get("/customsearch/v1") { google_results("https://example.com/game/10270") }

      expect(client.search("Chrono Trigger")).to be_nil
    end

    it "raises RequestError when Google fails" do
      google_stubs.get("/customsearch/v1") { [ 403, { "Content-Type" => "application/json" }, { error: { message: "quota" } }.to_json ] }

      expect { client.search("Chrono Trigger") }.to raise_error(described_class::RequestError, /Google Custom Search/)
    end

    it "raises RequestError when the HLTB page fails" do
      google_stubs.get("/customsearch/v1") { google_results(page_url) }
      page_stubs.get(page_url) { [ 503, {}, "busy" ] }

      expect { client.search("Chrono Trigger") }.to raise_error(described_class::RequestError, /HowLongToBeat/)
    end

    it "raises RequestError when the network fails" do
      google_stubs.get("/customsearch/v1") { raise Faraday::ConnectionFailed, "connection refused" }

      expect { client.search("Chrono Trigger") }.to raise_error(described_class::RequestError)
    end

    it "raises ConfigurationError without Google Custom Search credentials" do
      unconfigured = described_class.new(api_key: "", search_engine_id: "", google_http: google_http, page_http: page_http)

      expect { unconfigured.search("Chrono Trigger") }
        .to raise_error(described_class::ConfigurationError, /GOOGLE_CUSTOM_SEARCH_API_KEY/)
    end
  end
end
