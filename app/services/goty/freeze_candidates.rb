# frozen_string_literal: true

module Goty
  # Freezes each Award's candidates when a GOTY Vote's voting opens (spec
  # api#471): GOTM and NR-GOTM of the Year take the year's round winners,
  # Game of the Year the distinct nominated games re-checked for
  # eligibility, so a game whose release staff corrected since it was
  # nominated drops off. One row per Award and game, in ballot order; the
  # tally, the cap and the history read these.
  #
  # Runs once: `candidates_frozen_at` marks it, so a second call (the sweep
  # running late or twice, a cast racing it) changes nothing. Before voting
  # opens it does nothing. Returns whether this call froze.
  module FreezeCandidates
    module_function

    def call(vote, now: Time.current)
      vote.with_lock do
        next false if vote.candidates_frozen_at.present? || now < vote.voting_opens_at

        Goty::Ballots.for(vote.year).each do |award, game_ids|
          game_ids = eligible(game_ids, vote.year) if award == "game_of_the_year"
          game_ids.each_with_index do |game_id, position|
            GotyCandidate.create!(year: vote.year, award: award, gamedb_game_id: game_id, position: position)
          end
        end
        vote.update!(candidates_frozen_at: now)
        true
      end
    end

    def eligible(game_ids, year)
      results = Goty::Eligibility.check_all(game_ids, year)
      game_ids.select { |id| results.fetch(id).eligible? }
    end
  end
end
