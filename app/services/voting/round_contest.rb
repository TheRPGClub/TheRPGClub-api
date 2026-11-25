# frozen_string_literal: true

module Voting
  # A GOTM round as a Voting::Decide contest: its keys are the categories,
  # tallied from each category's vote table, and winners go into the entry
  # tables (Voting::Winners). A round never goes uncontested: a category
  # with one nominated game still votes, as it always has.
  class RoundContest
    attr_reader :record

    def initialize(round)
      @record = round
    end

    def label = "round #{record.round_number}"

    def keys = Voting::CATEGORIES.keys

    def uncontested(_category) = nil

    def leaders(category, runoff:)
      Tally.leaders(Voting.models_for(category).fetch(:vote), record.round_number, runoff: runoff)
    end

    # Entries carry no decided_by; how a round was decided lives in its
    # events and timestamps.
    def record_winners!(category, game_ids, decided_by:) # rubocop:disable Lint/UnusedMethodArgument
      Winners.record!(Voting.models_for(category).fetch(:entry), record, game_ids)
    end
  end
end
