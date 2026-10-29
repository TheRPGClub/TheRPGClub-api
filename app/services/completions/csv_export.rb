# frozen_string_literal: true

require "csv"

module Completions
  # Renders a user's completions as the CSV the Discord bot's
  # `/game-completion export` produces (`completion-export.service.ts`): same
  # columns in the same order, the completion date as a UTC `YYYY-MM-DD`, and
  # `created_at` as a millisecond ISO-8601 UTC timestamp (JS `toISOString`).
  # Quoting is RFC 4180 via Ruby's CSV, so fields are quoted only when they
  # contain a comma, quote or line break.
  class CsvExport
    HEADER = [ "ID", "Game ID", "Title", "Type", "Platform ID", "Completed Date", "Playtime (Hours)", "Note",
               "Created At" ].freeze

    def initialize(completions)
      @completions = completions
    end

    def to_csv
      CSV.generate(row_sep: "\n") do |csv|
        csv << HEADER
        @completions.each { |completion| csv << row(completion) }
      end
    end

    private

    def row(completion)
      [
        completion.completion_id,
        completion.gamedb_game_id,
        completion.game&.title,
        completion.completion_type,
        completion.platform_id,
        completion.completed_at&.utc&.to_date&.iso8601,
        playtime(completion.final_playtime_hrs),
        completion.note,
        completion.created_at&.utc&.iso8601(3)
      ]
    end

    # A JS number prints without a trailing `.0`, so 40.00 renders as `40`.
    def playtime(value)
      return nil if value.nil?

      value.frac.zero? ? value.to_i.to_s : value.to_s("F")
    end
  end
end
