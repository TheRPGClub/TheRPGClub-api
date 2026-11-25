# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261125170000_backfill_playtime_launch_data")

# The deploy runs the Playtime launch data once (spec api#457): existing
# Conquests are written unannounced and Completion playtimes are seeded.
RSpec.describe BackfillPlaytimeLaunchData do
  let(:member) { create(:user) }
  let(:franchise) { create(:franchise) }
  let(:ff1) { create(:game) }
  let(:ff2) { create(:game) }

  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  it "backfills Conquests silently and seeds Manual Playtime, and is safe to run twice" do
    [ ff1, ff2 ].each { |game| GamedbGameFranchise.create!(franchise: franchise, game: game, mainline: true) }
    create(:completion, user: member, game: ff1, final_playtime_hrs: 12.5)
    create(:completion, user: member, game: ff2)

    2.times { migrate_up }

    expect(UserFranchiseConquest.all).to contain_exactly(have_attributes(user_id: member.user_id, announce: false))
    expect(BotJob.where(kind: "franchise_conquest")).to be_empty
    expect(UserGameManualPlaytime.all).to contain_exactly(
      have_attributes(user_id: member.user_id, gamedb_game_id: ff1.game_id, minutes: 750, origin: "completion_seed")
    )
  end
end
