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

  describe "#played_sets" do
    def completion_entry(game_id, awarded:, hardcore: 0, recent: "2024-05-01 10:00:00")
      {
        "GameID" => game_id, "Title" => "Game #{game_id}", "ImageIcon" => "/Images/0#{game_id}.png",
        "ConsoleID" => 7, "ConsoleName" => "NES/Famicom", "MaxPossible" => 40,
        "NumAwarded" => awarded, "NumAwardedHardcore" => hardcore,
        "MostRecentAwardedDate" => (recent if awarded.positive?),
        "HighestAwardKind" => nil, "HighestAwardDate" => nil
      }
    end

    context "without since (Backfill)" do
      it "lists every set with at least one award from GetUserCompletionProgress, paging by 500" do
        first_page = Array.new(500) { |i| completion_entry(1000 + i, awarded: i.zero? ? 0 : 1) }
        second_page = [ completion_entry(14402, awarded: 3, hardcore: 3, recent: "2024-06-02 21:15:03") ]
        stubs.get("/API/API_GetUserCompletionProgress.php") do |env|
          expect(env.params).to include("u" => ulid, "c" => "500", "y" => "test-key")
          page = env.params["o"] == "0" ? first_page : second_page
          json({ "Count" => page.size, "Total" => 501, "Results" => page })
        end

        sets = client.played_sets(ulid)

        expect(sets.size).to eq(500)
        expect(sets.last).to eq(
          Achievements::Providers::PlayedSet.new(
            external_id: "14402", title: "Game 14402", platform_label: "NES/Famicom",
            icon_url: "https://media.retroachievements.org/Images/014402.png",
            achievements_count: 40, activity_at: Time.utc(2024, 6, 2, 21, 15, 3)
          )
        )
        expect(sets.map(&:external_id)).not_to include("1000")
      end

      it "stops after a short first page" do
        stubs.get("/API/API_GetUserCompletionProgress.php") do |env|
          expect(env.params["o"]).to eq("0")
          json({ "Count" => 1, "Total" => 1, "Results" => [ completion_entry(1, awarded: 1) ] })
        end

        expect(client.played_sets(ulid).map(&:external_id)).to eq([ "1" ])
        stubs.verify_stubbed_calls
      end
    end

    context "with since (incremental)" do
      let(:since) { Time.utc(2024, 6, 1) }

      def recent_entry(game_id, last_played:, achieved: 1, possible: 20)
        {
          "GameID" => game_id, "ConsoleID" => 7, "ConsoleName" => "SNES/Super Famicom", "Title" => "Game #{game_id}",
          "ImageIcon" => "/Images/0#{game_id}.png", "LastPlayed" => last_played,
          "AchievementsTotal" => possible, "NumPossibleAchievements" => possible, "PossibleScore" => 200,
          "NumAchieved" => achieved, "ScoreAchieved" => 10, "NumAchievedHardcore" => 0, "ScoreAchievedHardcore" => 0
        }
      end

      it "pages GetUserRecentlyPlayedGames and stops once LastPlayed is older than since" do
        first_page = Array.new(50) { |i| recent_entry(i + 1, last_played: "2024-06-#{format("%02d", 30 - (i / 2))} 12:00:00") }
        second_page = [
          recent_entry(900, last_played: "2024-06-01 08:00:00"),
          recent_entry(901, last_played: "2024-05-31 23:59:59"),
          recent_entry(902, last_played: "2024-05-20 00:00:00")
        ] + Array.new(47) { |i| recent_entry(1000 + i, last_played: "2024-05-01 00:00:00") }
        requested_offsets = []
        stubs.get("/API/API_GetUserRecentlyPlayedGames.php") do |env|
          expect(env.params).to include("u" => ulid, "c" => "50")
          requested_offsets << env.params["o"]
          json(env.params["o"] == "0" ? first_page : second_page)
        end

        sets = client.played_sets(ulid, since: since)

        expect(requested_offsets).to eq(%w[0 50])
        expect(sets.size).to eq(51)
        expect(sets.last).to eq(
          Achievements::Providers::PlayedSet.new(
            external_id: "900", title: "Game 900", platform_label: "SNES/Super Famicom",
            icon_url: "https://media.retroachievements.org/Images/0900.png",
            achievements_count: 20, activity_at: Time.utc(2024, 6, 1, 8)
          )
        )
      end

      it "skips recently played games with no Unlocks or no Achievements" do
        stubs.get("/API/API_GetUserRecentlyPlayedGames.php") do
          json([
            recent_entry(1, last_played: "2024-06-05 00:00:00"),
            recent_entry(2, last_played: "2024-06-04 00:00:00", achieved: 0),
            recent_entry(3, last_played: "2024-06-03 00:00:00", achieved: 0, possible: 0)
          ])
        end

        expect(client.played_sets(ulid, since: since).map(&:external_id)).to eq([ "1" ])
      end
    end
  end

  describe "#set_with_progress" do
    def achievement(id, order:, awarded:, awarded_hardcore:, **dates)
      {
        "ID" => id, "Title" => "Cheevo #{id}", "Description" => "Do thing #{id}", "Points" => 10,
        "TrueRatio" => 25, "BadgeName" => "1#{id}", "DisplayOrder" => order, "type" => nil,
        "NumAwarded" => awarded, "NumAwardedHardcore" => awarded_hardcore
      }.merge(dates.transform_keys(&:to_s))
    end

    let(:game) do
      {
        "ID" => 14402, "Title" => "Dragon Quest III", "ConsoleID" => 7, "ConsoleName" => "NES/Famicom",
        "ImageIcon" => "/Images/067895.png", "NumDistinctPlayers" => 200,
        "NumDistinctPlayersCasual" => 120, "NumDistinctPlayersHardcore" => 80,
        "UserTotalPlaytime" => 7_290,
        # The RA quirk: Achievements is an object keyed by id, not an array.
        "Achievements" => {
          "101" => achievement(101, order: 2, awarded: 150, awarded_hardcore: 60,
                                    DateEarned: "2024-06-02 20:00:00", DateEarnedHardcore: "2024-06-02 20:00:00"),
          "102" => achievement(102, order: 1, awarded: 9, awarded_hardcore: 1,
                                    DateEarned: "2024-06-03 08:30:00"),
          "103" => achievement(103, order: 3, awarded: 0, awarded_hardcore: 0)
        }
      }
    end

    it "normalises definitions, Rarity, Unlocks with both dates, and playtime" do
      stubs.get("/API/API_GetGameInfoAndUserProgress.php") do |env|
        expect(env.params).to include("g" => "14402", "u" => ulid, "a" => "1", "y" => "test-key")
        json(game)
      end

      set = client.set_with_progress(ulid, 14402)

      expect(set).to have_attributes(
        external_id: "14402", title: "Dragon Quest III", platform_label: "NES/Famicom",
        icon_url: "https://media.retroachievements.org/Images/067895.png",
        playtime_minutes: 121, np_service_name: nil
      )
      expect(set.achievements.first).to eq(
        Achievements::Providers::AchievementDefinition.new(
          external_id: "101", name: "Cheevo 101", description: "Do thing 101",
          icon_url: "https://media.retroachievements.org/Badge/1101.png",
          icon_locked_url: "https://media.retroachievements.org/Badge/1101_lock.png",
          hidden: false, points: 10, tier: nil, display_order: 2,
          rarity: BigDecimal("75.0"), rarity_hardcore: BigDecimal("30.0")
        )
      )
      expect(set.achievements.map { |a| [ a.external_id, a.rarity, a.rarity_hardcore ] }).to eq([
        [ "101", BigDecimal("75"), BigDecimal("30") ],
        [ "102", BigDecimal("4.5"), BigDecimal("0.5") ],
        [ "103", BigDecimal("0"), BigDecimal("0") ]
      ])
      expect(set.unlocks).to contain_exactly(
        Achievements::Providers::ProviderUnlock.new(
          achievement_external_id: "101",
          unlocked_at: Time.utc(2024, 6, 2, 20), hardcore_unlocked_at: Time.utc(2024, 6, 2, 20)
        ),
        Achievements::Providers::ProviderUnlock.new(
          achievement_external_id: "102", unlocked_at: Time.utc(2024, 6, 3, 8, 30), hardcore_unlocked_at: nil
        )
      )
      expect(set.unlocks.find { |u| u.achievement_external_id == "101" }).to be_hardcore
    end

    it "rounds Rarity to two decimals and leaves it nil when the set has no players" do
      game["NumDistinctPlayers"] = 3
      game["Achievements"]["102"]["NumAwarded"] = 1
      stubs.get("/API/API_GetGameInfoAndUserProgress.php") { json(game) }
      expect(client.set_with_progress(ulid, 14402).achievements.find { |a| a.external_id == "102" }.rarity)
        .to eq(BigDecimal("33.33"))

      game["NumDistinctPlayers"] = 0
      expect(client.set_with_progress(ulid, 14402).achievements.map(&:rarity)).to all(be_nil)
    end

    it "uses the hardcore date as the Unlock date when RA only reports a hardcore one" do
      game["Achievements"] = { "101" => achievement(101, order: 1, awarded: 1, awarded_hardcore: 1,
                                                         DateEarnedHardcore: "2024-06-02 20:00:00") }
      stubs.get("/API/API_GetGameInfoAndUserProgress.php") { json(game) }

      unlock = client.set_with_progress(ulid, 14402).unlocks.sole
      expect(unlock).to have_attributes(unlocked_at: Time.utc(2024, 6, 2, 20), hardcore_unlocked_at: Time.utc(2024, 6, 2, 20))
    end

    it "returns an empty set when RA lists no Achievements (an empty array)" do
      stubs.get("/API/API_GetGameInfoAndUserProgress.php") { json(game.merge("Achievements" => [], "UserTotalPlaytime" => nil)) }

      set = client.set_with_progress(ulid, 14402)
      expect(set).to have_attributes(achievements: [], unlocks: [], playtime_minutes: nil)
    end

    it "raises NotFound for an unknown game" do
      stubs.get("/API/API_GetGameInfoAndUserProgress.php") { json({}, status: 404) }

      expect { client.set_with_progress(ulid, 999_999) }.to raise_error(Achievements::Providers::NotFound)
    end
  end

  describe "upstream failures" do
    let(:profile) { { "User" => "Member", "ULID" => ulid, "UserPic" => "/UserPic/Member.png" } }

    def stub_profile_responses(*responses)
      queue = responses.dup
      stubs.get("/API/API_GetUserProfile.php") { queue.shift }
    end

    it "retries a short 429, honouring Retry-After, and returns the eventual success" do
      stub_profile_responses(json({}, status: 429, headers: { "Retry-After" => "2" }), json(profile))

      expect(client.user_profile(ulid)).to include(external_id: ulid)
      expect(sleeps).to eq([ 2.0 ])
    end

    it "raises RateLimited with Retry-After at once when the wait is longer than the client retries" do
      stub_profile_responses(json({}, status: 429, headers: { "Retry-After" => "60" }))

      expect { client.user_profile(ulid) }.to raise_error(Achievements::Providers::RateLimited) { |error|
        expect(error.retry_after).to eq(60.0)
      }
      expect(sleeps).to be_empty
    end

    it "raises RateLimited once repeated 429s exhaust the attempts" do
      stub_profile_responses(*Array.new(3) { json({}, status: 429) })

      expect { client.user_profile(ulid) }.to raise_error(Achievements::Providers::RateLimited) { |error|
        expect(error.retry_after).to be_nil
      }
      expect(sleeps).to eq([ 0.5, 1.0 ])
    end

    it "retries a 5xx and raises Error once the attempts are exhausted" do
      stub_profile_responses(*Array.new(3) { json({}, status: 503) })

      expect { client.user_profile(ulid) }.to raise_error(described_class::Error, /HTTP 503/)
      expect(sleeps).to eq([ 0.5, 1.0 ])
    end

    it "raises Error on a non-transient status without retrying" do
      stub_profile_responses(json({}, status: 401))

      expect { client.user_profile(ulid) }.to raise_error(described_class::Error, /HTTP 401/)
      expect(sleeps).to be_empty
    end

    it "raises ConfigurationError when no API key is set" do
      original = ENV.delete("RETROACHIEVEMENTS_API_KEY")

      expect { described_class.new(http: http, sleeper: sleeper).user_profile(ulid) }
        .to raise_error(described_class::ConfigurationError, "RETROACHIEVEMENTS_API_KEY must be set")
    ensure
      ENV["RETROACHIEVEMENTS_API_KEY"] = original if original
    end
  end
end
