# frozen_string_literal: true

module Goty
  # A GOTY Vote as a Voting::Decide contest: its keys are the Awards, each
  # tallied from its own goty_ballot_votes, and each Award's winner is one
  # goty_winners row. An Award with a single candidate goes to it
  # uncontested; one with none gets no winner.
  class Contest
    attr_reader :record

    def initialize(vote)
      @record = vote
    end

    def label = "GOTY Vote #{record.year}"

    def keys = Goty::AWARDS.keys

    def uncontested(award)
      ids = GotyCandidate.where(year: record.year, award: award).limit(2).pluck(:gamedb_game_id)
      ids.first if ids.one?
    end

    def leaders(award, runoff:)
      Voting::Tally.top(Voting::Tally.count(GotyBallotVote.where(year: record.year, award: award, runoff: runoff)))
    end

    # An Award has one winner, so an admin picks one game (Goty::Decide
    # checks). Idempotent per Award.
    def record_winners!(award, game_ids, decided_by:)
      GotyWinner.find_or_create_by!(year: record.year, award: award) do |winner|
        winner.gamedb_game_id = game_ids.sole
        winner.decided_by = decided_by
      end
      # The game payload's goty_awards is cached on the game's behalf.
      Gamedb::GameRelationsCacheVersion.bump!
    end
  end
end
