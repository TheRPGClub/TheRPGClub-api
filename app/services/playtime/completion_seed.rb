# frozen_string_literal: true

module Playtime
  # The launch seed (spec api#457, ADR 0015): each Game Completion's
  # `final_playtime_hrs` becomes Manual Playtime on the Completion's platform
  # ("Other" when it has none), so members' figures aren't empty on launch
  # day. Several Completions of one game on one platform add up.
  #
  # Games a Provider reports Playtime on for that member are skipped, so a
  # synced game isn't counted twice. A seeded entry is marked `origin:
  # completion_seed`: it is created with the note "From Game Completion", or,
  # when the member already has an entry on that platform, raised by the
  # Completions' time (their note kept). An entry already marked is left
  # alone, so the seed can run again safely. Members whose row is gone are
  # skipped.
  class CompletionSeed
    NOTE = "From Game Completion"

    Result = Struct.new(:created, :raised, :skipped, keyword_init: true)

    def self.call = new.call

    def call
      result = Result.new(created: 0, raised: 0, skipped: 0)
      groups = completion_hours
      reported = Ledger.provider_reported(user_ids: groups.map(&:first).uniq)
      groups.each do |user_id, game_id, platform_id, hours|
        if reported.include?([ user_id, game_id ])
          result.skipped += 1
          next
        end

        outcome = seed(user_id, game_id, platform_id, (hours * 60).round)
        result[outcome] += 1 if outcome
      end
      result
    end

    private

    # [user_id, game_id, platform_id, total hours] per member, game and platform.
    def completion_hours
      UserGameCompletion.joins(:user).where("user_game_completions.final_playtime_hrs > 0")
        .group(:user_id, :gamedb_game_id, :platform_id)
        .pluck(:user_id, :gamedb_game_id, :platform_id, Arel.sql("SUM(user_game_completions.final_playtime_hrs)"))
    end

    def seed(user_id, game_id, platform_id, minutes)
      UserGameManualPlaytime.transaction do
        entry = UserGameManualPlaytime.lock
          .find_or_initialize_by(user_id: user_id, gamedb_game_id: game_id, platform_id: platform_id)
        next if entry.completion_seed?

        outcome = entry.new_record? ? :created : :raised
        entry.update!(minutes: entry.minutes + minutes, origin: "completion_seed", note: entry.note.presence || NOTE)
        outcome
      end
    end
  end
end
