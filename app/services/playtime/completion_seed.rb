# frozen_string_literal: true

module Playtime
  # The launch seed (spec api#457, ADR 0015): each Game Completion's
  # `final_playtime_hrs` becomes Manual Playtime on the Completion's platform
  # ("Other" when it has none), so members' figures aren't empty on launch
  # day. Several Completions of one game on one platform add up.
  #
  # It is for launch day only, and safe to run again after it, since it never
  # adds onto time the member already has:
  # - games a Provider reports Playtime on for that member are skipped, so a
  #   synced game isn't counted twice;
  # - Completions a Playthrough closed are left out, their time being Playtime
  #   already (the Playthrough measured it, or filled the Completion from it);
  # - a platform where the member has their own entry (`origin: member`) is
  #   left alone;
  # - a platform it already seeded (`origin: completion_seed`) is left alone,
  #   so a second run changes nothing.
  # So it only creates entries, marked `origin: completion_seed` with the note
  # "From Game Completion". Members whose row is gone are skipped.
  class CompletionSeed
    NOTE = "From Game Completion"

    Result = Struct.new(:created, :kept, :skipped, keyword_init: true)

    def self.call = new.call

    def call
      result = Result.new(created: 0, kept: 0, skipped: 0)
      groups = completion_hours
      reported = Ledger.provider_reported(user_ids: groups.map(&:first).uniq)
      groups.each do |user_id, game_id, platform_id, hours|
        if reported.include?([ user_id, game_id ])
          result.skipped += 1
          next
        end

        result[seed(user_id, game_id, platform_id, (hours * 60).round)] += 1
      end
      result
    end

    private

    # [user_id, game_id, platform_id, total hours] per member, game and platform.
    def completion_hours
      UserGameCompletion.joins(:user).where("user_game_completions.final_playtime_hrs > 0")
        .where.not(completion_id: UserGamePlaythrough.where.not(completion_id: nil).select(:completion_id))
        .group(:user_id, :gamedb_game_id, :platform_id)
        .pluck(:user_id, :gamedb_game_id, :platform_id, Arel.sql("SUM(user_game_completions.final_playtime_hrs)"))
    end

    # :created, or :kept when the platform already has an entry (the
    # member's own, or one an earlier run seeded).
    def seed(user_id, game_id, platform_id, minutes)
      UserGameManualPlaytime.transaction(requires_new: true) do
        next :kept if UserGameManualPlaytime.exists?(user_id: user_id, gamedb_game_id: game_id, platform_id: platform_id)

        UserGameManualPlaytime.create!(user_id: user_id, gamedb_game_id: game_id, platform_id: platform_id,
          minutes: [ minutes, UserGameManualPlaytime::MAX_MINUTES ].min, origin: "completion_seed", note: NOTE)
        :created
      end
    rescue ActiveRecord::RecordNotUnique
      :kept
    end
  end
end
