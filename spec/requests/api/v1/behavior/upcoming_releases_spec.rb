# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Release Calendar (spec #389, ticket #394): the
# release_calendar Feature and GET /api/v1/upcoming_releases, which lists
# Upcoming Releases (one game's Releases sharing a date and Date Precision).
RSpec.describe "api/v1/upcoming_releases behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:ps5) { create(:platform, platform_name: "PlayStation 5", platform_abbreviation: "PS5") }
  let(:switch) { create(:platform, platform_name: "Nintendo Switch", platform_abbreviation: "Switch") }
  let(:pc) { create(:platform, platform_name: "PC", platform_abbreviation: "PC") }
  let(:na) { GamedbRegion.create_with(region_name: "North America").find_or_create_by!(region_code: "NA") }
  let(:eu) { GamedbRegion.create_with(region_name: "Europe").find_or_create_by!(region_code: "EU") }
  let(:japan) { GamedbRegion.create_with(region_name: "Japan").find_or_create_by!(region_code: "JP") }

  # Today is 2027-03-10 for every example.
  around { |example| travel_to(Time.utc(2027, 3, 10, 12)) { example.run } }

  # Moves "now" inside an example (travel_to blocks do not nest).
  def at(time)
    travel_back
    travel_to(time)
    yield
  end

  def release(game, on, precision: "day", platform: ps5, region: na, **attrs)
    create(:release, game: game, platform: platform, region: region, release_date: on && Date.parse(on),
      date_precision: precision, **attrs)
  end

  def upcoming(**params)
    get "/api/v1/upcoming_releases", params: params, headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  # Each Upcoming Release as [title, date, precision].
  def entries(**params)
    upcoming(**params).map { |entry| [ entry.dig("game", "title"), entry["date"], entry["date_precision"] ] }
  end

  describe "the Release Calendar Feature" do
    it "is a hideable Feature that reads as Preview with no stored state", feature_flags: :none do
      admin = create(:user, role_admin: true)

      get "/api/v1/features", headers: auth_headers_for(admin)

      release_calendar = json.fetch("data").find { |feature| feature["key"] == "release_calendar" }
      expect(release_calendar).to include("name" => "Release Calendar", "state" => "preview", "core" => false,
        "hideable" => true, "last_change" => nil,
        "coverage" => { "website" => [ "Releases" ], "bot" => [], "posts" => [] })
    end
  end

  describe "Upcoming Releases" do
    it "groups one game's Releases on the same date and Date Precision, listing each platform and region" do
      game = create(:game, title: "Starfall")
      create(:game_image, :primary, game: game, kind: "cover")
      release(game, "2027-04-02", platform: ps5, region: na, format: "Physical")
      release(game, "2027-04-02", platform: switch, region: eu, source: "igdb")
      release(game, "2027-04-02", platform: pc, region: japan)

      data = upcoming

      expect(data.size).to eq(1)
      expect(data.first).to include(
        "game" => { "game_id" => game.game_id, "title" => "Starfall", "cover_url" => game.reload.cover_url },
        "date" => "2027-04-02", "date_precision" => "day", "section" => "April 2027", "first_released_on" => nil
      )
      expect(data.first.fetch("releases")).to contain_exactly(
        include("platform_id" => ps5.platform_id, "platform_name" => "PlayStation 5", "platform_abbreviation" => "PS5",
          "region_code" => "NA", "region_name" => "North America", "format" => "Physical", "source" => "manual"),
        include("platform_id" => switch.platform_id, "region_code" => "EU", "format" => nil, "source" => "igdb"),
        include("platform_id" => pc.platform_id, "region_code" => "JP", "region_name" => "Japan")
      )
    end

    it "lists a Japanese Release like any other region" do
      release(create(:game, title: "Hoshi"), "2027-05-01", region: japan)

      expect(upcoming.first.fetch("releases")).to contain_exactly(include("region_code" => "JP"))
    end

    it "keeps a game's Releases on different dates, or at different precisions, as separate entries" do
      game = create(:game, title: "Tides")
      release(game, "2027-05-01", region: na)
      release(game, "2027-05-02", region: eu)
      release(game, "2027-05-01", precision: "month", platform: switch)

      expect(entries).to eq([
        [ "Tides", "2027-05-01", "month" ], [ "Tides", "2027-05-01", "day" ], [ "Tides", "2027-05-02", "day" ]
      ])
    end
  end

  describe "placement" do
    it "places each Date Precision on the calendar under its section" do
      release(create(:game, title: "Alpha"), "2027-07-15")
      release(create(:game, title: "Beta"), "2027-07-01", precision: "month")
      release(create(:game, title: "Aardvark"), "2027-07-01")
      release(create(:game, title: "Gamma"), "2027-09-30")
      release(create(:game, title: "Delta"), "2027-07-01", precision: "quarter")
      release(create(:game, title: "Epsilon"), "2027-10-01", precision: "month")
      release(create(:game, title: "Zulu"), "2027-10-01", precision: "quarter")
      release(create(:game, title: "Golf"), "2027-12-31")
      release(create(:game, title: "Hotel"), "2027-01-01", precision: "year")
      release(create(:game, title: "India"), nil, precision: "tba")
      release(create(:game, title: "Juliet"), "2028-01-01", precision: "month")

      expect(upcoming.map { |entry| [ entry.dig("game", "title"), entry["section"] ] }).to eq([
        [ "Beta", "July 2027" ],
        [ "Aardvark", "July 2027" ],
        [ "Alpha", "July 2027" ],
        [ "Gamma", "September 2027" ],
        [ "Delta", "Q3 2027" ],
        [ "Epsilon", "October 2027" ],
        [ "Golf", "December 2027" ],
        [ "Zulu", "Q4 2027" ],
        [ "Hotel", "2027" ],
        [ "Juliet", "January 2028" ],
        [ "India", "TBA" ]
      ])
    end

    it "returns a TBA entry with no date" do
      release(create(:game, title: "Someday"), nil, precision: "tba")

      expect(upcoming.first).to include("date" => nil, "date_precision" => "tba", "section" => "TBA")
    end

    it "breaks ties on game title, then game id" do
      zeta = create(:game, title: "Zeta")
      first_twin = create(:game, title: "Twin")
      second_twin = create(:game, title: "Twin")
      [ zeta, second_twin, first_twin ].each { |game| release(game, "2027-04-01") }

      expect(upcoming.map { |entry| entry.dig("game", "game_id") })
        .to eq([ first_twin.game_id, second_twin.game_id, zeta.game_id ])
    end
  end

  describe "the default window" do
    it "runs from today forward, keeping a vague date until its whole period has ended and TBA always" do
      release(create(:game, title: "Yesterday"), "2027-03-09")
      release(create(:game, title: "Today"), "2027-03-10")
      release(create(:game, title: "February"), "2027-02-01", precision: "month")
      release(create(:game, title: "March"), "2027-03-01", precision: "month")
      release(create(:game, title: "Q4 2026"), "2026-10-01", precision: "quarter")
      release(create(:game, title: "Q1 2027"), "2027-01-01", precision: "quarter")
      release(create(:game, title: "Year 2026"), "2026-01-01", precision: "year")
      release(create(:game, title: "Year 2027"), "2027-01-01", precision: "year")
      release(create(:game, title: "Unknown"), nil, precision: "tba")

      expect(entries.map(&:first)).to eq([ "March", "Today", "Q1 2027", "Year 2027", "Unknown" ])
    end

    it "still returns a day Release all through its own date" do
      release(create(:game, title: "Launch"), "2027-03-10")

      at(Time.utc(2027, 3, 10, 23, 59)) { expect(entries.map(&:first)).to eq([ "Launch" ]) }
      at(Time.utc(2027, 3, 11, 0, 1)) { expect(entries).to eq([]) }
    end

    it "still returns a quarter Release on the quarter's last day" do
      release(create(:game, title: "Spring"), "2027-01-01", precision: "quarter")

      at(Time.utc(2027, 3, 31, 23)) { expect(entries.map(&:first)).to eq([ "Spring" ]) }
      at(Time.utc(2027, 4, 1, 1)) { expect(entries).to eq([]) }
    end
  end

  describe "month=" do
    before do
      release(create(:game, title: "November day"), "2026-11-05")
      release(create(:game, title: "November month"), "2026-11-01", precision: "month")
      release(create(:game, title: "December day"), "2026-12-24")
      release(create(:game, title: "Q4 2026"), "2026-10-01", precision: "quarter")
      release(create(:game, title: "Year 2026"), "2026-01-01", precision: "year")
      release(create(:game, title: "Upcoming"), "2027-04-01")
      release(create(:game, title: "Unknown"), nil, precision: "tba")
    end

    it "returns a past month's entries" do
      expect(entries(month: "2026-11").map(&:first)).to eq([ "November month", "November day" ])
    end

    it "returns the quarter and year that end in the month after its days" do
      expect(entries(month: "2026-12").map(&:first)).to eq([ "December day", "Q4 2026", "Year 2026" ])
    end

    it "returns a future month's entries" do
      expect(entries(month: "2027-04").map(&:first)).to eq([ "Upcoming" ])
    end

    it "is a 422 when it is not a YYYY-MM month" do
      %w[2027-13 2027-4 April].each do |month|
        get "/api/v1/upcoming_releases", params: { month: month }, headers: auth_headers_for(member)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("error" => "invalid_month")
      end
    end
  end

  describe "platform_id" do
    let(:game) { create(:game, title: "Duo") }

    before do
      release(game, "2027-05-01", platform: ps5)
      release(game, "2027-05-01", platform: switch, region: eu)
      release(create(:game, title: "Solo"), "2027-05-01", platform: pc)
    end

    it "keeps an Upcoming Release when any of its Releases is on one of the platforms, with all its Releases" do
      data = upcoming(platform_id: [ switch.platform_id ])

      expect(data.map { |entry| entry.dig("game", "title") }).to eq([ "Duo" ])
      expect(data.first.fetch("releases").map { |r| r["platform_id"] })
        .to contain_exactly(ps5.platform_id, switch.platform_id)
    end

    it "takes several platforms, repeated or comma-separated" do
      expect(entries(platform_id: [ switch.platform_id, pc.platform_id ]).map(&:first)).to eq([ "Duo", "Solo" ])
      expect(entries(platform_id: "#{switch.platform_id},#{pc.platform_id}").map(&:first)).to eq([ "Duo", "Solo" ])
    end

    it "takes the bare repeated form (platform_id=1&platform_id=2) as several platforms" do
      get "/api/v1/upcoming_releases?platform_id=#{switch.platform_id}&platform_id=#{pc.platform_id}",
        headers: auth_headers_for(member)

      expect(json.fetch("data").map { |entry| entry.dig("game", "title") }).to eq([ "Duo", "Solo" ])
    end

    it "is a 422 for an id that is not a number" do
      get "/api/v1/upcoming_releases", params: { platform_id: "ps5" }, headers: auth_headers_for(member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_platform_id")
    end
  end

  describe "game_id and per_game=next" do
    let(:sequel) { create(:game, title: "Sequel") }
    let(:other) { create(:game, title: "Other") }

    before do
      release(sequel, "2027-06-01", region: japan)
      release(sequel, "2027-08-01", region: na)
      release(sequel, nil, precision: "tba", platform: switch)
      release(other, "2027-04-01")
      release(other, "2027-01-01", precision: "year", platform: pc)
    end

    it "limits the entries to the given games" do
      expect(entries(game_id: [ sequel.game_id ])).to eq([
        [ "Sequel", "2027-06-01", "day" ], [ "Sequel", "2027-08-01", "day" ], [ "Sequel", nil, "tba" ]
      ])
    end

    it "takes several games in the bare repeated form (game_id=1&game_id=2)" do
      get "/api/v1/upcoming_releases?game_id=#{sequel.game_id}&game_id=#{other.game_id}&per_game=next",
        headers: auth_headers_for(member)

      expect(json.fetch("data").map { |entry| entry.dig("game", "title") }).to eq([ "Other", "Sequel" ])
    end

    it "keeps only each game's earliest Upcoming Release" do
      expect(entries(per_game: "next")).to eq([ [ "Other", "2027-04-01", "day" ], [ "Sequel", "2027-06-01", "day" ] ])
    end

    it "combines with game_id" do
      expect(entries(per_game: "next", game_id: [ sequel.game_id ])).to eq([ [ "Sequel", "2027-06-01", "day" ] ])
    end

    it "picks each game's earliest entry among those on the filtered platforms" do
      expect(entries(per_game: "next", platform_id: [ switch.platform_id, pc.platform_id ]))
        .to eq([ [ "Other", "2027-01-01", "year" ], [ "Sequel", nil, "tba" ] ])
    end

    it "is a 422 for any other per_game" do
      get "/api/v1/upcoming_releases", params: { per_game: "all" }, headers: auth_headers_for(member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_per_game")
    end
  end

  describe "first_released_on" do
    it "is the game's earliest dated Release on a later-region or later-platform entry, and null on the first" do
      game = create(:game, title: "Staggered")
      release(game, "2027-04-20", region: japan)
      release(game, "2027-05-20", region: na)
      release(game, nil, precision: "tba", platform: switch)

      expect(upcoming.map { |entry| [ entry["date"], entry["first_released_on"], entry["first_released_precision"] ] })
        .to eq([ [ "2027-04-20", nil, nil ], [ "2027-05-20", "2027-04-20", "day" ], [ nil, "2027-04-20", "day" ] ])
    end

    it "counts a Release from before the window" do
      game = create(:game, title: "Remaster")
      release(game, "2020-05-01", platform: pc)
      release(game, "2027-06-01", platform: switch)

      expect(upcoming.first).to include("date" => "2027-06-01", "first_released_on" => "2020-05-01")
    end

    it "carries the earliest Release's Date Precision" do
      game = create(:game, title: "Vague")
      release(game, "2027-04-01", precision: "quarter", platform: pc)
      release(game, "2027-08-14", platform: switch)

      expect(upcoming.map { |entry| [ entry["date"], entry["first_released_on"], entry["first_released_precision"] ] })
        .to eq([ [ "2027-04-01", nil, nil ], [ "2027-08-14", "2027-04-01", "quarter" ] ])
    end

    it "counts a vague Release as first only once its whole period has ended before the entry" do
      game = create(:game, title: "Overlap")
      release(game, "2027-03-01", precision: "month", region: japan)
      release(game, "2027-03-25", region: na)
      release(game, "2027-07-01", precision: "quarter", platform: pc)
      release(game, "2027-08-14", platform: switch)
      release(game, "2027-10-02", platform: switch, region: eu)

      expect(upcoming.map { |entry| [ entry["date"], entry["first_released_on"], entry["first_released_precision"] ] })
        .to eq([
          [ "2027-03-01", nil, nil ],
          [ "2027-03-25", nil, nil ],
          [ "2027-08-14", "2027-03-01", "month" ],
          [ "2027-07-01", "2027-03-01", "month" ],
          [ "2027-10-02", "2027-03-01", "month" ]
        ])
    end

    it "names an exact day inside an earlier vague Release's period when only the day came before the entry" do
      game = create(:game, title: "Sharpened")
      release(game, "2027-01-01", precision: "year", region: japan)
      release(game, "2027-04-02", region: eu)
      release(game, "2027-11-20", region: na)
      release(game, "2028-02-01", platform: pc)

      expect(upcoming.map { |entry| [ entry["date"], entry["first_released_on"], entry["first_released_precision"] ] })
        .to eq([
          [ "2027-04-02", nil, nil ],
          [ "2027-11-20", "2027-04-02", "day" ],
          [ "2027-01-01", nil, nil ],
          [ "2028-02-01", "2027-01-01", "year" ]
        ])
    end

    it "prefers the more precise Release when two share the earliest date" do
      game = create(:game, title: "Twice")
      release(game, "2027-07-01", precision: "month", platform: pc)
      release(game, "2027-07-01", platform: switch)
      release(game, "2027-09-01", platform: ps5)

      expect(upcoming.last).to include("date" => "2027-09-01", "first_released_on" => "2027-07-01",
        "first_released_precision" => "day")
    end
  end

  describe "pagination" do
    it "pages through the Upcoming Releases with page and per" do
      %w[One Two Three].each_with_index { |title, i| release(create(:game, title: title), "2027-04-0#{i + 1}") }

      get "/api/v1/upcoming_releases", params: { page: 2, per: 2 }, headers: auth_headers_for(member)

      expect(json.fetch("data").map { |entry| entry.dig("game", "title") }).to eq([ "Three" ])
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 2, "count" => 3, "per" => 2, "prev" => 1, "next" => nil)
    end

    it "still counts the entries on a page past the end" do
      release(create(:game, title: "Only"), "2027-04-01")

      get "/api/v1/upcoming_releases", params: { page: 3, per: 1 }, headers: auth_headers_for(member)

      expect(json.fetch("data")).to eq([])
      expect(json.dig("meta", "count")).to eq(1)
    end
  end
end
