# frozen_string_literal: true

# Launch data for Playtime and Franchise Progress (spec api#457), run once by
# the deploy's `db:prepare` right after the tables exist:
# 1. Conquests members already hold are written unannounced, before any live
#    Conquest check can post them as new.
# 2. Game Completions' final playtimes become Manual Playtime where no
#    Provider reports Playtime, so day-one totals aren't empty.
# Both are idempotent; the rake tasks `franchise_progress:backfill_conquests`
# and `playtime:seed_from_completions` re-run them by hand.
class BackfillPlaytimeLaunchData < ActiveRecord::Migration[8.1]
  def up
    [ UserFranchiseConquest, UserGameManualPlaytime, UserGamePlaythrough ].each(&:reset_column_information)
    conquests = Franchises::ConquestBackfill.call
    seed = Playtime::CompletionSeed.call
    say "Conquests backfilled: #{conquests}; Manual Playtime seeded: #{seed.created} created, " \
        "#{seed.kept} kept, #{seed.skipped} skipped"
  end

  def down
    # Data only; the table migrations' rollbacks remove it.
  end
end
