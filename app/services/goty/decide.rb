# frozen_string_literal: true

module Goty
  # Decides a GOTY Vote's Awards (spec api#471, ticket api#474) with the GOTM
  # round's steps (Voting::Decide) over Goty::Contest:
  #
  # - #close! once voting has closed: per Award, a lone candidate wins as
  #   `uncontested`, the tally's sole leader by `vote`, an Award nobody voted
  #   in (or with no candidates) gets no winner, and every tied Award goes to
  #   one shared runoff of Voting.runoff_duration.
  # - #close_runoff! once the runoff has closed: a sole leader wins by
  #   `runoff`; an Award that ties again waits for an admin.
  # - #resolve_tie! is the admin's pick (`admin`), also allowed while the
  #   runoff is open.
  #
  # The GOTY Vote is decided once no Award is pending. Each step is
  # idempotent and returns whether it acted; a block runs inside the row
  # lock only when it did (for #resolve_tie!, when it decided the vote), for
  # the lifecycle's outbox events.
  module Decide
    module_function

    def close!(vote, now: Time.current, &)
      FreezeCandidates.call(vote, now: now)
      Voting::Decide.close!(Contest.new(vote), now: now, &)
    end

    def close_runoff!(vote, now: Time.current, &)
      Voting::Decide.close_runoff!(Contest.new(vote), now: now, &)
    end

    def resolve_tie!(vote, award:, gamedb_game_id:, now: Time.current, &)
      picks = Array(gamedb_game_id).map { |id| Integer(id) }.uniq
      raise Voting::Decide::InvalidPickError, "pick exactly one of the tied games" unless picks.one?

      Voting::Decide.resolve_tie!(Contest.new(vote), award.to_s, picks, now: now, &)
    end

    # { award => { gamedb_game_id:, decided_by: } } for the Awards decided so far.
    def winners(vote)
      GotyWinner.where(year: vote.year).pluck(:award, :gamedb_game_id, :decided_by)
        .to_h { |award, game_id, how| [ award, { gamedb_game_id: game_id, decided_by: how } ] }
    end
  end
end
