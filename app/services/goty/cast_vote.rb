# frozen_string_literal: true

module Goty
  # Casts (or toggles off) a member's vote in one Award of a GOTY Vote (spec
  # api#471, ticket api#474), by the GOTM round's rules (Voting::CastRules):
  # the window, the cap of half the Award's candidates (at least 1) computed
  # at cast time, toggling, oldest-first eviction, and one vote for a tied
  # game on the runoff ballot. Each Award is its own ballot, so a game on
  # several Awards takes a vote in each.
  #
  # The ballot is the Award's frozen candidates (Goty::FreezeCandidates);
  # a cast freezes them first when the sweep has not yet. An Award with a
  # single candidate goes to it uncontested, so it takes no votes.
  module CastVote
    class UnknownAwardError < StandardError; end
    class NotACandidateError < StandardError; end
    class UncontestedError < StandardError; end

    module_function

    def call(year:, award:, user_id:, gamedb_game_id:, now: Time.current)
      award = award.to_s
      raise UnknownAwardError, "unknown Award #{award.inspect}: one of #{Goty::AWARDS.keys.join(', ')}" unless
        Goty::AWARDS.key?(award)

      vote = GotyVote.find(year)
      FreezeCandidates.call(vote, now: now)
      runoff_games = Voting::CastRules.open_ballot!(vote, award, label: label(vote), now: now)
      runoff = !runoff_games.nil?
      game_id = Integer(gamedb_game_id)

      GotyBallotVote.transaction do
        Voting::CastRules.lock!(GotyBallotVote, user_id, "#{vote.year}:#{award}")

        candidates = GotyCandidate.ballot(vote.year, award).pluck(:gamedb_game_id)
        check_candidate!(vote, award, candidates, game_id, runoff_games)

        votes = GotyBallotVote.where(year: vote.year, award: award, user_id: user_id.to_s, runoff: runoff)
          .order(:voted_at, :id).to_a
        cap = runoff ? Voting::CastRules::RUNOFF_CAP : Voting::CastRules.cap(candidates.size)
        Voting::CastRules.apply!(votes, gamedb_game_id: game_id, cap: cap, runoff: runoff) do
          GotyBallotVote.create!(goty_vote: vote, award: award, user_id: user_id.to_s, gamedb_game_id: game_id,
            runoff: runoff)
        end
      end
    end

    # The cap a member has on the Award's ballot open now: one in its runoff,
    # else half its candidates.
    def cap_for(vote, award, now: Time.current)
      return Voting::CastRules::RUNOFF_CAP if runoff_open_for?(vote, award, now)

      Voting::CastRules.cap(GotyCandidate.where(year: vote.year, award: award.to_s).count)
    end

    def runoff_open_for?(vote, award, now = Time.current)
      vote.runoff_open?(now) && Array(vote.pending_ties[award.to_s]).any?
    end

    def label(vote) = "GOTY Vote #{vote.year}"

    def check_candidate!(vote, award, candidates, game_id, runoff_games)
      name = Goty.award_name(award)
      unless candidates.include?(game_id)
        raise NotACandidateError, "game #{game_id} is not a candidate for #{name} #{vote.year}"
      end
      if candidates.one?
        raise UncontestedError, "#{name} #{vote.year} has a single candidate, so it wins without a vote"
      end
      return if runoff_games.nil? || runoff_games.include?(game_id)

      raise Voting::CastRules::GameNotInRunoffError, "game #{game_id} is not one of the games in the #{name} runoff"
    end
  end
end
