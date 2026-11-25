# frozen_string_literal: true

module Goty
  # A GOTY Vote's live ballots: for GOTM and NR-GOTM of the Year, every winner
  # recorded in gotm_entries / nr_gotm_entries for a round labelled with a
  # month of the year (its `month_year`, the month the club plays the game),
  # in round order, each game once. A round with several winners puts them
  # all on. NR-GOTM "N/A" placeholder games are left out, as in round history.
  #
  # Game of the Year is every game members nominated for the year, each once,
  # in the order first nominated. These are the ballots while nominating; at
  # voting open they are frozen into candidates, which the vote then reads.
  module Ballots
    ENTRY_MODELS = { "gotm" => GotmEntry, "nr_gotm" => NrGotmEntry }.freeze
    # A four-digit year standing on its own, so "Round 12345" has none.
    YEAR_PATTERN = /(?<!\d)((?:19|20)\d{2})(?!\d)/

    module_function

    # { award => [gamedb_game_id, ...] } for every Award, in Goty::AWARDS order.
    def for(year)
      year = Integer(year)
      Goty::AWARDS.keys.index_with { |award| game_ids(year, award) }
    end

    def game_ids(year, award)
      return nominated_game_ids(year) if award.to_s == "game_of_the_year"

      model = ENTRY_MODELS[award.to_s]
      return [] if model.nil?

      # Older rows may be labelled in other formats, so the LIKE only narrows
      # the scan and round_year has the last word.
      model.where.not(gamedb_game_id: nil)
        .where("month_year LIKE ?", "%#{year}%")
        .left_joins(:game).where("TRIM(LOWER(COALESCE(gamedb_games.title, ''))) <> ?", Gotm::RoundHistory::PLACEHOLDER_TITLE)
        .order(:round_number, :game_index)
        .pluck(:month_year, :gamedb_game_id)
        .select { |label, _| round_year(label) == year }
        .map(&:last).uniq
    end

    def nominated_game_ids(year)
      GotyNomination.where(year: year).group(:gamedb_game_id)
        .order(Arel.sql("MIN(nominated_at)"), :gamedb_game_id).pluck(:gamedb_game_id)
    end

    # The year a round counts toward, from its `month_year` label ("March
    # 2026", "Mar 2026", "2026-03", "03/2026"); nil when the label has none.
    # The last standalone year wins.
    def round_year(month_year)
      match = month_year.to_s.scan(YEAR_PATTERN).last
      match && Integer(match.first, 10)
    end
  end
end
