# frozen_string_literal: true

require "rails_helper"
require "rake"

# The launch seed (spec api#457, ticket api#458; ADR 0015): Game Completions'
# final playtimes become Manual Playtime, only on games no Provider reports
# Playtime for that member, so synced games are not counted twice.
RSpec.describe "playtime:seed_from_completions" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["playtime:seed_from_completions"] }
  let(:member) { create(:user) }
  let(:platform) { create(:platform) }

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("playtime:seed_from_completions") }

  before { task.reenable }

  def run_seed
    expect { task.invoke }.to output(/Seeded Manual Playtime/).to_stdout
    task.reenable
  end

  def entries = UserGameManualPlaytime.order(:id).map { |entry| entry.slice(:user_id, :gamedb_game_id, :platform_id, :minutes, :origin, :note).symbolize_keys }

  it "adds up a game's Completions per platform, once however often it runs" do
    game = create(:game)
    create(:completion, user: member, game: game, platform: platform, final_playtime_hrs: 10.5)
    create(:completion, user: member, game: game, platform: platform, final_playtime_hrs: 2)
    create(:completion, user: member, game: game, platform: nil, final_playtime_hrs: 1.25)
    create(:completion, user: member, game: create(:game), platform: platform, final_playtime_hrs: nil)

    run_seed
    run_seed

    expect(entries).to contain_exactly(
      { user_id: member.user_id, gamedb_game_id: game.game_id, platform_id: platform.platform_id, minutes: 750,
        origin: "completion_seed", note: "From Game Completion" },
      { user_id: member.user_id, gamedb_game_id: game.game_id, platform_id: nil, minutes: 75,
        origin: "completion_seed", note: "From Game Completion" }
    )
  end

  it "leaves a member's own entry on that platform alone" do
    game = create(:game)
    create(:manual_playtime, user: member, game: game, platform: platform, minutes: 30, note: "save file")
    create(:completion, user: member, game: game, platform: platform, final_playtime_hrs: 1)

    run_seed

    expect(entries).to contain_exactly(include(minutes: 30, origin: "member", note: "save file"))
  end

  it "skips a Completion a Playthrough filled, its time already being Playtime" do
    game = create(:game)
    create(:manual_playtime, user: member, game: game, platform: platform, minutes: 600, origin: "completion_seed")
    filled = create(:completion, user: member, game: game, platform: platform, final_playtime_hrs: 4)
    create(:playthrough, user: member, game: game, ended_at: Time.current, end_reason: "completed",
      completion_id: filled.completion_id, final_minutes: 240)
    other_game = create(:game)
    other_filled = create(:completion, user: member, game: other_game, platform: platform, final_playtime_hrs: 2)
    create(:playthrough, user: member, game: other_game, ended_at: Time.current, end_reason: "completed",
      completion_id: other_filled.completion_id, final_minutes: 120)

    run_seed

    expect(entries).to contain_exactly(include(gamedb_game_id: game.game_id, minutes: 600))
  end

  it "skips a game a Provider reports Playtime on for that member" do
    game = create(:game)
    set = create(:achievement_set, game: game, platform_label: "PC")
    create(:user_achievement_set_progress, linked_account: create(:user_linked_account, user: member),
      achievement_set: set, playtime_minutes: 300)
    create(:completion, user: member, game: game, platform: platform, final_playtime_hrs: 10)
    friend_completion = create(:completion, game: game, platform: platform, final_playtime_hrs: 3)

    run_seed

    expect(entries).to contain_exactly(include(user_id: friend_completion.user_id, minutes: 180))
  end
end
