# frozen_string_literal: true

module Franchises
  # Writes Conquests (GLOSSARY.md "Conquered"; spec api#457, ticket api#461):
  # a member who holds a Game Completion for every Mainline game of a
  # Franchise (Franchises::Progress.mainline_game_ids) and has no Conquest
  # there yet gets one. A Franchise with no Mainline games can't be
  # Conquered. Rows are never removed here.
  #
  # The Conquest is dated by the day the set was finished: for each Mainline
  # game the member's first Completion (by finish day, else when it was
  # logged), and of those the latest, which is also `completion_id`.
  #
  # A new Conquest is announced (Franchises::ConquestAnnouncement) unless the
  # check runs with `announce: false` (Completionator imports, the launch
  # backfill), which also stores `announce: false` on the row.
  #
  #   check = Franchises::ConquestCheck.new(requested_by: user_id)
  #   check.after_completion(completion)   # the member, the game's Franchises
  #   check.for_franchise(franchise)       # every member, one Franchise
  #
  # Both return the new UserFranchiseConquest rows.
  class ConquestCheck
    def initialize(announce: true, requested_by: nil)
      @announce = announce
      @requested_by = requested_by
    end

    # After a Completion is created or updated: its member, in every current
    # Franchise that links its game.
    def after_completion(completion)
      franchise_ids = GamedbGameFranchise.where(game_id: completion.gamedb_game_id).select(:franchise_id)
      GamedbFranchise.current.where(franchise_id: franchise_ids).flat_map do |franchise|
        check(franchise, user_ids: [ completion.user_id ])
      end
    end

    # After a Mainline change or a link: every member, in this Franchise.
    def for_franchise(franchise)
      return [] if franchise.merged?

      check(franchise, user_ids: nil)
    end

    private

    def check(franchise, user_ids:)
      mainline = Progress.mainline_game_ids(franchise.franchise_id)
      return [] if mainline.empty?

      rows = conquerors(franchise, mainline, user_ids)
      return [] if rows.empty?

      ids = UserFranchiseConquest.insert_all(rows, unique_by: :ux_user_franchise_conquests_member, returning: %i[id])
        .rows.flatten
      conquests = UserFranchiseConquest.where(id: ids).order(:conquered_at, :id).preload(:user).to_a
      announce!(franchise, conquests) if @announce
      conquests
    end

    def announce!(franchise, conquests)
      progress = Progress.new(franchise)
      conquests.each do |conquest|
        ConquestAnnouncement.enqueue!(conquest, franchise: franchise, progress: progress, requested_by: @requested_by)
      end
    end

    # The rows to insert for members (among `user_ids`, all when nil) who
    # hold every Mainline game and have no Conquest here yet.
    def conquerors(franchise, mainline, user_ids)
      scope = UserGameCompletion.joins(:user).where(gamedb_game_id: mainline)
        .where.not(user_id: UserFranchiseConquest.where(franchise_id: franchise.franchise_id).select(:user_id))
      scope = scope.where(user_id: user_ids) if user_ids
      finished = Arel.sql("COALESCE(user_game_completions.completed_at, user_game_completions.created_at)")
      now = Time.current

      scope.pluck(:user_id, :gamedb_game_id, :completion_id, finished).group_by(&:first).filter_map do |user_id, list|
        firsts = list.group_by { |row| row[1] }.values.map { |rows| rows.min_by { |row| [ row[3], row[2] ] } }
        next unless firsts.size == mainline.size

        last = firsts.max_by { |row| [ row[3], row[2] ] }
        { user_id: user_id, franchise_id: franchise.franchise_id, conquered_at: last[3], completion_id: last[2],
          announce: @announce, created_at: now, updated_at: now }
      end
    end
  end
end
