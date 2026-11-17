# frozen_string_literal: true

require "rails_helper"

RSpec.describe Igdb::Client do
  subject(:client) { described_class.new }

  around do |example|
    keys = %w[IGDB_CLIENT_ID IGDB_CLIENT_SECRET]
    original_values = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["IGDB_CLIENT_ID"] = "test-client-id"
    ENV["IGDB_CLIENT_SECRET"] = "test-client-secret"

    example.run
  ensure
    original_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  describe "#game release dates and their Date Precision" do
    let(:platform) { { "id" => 6, "name" => "PC (Microsoft Windows)" } }
    let(:requests) { [] }

    def igdb_lists(*release_dates)
      token_response = instance_double(
        Faraday::Response, body: '{"access_token":"token","expires_in":3600}', success?: true
      )
      games_response = instance_double(
        Faraday::Response,
        body: [ { "id" => 1942, "name" => "Spec Game", "release_dates" => release_dates } ].to_json,
        success?: true
      )
      allow(Faraday).to receive(:post).with(described_class::TOKEN_URL).and_return(token_response)
      allow(Faraday).to receive(:post).with("#{described_class::API_BASE_URL}/games") do |&block|
        request = Struct.new(:headers, :body, :options).new({}, nil, Struct.new(:timeout).new)
        block.call(request)
        requests << request.body
        games_response
      end
    end

    def release_dates
      client.game(1942).fetch(:release_dates).map { |release| release.slice(:date, :date_precision) }
    end

    it "asks IGDB for each release date's format alongside the date" do
      igdb_lists

      client.game(1942)

      expect(requests.sole).to include("release_dates.date_format.format", "release_dates.category")
    end

    it "maps an exact day to a `day` Date Precision on its plain calendar date" do
      igdb_lists(
        { "platform" => platform, "region" => 2, "date" => Time.utc(2027, 3, 5).to_i, "y" => 2027, "m" => 3,
          "date_format" => { "format" => "YYYYMMMMDD" } }
      )

      expect(release_dates).to eq([ { date: Date.new(2027, 3, 5), date_precision: "day" } ])
    end

    it "maps a month-only date to `month`, stored on the first of its month" do
      igdb_lists(
        { "platform" => platform, "region" => 2, "date" => Time.utc(2027, 3, 31).to_i, "y" => 2027, "m" => 3,
          "date_format" => { "format" => "YYYYMMMM" } }
      )

      expect(release_dates).to eq([ { date: Date.new(2027, 3, 1), date_precision: "month" } ])
    end

    it "maps a quarter to `quarter`, stored on the first day of the quarter" do
      igdb_lists(
        { "platform" => platform, "region" => 2, "date" => Time.utc(2027, 9, 30).to_i, "y" => 2027, "m" => 9,
          "date_format" => { "format" => "YYYYQ3" } }
      )

      expect(release_dates).to eq([ { date: Date.new(2027, 7, 1), date_precision: "quarter" } ])
    end

    it "maps a year-only date to `year`, stored on 1 January" do
      igdb_lists(
        { "platform" => platform, "region" => 2, "date" => Time.utc(2027, 12, 31).to_i, "y" => 2027,
          "date_format" => { "format" => "YYYY" } }
      )

      expect(release_dates).to eq([ { date: Date.new(2027, 1, 1), date_precision: "year" } ])
    end

    it "keeps a TBA release date as `tba` with no date" do
      igdb_lists({ "platform" => platform, "region" => 2, "date_format" => { "format" => "TBD" } })

      expect(release_dates).to eq([ { date: nil, date_precision: "tba" } ])
    end

    it "falls back to the deprecated category when IGDB sends no date format" do
      igdb_lists(
        { "platform" => platform, "region" => 1, "date" => Time.utc(2028, 6, 30).to_i, "y" => 2028, "category" => 4 },
        { "platform" => platform, "region" => 2, "category" => 7 }
      )

      expect(release_dates).to eq([
        { date: Date.new(2028, 4, 1), date_precision: "quarter" },
        { date: nil, date_precision: "tba" }
      ])
    end

    it "reads a release date with neither format nor category from what it carries" do
      igdb_lists(
        { "platform" => platform, "region" => 1, "date" => Time.utc(2027, 3, 5).to_i },
        { "platform" => platform, "region" => 2, "y" => 2028, "m" => 2 },
        { "platform" => platform, "region" => 3, "y" => 2029 },
        { "platform" => platform, "region" => 4 }
      )

      expect(release_dates).to eq([
        { date: Date.new(2027, 3, 5), date_precision: "day" },
        { date: Date.new(2028, 2, 1), date_precision: "month" },
        { date: Date.new(2029, 1, 1), date_precision: "year" },
        { date: nil, date_precision: "tba" }
      ])
    end
  end

  describe "network failures" do
    it "wraps Faraday failures while fetching an access token" do
      allow(Faraday).to receive(:post).with(described_class::TOKEN_URL)
        .and_raise(Faraday::ConnectionFailed, "connection refused")

      expect { client.send(:access_token) }
        .to raise_error(described_class::RequestError, "IGDB token request failed: connection refused")
    end

    it "wraps Faraday failures while making an IGDB request" do
      token_response = instance_double(
        Faraday::Response,
        body: '{"access_token":"token","expires_in":3600}',
        success?: true
      )
      allow(Faraday).to receive(:post).with(described_class::TOKEN_URL).and_return(token_response)
      allow(Faraday).to receive(:post).with("#{described_class::API_BASE_URL}/games")
        .and_raise(Faraday::TimeoutError, "execution expired")

      expect { client.search("Chrono Trigger") }
        .to raise_error(described_class::RequestError, "IGDB games request failed: execution expired")
    end
  end
end
