# frozen_string_literal: true

require "rails_helper"

RSpec.describe Steam::Client do
  subject(:client) { described_class.new(api_key: "test-key", http: http, sleeper: sleeper, clock: -> { time[:now] }) }

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:http) { Faraday.new(url: described_class::API_BASE_URL) { |builder| builder.adapter(:test, stubs) } }
  # A fake monotonic clock that only moves when the client sleeps, so the
  # backoff and rate-limit waits are observable without real sleeping.
  let(:time) { { now: 1_000.0 } }
  let(:sleeps) { [] }
  let(:sleeper) do
    lambda do |seconds|
      sleeps << seconds
      time[:now] += seconds
    end
  end
  let(:steam_id) { "76561197960287930" }

  # Steam payloads all nest under `response:`, which Ruby would otherwise read
  # as a keyword argument, so the body is collected from the remaining keywords.
  def json(status: 200, headers: {}, **body)
    [ status, { "Content-Type" => "application/json" }.merge(headers), body.to_json ]
  end

  describe "#resolve_profile" do
    it "accepts a bare SteamID64 without calling Steam" do
      expect(client.resolve_profile(" #{steam_id} ")).to eq(
        steam_id64: steam_id,
        identifier_kind: "steamid64",
        raw_identifier: " #{steam_id} ",
        profile_path: "profiles/#{steam_id}"
      )
    end

    it "accepts a steamcommunity.com/profiles URL without calling Steam" do
      profile = client.resolve_profile("https://steamcommunity.com/profiles/#{steam_id}/games?tab=all")

      expect(profile).to include(steam_id64: steam_id, identifier_kind: "profiles_url")
    end

    it "resolves a steamcommunity.com/id vanity URL through ResolveVanityURL" do
      stubs.get("/ISteamUser/ResolveVanityURL/v1/") do |env|
        expect(env.params).to eq("vanityurl" => "gabelogannewell", "key" => "test-key")
        json(response: { success: 1, steamid: steam_id })
      end

      profile = client.resolve_profile("http://steamcommunity.com/id/gabelogannewell/")

      expect(profile).to eq(
        steam_id64: steam_id,
        identifier_kind: "vanity_url",
        raw_identifier: "http://steamcommunity.com/id/gabelogannewell/",
        profile_path: "profiles/#{steam_id}"
      )
      stubs.verify_stubbed_calls
    end

    it "resolves a bare vanity name through ResolveVanityURL" do
      stubs.get("/ISteamUser/ResolveVanityURL/v1/") { json(response: { success: 1, steamid: steam_id }) }

      expect(client.resolve_profile("gabelogannewell")).to include(steam_id64: steam_id, identifier_kind: "vanity")
    end

    it "raises invalid_identifier when Steam cannot resolve the vanity name" do
      stubs.get("/ISteamUser/ResolveVanityURL/v1/") { json(response: { success: 42, message: "No match" }) }

      expect { client.resolve_profile("nobody-here") }
        .to raise_error(described_class::Error) { |error| expect(error.code).to eq("invalid_identifier") }
    end

    [
      [ "a blank identifier", "   " ],
      [ "an unsupported format", "not a steam profile!" ],
      [ "a profiles URL whose id is not a SteamID64", "https://steamcommunity.com/profiles/12345" ]
    ].each do |label, identifier|
      it "raises invalid_identifier for #{label} without calling Steam" do
        expect { client.resolve_profile(identifier) }
          .to raise_error(described_class::Error) { |error| expect(error.code).to eq("invalid_identifier") }
      end
    end
  end

  describe "#player_summary" do
    it "returns the persona name" do
      stubs.get("/ISteamUser/GetPlayerSummaries/v2/") do |env|
        expect(env.params).to include("steamids" => steam_id)
        json(response: { players: [ { steamid: steam_id, personaname: " Rabscuttle " } ] })
      end

      expect(client.player_summary(steam_id)).to eq(profile_name: "Rabscuttle")
    end

    it "returns a nil name when Steam lists no player" do
      stubs.get("/ISteamUser/GetPlayerSummaries/v2/") { json(response: { players: [] }) }

      expect(client.player_summary(steam_id)).to eq(profile_name: nil)
    end
  end

  describe "#owned_games" do
    before do
      stubs.get("/ISteamUser/GetPlayerSummaries/v2/") do
        json(response: { players: [ { steamid: steam_id, personaname: "Rabscuttle" } ] })
      end
    end

    it "returns the library with normalized games and the persona name" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") do |env|
        expect(env.params).to eq(
          "steamid" => steam_id, "include_appinfo" => "1", "include_played_free_games" => "1", "key" => "test-key"
        )
        json(response: {
          game_count: 3,
          games: [
            {
              appid: 570, name: " Dota 2 ", playtime_forever: 1200, playtime_windows_forever: 1000,
              playtime_mac_forever: 0, playtime_linux_forever: 200, playtime_deck_forever: 0,
              rtime_last_played: 1_700_000_000
            },
            { appid: 220, name: "Half-Life 2", playtime_forever: 0, rtime_last_played: 0 },
            { appid: 0, name: "Broken" },
            { appid: 10, name: "  " }
          ]
        })
      end

      library = client.owned_games(steam_id)

      expect(library).to eq(
        steam_id64: steam_id,
        profile_name: "Rabscuttle",
        game_count: 3,
        games: [
          {
            app_id: 570, name: "Dota 2", playtime_forever_minutes: 1200, playtime_windows_minutes: 1000,
            playtime_mac_minutes: 0, playtime_linux_minutes: 200, playtime_deck_minutes: 0,
            last_played_at: Time.utc(2023, 11, 14, 22, 13, 20)
          },
          {
            app_id: 220, name: "Half-Life 2", playtime_forever_minutes: 0, playtime_windows_minutes: nil,
            playtime_mac_minutes: nil, playtime_linux_minutes: nil, playtime_deck_minutes: nil,
            last_played_at: nil
          }
        ]
      )
    end

    it "raises private_profile when Steam returns no visible games" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") { json(response: {}) }

      expect { client.owned_games(steam_id) }
        .to raise_error(described_class::Error) { |error| expect(error.code).to eq("private_profile") }
    end

    it "raises invalid_identifier for an id that is not a SteamID64" do
      expect { client.owned_games("gabelogannewell") }
        .to raise_error(described_class::Error) { |error| expect(error.code).to eq("invalid_identifier") }
    end
  end

  describe "#played_sets" do
    let(:owned_games) do
      json(response: {
        game_count: 3,
        games: [
          { appid: 620, name: " Portal 2 ", playtime_forever: 900, rtime_last_played: 1_700_000_000, img_icon_url: "abc123" },
          { appid: 220, name: "Half-Life 2", playtime_forever: 0, rtime_last_played: 0 },
          { appid: 400, name: "Portal", playtime_forever: 120, rtime_last_played: 1_600_000_000, img_icon_url: "" }
        ]
      })
    end

    it "lists only the games with playtime, as PlayedSets, without fetching the persona name" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") do |env|
        expect(env.params).to include("steamid" => steam_id, "include_appinfo" => "1", "include_played_free_games" => "1")
        owned_games
      end

      expect(client.played_sets(steam_id)).to eq([
        Achievements::Providers::PlayedSet.new(
          external_id: "620", title: "Portal 2", platform_label: "PC",
          icon_url: "https://media.steampowered.com/steamcommunity/public/images/apps/620/abc123.jpg",
          last_played_at: Time.utc(2023, 11, 14, 22, 13, 20), playtime_minutes: 900
        ),
        Achievements::Providers::PlayedSet.new(
          external_id: "400", title: "Portal", platform_label: "PC", icon_url: nil,
          last_played_at: Time.utc(2020, 9, 13, 12, 26, 40), playtime_minutes: 120
        )
      ])
      stubs.verify_stubbed_calls
    end

    it "keeps only the games last played after `since`" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") { owned_games }

      sets = client.played_sets(steam_id, since: Time.utc(2023, 1, 1))

      expect(sets.map(&:external_id)).to eq([ "620" ])
    end

    it "returns no sets for a public library whose played games list is empty" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") { json(response: { game_count: 0, games: [] }) }

      expect(client.played_sets(steam_id)).to eq([])
    end

    it "raises Private when Steam hides the game details" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") { json(response: {}) }

      expect { client.played_sets(steam_id) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises Private on HTTP 403" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") { json(status: 403) }

      expect { client.played_sets(steam_id) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises RateLimited once the 429 retries are exhausted" do
      stubs.get("/IPlayerService/GetOwnedGames/v1/") { json(status: 429) }

      expect { client.played_sets(steam_id) }.to raise_error(Achievements::Providers::RateLimited)
    end
  end

  describe "#set_with_progress" do
    let(:schema_path) { "/ISteamUserStats/GetSchemaForGame/v2/" }
    let(:player_path) { "/ISteamUserStats/GetPlayerAchievements/v1/" }
    let(:global_path) { "/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/" }
    let(:schema) do
      json(game: {
        gameName: "ValveTestApp620",
        availableGameStats: {
          achievements: [
            {
              name: "ACH_WAKE_UP", displayName: "Wake Up Call", description: "Survive the manual override.",
              icon: "https://cdn.example/wake.jpg", icongray: "https://cdn.example/wake_gray.jpg", hidden: 0
            },
            {
              name: "ACH_SECRET", displayName: "Secret Ending", icon: "https://cdn.example/secret.jpg",
              icongray: "https://cdn.example/secret_gray.jpg", hidden: 1
            },
            {
              name: "ACH_LATE", displayName: "Late Addition", description: "",
              icon: "https://cdn.example/late.jpg", icongray: "https://cdn.example/late_gray.jpg", hidden: 0
            }
          ]
        }
      })
    end
    let(:player) do
      json(playerstats: {
        steamID: steam_id, gameName: "Portal 2", success: true,
        achievements: [
          { apiname: "ACH_WAKE_UP", achieved: 1, unlocktime: 1_700_000_000 },
          { apiname: "ACH_SECRET", achieved: 0, unlocktime: 0 },
          { apiname: "ACH_LATE", achieved: 0, unlocktime: 0 }
        ]
      })
    end
    let(:global) do
      json(achievementpercentages: {
        achievements: [ { name: "ACH_WAKE_UP", percent: 71.25 }, { name: "ACH_SECRET", percent: "4.3" } ]
      })
    end

    it "merges the schema, the member's Unlocks and the global Rarity into a SetDefinition" do
      stubs.get(schema_path) do |env|
        expect(env.params).to include("appid" => "620", "l" => "english")
        schema
      end
      stubs.get(player_path) do |env|
        expect(env.params).to include("steamid" => steam_id, "appid" => "620")
        player
      end
      stubs.get(global_path) do |env|
        expect(env.params).to include("gameid" => "620")
        global
      end

      set = client.set_with_progress(steam_id, 620)

      expect(set).to eq(
        Achievements::Providers::SetDefinition.new(
          external_id: "620", title: "Portal 2", platform_label: "PC",
          achievements: [
            Achievements::Providers::AchievementDefinition.new(
              external_id: "ACH_WAKE_UP", name: "Wake Up Call", description: "Survive the manual override.",
              icon_url: "https://cdn.example/wake.jpg", icon_locked_url: "https://cdn.example/wake_gray.jpg",
              hidden: false, display_order: 1, rarity: BigDecimal("71.25")
            ),
            Achievements::Providers::AchievementDefinition.new(
              external_id: "ACH_SECRET", name: "Secret Ending", description: nil,
              icon_url: "https://cdn.example/secret.jpg", icon_locked_url: "https://cdn.example/secret_gray.jpg",
              hidden: true, display_order: 2, rarity: BigDecimal("4.3")
            ),
            Achievements::Providers::AchievementDefinition.new(
              external_id: "ACH_LATE", name: "Late Addition", description: nil,
              icon_url: "https://cdn.example/late.jpg", icon_locked_url: "https://cdn.example/late_gray.jpg",
              hidden: false, display_order: 3, rarity: nil
            )
          ],
          unlocks: [
            Achievements::Providers::ProviderUnlock.new(
              achievement_external_id: "ACH_WAKE_UP", unlocked_at: Time.utc(2023, 11, 14, 22, 13, 20)
            )
          ]
        )
      )
      stubs.verify_stubbed_calls
    end

    it "returns nil for a game with an empty schema, without asking for progress" do
      stubs.get(schema_path) { json(game: {}) }

      expect(client.set_with_progress(steam_id, 620)).to be_nil
      stubs.verify_stubbed_calls
    end

    it "raises Private when GetPlayerAchievements answers 403" do
      stubs.get(schema_path) { schema }
      stubs.get(player_path) do
        json(status: 403, playerstats: { error: "Profile is not public", success: false })
      end

      expect { client.set_with_progress(steam_id, 620) }.to raise_error(Achievements::Providers::Private)
    end

    it "raises Private when Steam reports a non-public profile with success: false" do
      stubs.get(schema_path) { schema }
      stubs.get(player_path) { json(playerstats: { error: "Profile is not public", success: false }) }

      expect { client.set_with_progress(steam_id, 620) }.to raise_error(Achievements::Providers::Private)
    end

    it "returns nil when Steam has no stats for the member on this app" do
      stubs.get(schema_path) { schema }
      stubs.get(player_path) do
        json(status: 400, playerstats: { error: "Requested app has no stats", success: false })
      end

      expect(client.set_with_progress(steam_id, 620)).to be_nil
    end
  end

  describe "upstream failures" do
    let(:summary_path) { "/ISteamUser/GetPlayerSummaries/v2/" }
    let(:ok_summary) { json(response: { players: [ { personaname: "Rabscuttle" } ] }) }

    def error_code_for
      client.player_summary(steam_id)
      nil
    rescue described_class::Error => error
      error.code
    end

    def stub_sequence(*responses)
      calls = 0
      stubs.get(summary_path) do
        response = responses.fetch(calls)
        calls += 1
        response.respond_to?(:call) ? response.call : response
      end
      -> { calls }
    end

    it "raises api_unauthorized on HTTP 401 without retrying" do
      calls = stub_sequence(json(status: 401))

      expect(error_code_for).to eq("api_unauthorized")
      expect(calls.call).to eq(1)
    end

    it "raises private_profile on HTTP 403 without retrying" do
      calls = stub_sequence(json(status: 403))

      expect(error_code_for).to eq("private_profile")
      expect(calls.call).to eq(1)
    end

    it "raises api_unavailable on a non-retryable HTTP error without retrying" do
      calls = stub_sequence(json(status: 404))

      expect(error_code_for).to eq("api_unavailable")
      expect(calls.call).to eq(1)
    end

    it "retries a 5xx with exponential backoff and returns the eventual success" do
      calls = stub_sequence(json(status: 502), json(status: 503), ok_summary)

      expect(client.player_summary(steam_id)).to eq(profile_name: "Rabscuttle")
      expect(calls.call).to eq(3)
      expect(sleeps.size).to eq(2)
      expect(sleeps[0]).to be_between(0.5, 0.75)
      expect(sleeps[1]).to be_between(1.0, 1.25)
    end

    it "honours Retry-After on a 429" do
      stub_sequence(json(status: 429, headers: { "Retry-After" => "3" }), ok_summary)

      expect(client.player_summary(steam_id)).to eq(profile_name: "Rabscuttle")
      expect(sleeps.first).to be_between(3.0, 3.25)
    end

    it "raises api_rate_limited once four 429s exhaust the attempts" do
      calls = stub_sequence(*Array.new(4) { json(status: 429) })

      expect(error_code_for).to eq("api_rate_limited")
      expect(calls.call).to eq(4)
    end

    it "raises api_unavailable once four 5xx responses exhaust the attempts" do
      calls = stub_sequence(*Array.new(4) { json(status: 500) })

      expect(error_code_for).to eq("api_unavailable")
      expect(calls.call).to eq(4)
    end

    it "retries network failures and raises api_unavailable when they persist" do
      calls = stub_sequence(*Array.new(4) { -> { raise Faraday::ConnectionFailed, "connection refused" } })

      expect(error_code_for).to eq("api_unavailable")
      expect(calls.call).to eq(4)
    end

    it "treats a malformed JSON body as a retryable failure" do
      stub_sequence([ 200, {}, "<html>oops</html>" ], ok_summary)

      expect(client.player_summary(steam_id)).to eq(profile_name: "Rabscuttle")
    end

    it "spaces consecutive requests at least 250ms apart" do
      stub_sequence(ok_summary, ok_summary)

      client.player_summary(steam_id)
      client.player_summary(steam_id)

      expect(sleeps).to eq([ 0.25 ])
    end
  end

  describe "configuration" do
    around do |example|
      keys = %w[STEAM_WEB_API_KEY STEAM_API_KEY]
      original_values = keys.to_h { |key| [ key, ENV[key] ] }
      keys.each { |key| ENV.delete(key) }
      example.run
    ensure
      original_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "reads the key from STEAM_WEB_API_KEY" do
      ENV["STEAM_WEB_API_KEY"] = "env-key"
      stubs.get("/ISteamUser/GetPlayerSummaries/v2/") do |env|
        expect(env.params["key"]).to eq("env-key")
        json(response: { players: [] })
      end

      described_class.new(http: http, sleeper: sleeper, clock: -> { time[:now] }).player_summary(steam_id)
      stubs.verify_stubbed_calls
    end

    it "raises ConfigurationError when no key is set" do
      expect { described_class.new(http: http, sleeper: sleeper, clock: -> { time[:now] }).player_summary(steam_id) }
        .to raise_error(described_class::ConfigurationError, "STEAM_WEB_API_KEY must be set")
    end
  end
end
