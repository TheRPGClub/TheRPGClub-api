# frozen_string_literal: true

module Goty
  # The payload of a GOTY Vote outbox event (VotingEvent::GOTY_KINDS), so the
  # bot can post without another call. Every kind carries the same shape,
  # captured when the event is queued:
  #
  #   { kind, year, name: "GOTY Vote 2026", nominations_open_at,
  #     voting_opens_at, voting_closes_at, runoff_opens_at, runoff_closes_at,
  #     decided_at, nomination_cap, days_before (reminders; else null),
  #     awards: [{ award, name, cap, uncontested, runoff_ballot, pending_tie,
  #                games: [{ gamedb_game_id, title, cover_url, votes, runoff_votes }],
  #                winner: { gamedb_game_id, title, cover_url, decided_by } | nil }] }
  #
  # `games` is the Award's ballot: the live one while nominating (Game of the
  # Year: the games nominated so far), the frozen candidates from voting
  # open. `votes` is null until the main vote has closed; `runoff_votes` is
  # null until the runoff (if any) has closed or the vote is decided. Counts
  # are anonymous; voters are never named in a payload.
  module EventPayload
    module_function

    def for(vote, kind, days_before: nil)
      ballots = Goty::Standings.ballots(vote)
      winners = GotyWinner.where(year: vote.year).index_by(&:award)
      games = GamedbGame.where(game_id: ballots.values.flatten | winners.values.map(&:gamedb_game_id))
        .preload(:images).index_by(&:game_id)
      counts = GotyBallotVote.where(year: vote.year).group(:award, :runoff, :gamedb_game_id).count

      {
        kind: kind, year: vote.year, name: "GOTY Vote #{vote.year}",
        nominations_open_at: vote.nominations_open_at, voting_opens_at: vote.voting_opens_at,
        voting_closes_at: vote.voting_closes_at, runoff_opens_at: vote.runoff_opens_at,
        runoff_closes_at: vote.runoff_closes_at, decided_at: vote.decided_at,
        nomination_cap: Goty::Nominate::CAP, days_before: days_before,
        awards: ballots.map { |award, ids| award(vote, award, ids, games, winners[award], counts) }
      }
    end

    def award(vote, award, ids, games, winner, counts)
      main_closed = vote.closed_at.present?
      runoff_closed = vote.runoff_closed_at.present? || vote.decided_at.present?
      {
        award: award, name: Goty.award_name(award),
        cap: Voting::CastRules.cap(ids.size), uncontested: ids.one?,
        runoff_ballot: Array(vote.runoff_ties[award]), pending_tie: Array(vote.pending_ties[award]),
        games: ids.filter_map do |id|
          game(games[id])&.merge(
            votes: main_closed ? counts.fetch([ award, false, id ], 0) : nil,
            runoff_votes: runoff_closed ? counts.fetch([ award, true, id ], 0) : nil
          )
        end,
        winner: winner && game(games[winner.gamedb_game_id])&.merge(decided_by: winner.decided_by)
      }
    end

    def game(game)
      game && { gamedb_game_id: game.game_id, title: game.title, cover_url: game.cover_url }
    end
  end
end
