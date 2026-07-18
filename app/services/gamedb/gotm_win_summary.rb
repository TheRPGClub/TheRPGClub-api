# frozen_string_literal: true

module Gamedb
  # Derives the round-ordered entry list and the latest `month_year` from a
  # GOTM/NR-GOTM entry set. Extracted out of GamesController so the
  # in-memory-sort logic GamesController#profile relies on to avoid
  # re-querying gotm_entries/nr_gotm_entries (#117, PR #197) gets a real
  # behavioral spec instead of living only in a doc-only request spec.
  class GotmWinSummary
    def initialize(entries)
      @ordered = entries.to_a.sort_by(&:round_number)
    end

    attr_reader :ordered

    def latest_month_year
      ordered.last&.month_year
    end
  end
end
