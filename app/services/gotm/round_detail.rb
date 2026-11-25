# frozen_string_literal: true

module Gotm
  # One closed Round in full, for the Round Page: per Category its winners,
  # its Nominations and, when the round had a vote, the anonymous vote counts
  # and any runoff. Never says who voted.
  #
  # A round is closed when it is in the GOTM History (it has entries in
  # either Category) and is decided (Gotm::RoundHistory.closed?). Winners come
  # from Gotm::RoundHistory (same game shape, NR-GOTM "N/A" placeholders
  # dropped, so a Category can have no winner). Rounds are decided per game,
  # so Nominations are listed one row per game: the game's earliest
  # Nomination, with any later Nominations of the same game as
  # `co_nominations` and the game's vote totals. A winner credits its game's
  # row; `nominations` holds every other row, most votes (then runoff votes)
  # first when the Category had a vote, otherwise in the order they were made.
  #
  # Built in a fixed number of queries, whatever the number of winners,
  # Nominations or votes.
  class RoundDetail
    CATEGORIES = Voting::CATEGORIES.keys.to_h do |kind|
      [ kind, Voting.models_for(kind).values_at(:nomination, :vote) ]
    end.freeze

    # The serialized round, or nil when `round_number` is not a closed round.
    def self.find(round_number)
      new(round_number).payload
    end

    def initialize(round_number)
      @round_number = round_number
    end

    def payload
      neighbours = neighbour_rounds
      return unless neighbours["present"]

      numbers = [ neighbours["previous"], @round_number, neighbours["next"] ].compact
      voting_rounds = VotingRound.where(round_number: numbers).index_by(&:round_number)
      return unless RoundHistory.closed?(voting_rounds[@round_number])

      # Rounds run in order, so only the rounds next to this one can still be
      # open; a neighbour that is not closed has no Round Page to link to.
      previous, following = neighbours.values_at("previous", "next").map do |number|
        number if number && RoundHistory.closed?(voting_rounds[number])
      end

      history = RoundHistory.new.rounds([ @round_number ]).first
      voting_round = voting_rounds[@round_number]
      {
        round_number: @round_number,
        month_year: history.dig(:gotm, :month_year) || history.dig(:nr_gotm, :month_year) || voting_round&.month_year,
        previous:,
        next: following,
        **CATEGORIES.keys.to_h { |kind| [ kind.to_sym, category(kind, history[kind.to_sym], voting_round) ] }
      }
    end

    private

    # Whether the round exists in the GOTM History, and the closest round
    # numbers on either side of it.
    def neighbour_rounds
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, { n: @round_number } ])
        SELECT MAX(round_number) FILTER (WHERE round_number < :n) AS previous,
               MIN(round_number) FILTER (WHERE round_number > :n) AS next,
               COALESCE(BOOL_OR(round_number = :n), FALSE) AS present
        FROM (SELECT round_number FROM gotm_entries UNION ALL SELECT round_number FROM nr_gotm_entries) rounds
      SQL
      ActiveRecord::Base.connection.select_one(sql)
    end

    def category(kind, block, voting_round)
      nomination_model, vote_model = CATEGORIES.fetch(kind)
      nominations = nomination_model.where(round_number: @round_number)
        .preload(:user, game: [ :images, :platforms ])
        .order(:nominated_at, :nomination_id)
        .to_a
      counts = vote_counts(vote_model)
      voted = counts.key?(false)
      runoff_games = Array(voting_round&.runoff_ties&.dig(kind)).map(&:to_i) |
        nominations.select { |nomination| counts.dig(true, nomination.nomination_id) }.map(&:gamedb_game_id)

      # One row per game, led by its earliest Nomination (rounds are decided
      # per game, as in Voting::Tally); a Nomination without a game is a row
      # of its own.
      rows = nominations.group_by { |nomination| nomination.gamedb_game_id || [ :nomination, nomination.nomination_id ] }
        .values
        .map { |row| serialize_row(row, counts, voted, runoff_games) }

      others = rows.dup
      winners = Array(block&.dig(:games)).map do |game|
        credit = others.find { |row| game[:gamedb_game_id] && row[:gamedb_game_id] == game[:gamedb_game_id] }
        others.delete(credit) if credit
        game.merge(nomination: credit)
      end
      if voted
        others = others.each_with_index
          .sort_by { |row, index| [ -row[:votes], -row[:runoff_votes].to_i, index ] }
          .map(&:first)
      end

      {
        month_year: block&.dig(:month_year),
        voting_results_message_id: block&.dig(:voting_results_message_id),
        voted:,
        runoff: runoff_games.any?,
        winners:,
        nominations: others
      }
    end

    # A game's row: its earliest Nomination, the game's other Nominations as
    # `co_nominations`, and the game's vote totals across all of them.
    def serialize_row(row, counts, voted, runoff_games)
      lead, *rest = row
      total = ->(runoff) { row.sum { |nomination| counts.dig(runoff, nomination.nomination_id) || 0 } }
      NominationResource.new(lead).serializable_hash.transform_keys(&:to_sym).merge(
        co_nominations: rest.map do |nomination|
          NominationResource.new(nomination).serializable_hash.transform_keys(&:to_sym)
            .slice(:user_id, :user, :reason, :nominated_at)
        end,
        votes: voted ? total.call(false) : nil,
        runoff_votes: runoff_games.include?(lead.gamedb_game_id) ? total.call(true) : nil
      )
    end

    # `{ runoff => { nomination_id => votes } }` over the round's two ballots.
    def vote_counts(vote_model)
      vote_model.where(round_number: @round_number).vote_counts.group(:runoff).select(:runoff)
        .each_with_object({}) do |row, counts|
          (counts[row.runoff] ||= {})[row.nomination_id] = row["vote_count"].to_i
        end
    end
  end
end
