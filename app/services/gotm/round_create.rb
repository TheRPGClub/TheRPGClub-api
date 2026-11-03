# frozen_string_literal: true

module Gotm
  # Adds a whole GOTM or NR-GOTM round (every game slot) in one transaction,
  # with the bot's round-setup rules: a positive round number not used yet, a
  # month label, and at least one game, each an existing GameDB game. Slots
  # are numbered in list order from 0. Any invalid game rejects the round.
  class RoundCreate
    # The round can't be created; the message is safe to show the caller.
    class Invalid < StandardError; end

    LABELS = { "gotm" => "GOTM", "nr_gotm" => "NR-GOTM" }.freeze
    # round_number is a 32-bit integer column.
    MAX_ROUND = (2**31) - 1

    def self.label(category) = LABELS.fetch(category.to_s)

    def initialize(category:, round_number:, month_year:, games:)
      @category = category.to_s
      @model = Voting.models_for(@category).fetch(:entry)
      @round_number = round_number
      @month_year = month_year
      @games = games
    end

    # The created entries, in slot order. Raises Invalid, or the model's
    # RecordInvalid for a column-level failure (rolled back either way).
    def call!
      round = parse_round
      month = @month_year.to_s.strip
      raise Invalid, "month_year is required" if month.empty?

      rows = parse_games
      @model.transaction do
        raise Invalid, "#{self.class.label(@category)} round #{round} already exists" if @model.exists?(round_number: round)

        rows.each_with_index.map do |row, index|
          @model.create!(round_number: round, month_year: month, game_index: index, **row)
        end
      end
    end

    private

    def parse_round
      value = Integer(@round_number.to_s, 10, exception: false)
      raise Invalid, "round_number must be a positive integer" unless value&.between?(1, MAX_ROUND)

      value
    end

    def parse_games
      raise Invalid, "games must be a non-empty list" unless @games.is_a?(Array) && @games.any?

      rows = @games.each_with_index.map do |game, index|
        raise Invalid, "Game #{index + 1}: must be an object" unless game.is_a?(Hash)

        game_id = Integer(game["gamedb_game_id"].to_s, 10, exception: false)
        raise Invalid, "Game #{index + 1}: gamedb_game_id is required" unless game_id&.positive?

        { gamedb_game_id: game_id, reddit_url: game["reddit_url"].presence }
      end
      known = GamedbGame.where(game_id: rows.map { |r| r[:gamedb_game_id] }).pluck(:game_id).to_set
      rows.each_with_index do |row, index|
        next if known.include?(row[:gamedb_game_id])

        raise Invalid, "Game #{index + 1}: GameDB game #{row[:gamedb_game_id]} does not exist"
      end
      rows
    end
  end
end
