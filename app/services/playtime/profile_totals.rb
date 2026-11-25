# frozen_string_literal: true

module Playtime
  # A member's Playtime for their profile (spec api#457, ticket api#460): the
  # total over every game they have Playtime on, and each shelf's total, where
  # a shelf counts a game once however many entries it has for it (two
  # Completions of one game, a game collected on two platforms).
  #
  #   Playtime::ProfileTotals.new(user_id, shelves: %i[completed favorites]).to_h
  #   # => { total_minutes: 750, shelves: { completed: 600, favorites: 600 } }
  #
  # One Ledger read for the member, plus one query for the shelves' games
  # when they have any Playtime.
  class ProfileTotals
    SHELVES = {
      completed: UserGameCompletion, backlog: UserGameBacklog, favorites: UserGameFavorite,
      collection: UserGameCollection, now_playing: UserNowPlaying
    }.freeze

    def initialize(user_id, shelves: SHELVES.keys, ledger: nil)
      @user_id = user_id.to_s
      @shelves = SHELVES.keys & shelves
      @ledger = ledger || Ledger.new(user_ids: [ @user_id ])
    end

    def to_h
      { total_minutes: minutes.values.sum, shelves: @shelves.index_with { |shelf| shelf_minutes(shelf) } }
    end

    private

    def minutes = @minutes ||= @ledger.minutes_by_game(@user_id)

    def shelf_minutes(shelf) = shelf_games.fetch(shelf, []).sum { |game_id| minutes.fetch(game_id, 0) }

    # { shelf => [game_id] }, distinct, for the games with Playtime only.
    def shelf_games
      @shelf_games ||= begin
        if minutes.empty? || @shelves.empty?
          {}
        else
          sql = @shelves.map do |shelf|
            SHELVES.fetch(shelf).where(user_id: @user_id, gamedb_game_id: minutes.keys)
              .select(Arel.sql(ApplicationRecord.sanitize_sql([ "? AS shelf", shelf.to_s ])), :gamedb_game_id)
              .distinct.to_sql
          end.join(" UNION ")
          ApplicationRecord.connection.select_rows(sql, "Playtime shelves")
            .group_by(&:first).to_h { |shelf, rows| [ shelf.to_sym, rows.map { |row| row.last.to_i } ] }
        end
      end
    end
  end
end
