# frozen_string_literal: true

module Goty
  # Each Award of a GOTY Vote as a member sees it (GET /goty_votes/:year),
  # with the GOTM round's visibility: anyone sees the ballot and their own
  # votes and cap; the counts stay hidden from members while that ballot is
  # open (staff see them), and once the GOTY Vote is decided the full result
  # names every voter.
  #
  # The ballot is the frozen candidates once voting has opened, else the
  # live ballot (Goty::Ballots).
  module Standings
    module_function

    # `viewer_id` is the member whose own votes are shown (nil for none);
    # `staff` sees the counts while the ballots are open.
    def awards(vote, viewer_id: nil, staff: false, now: Time.current)
      ballots = ballots(vote)
      votes = GotyBallotVote.where(year: vote.year).pluck(:award, :gamedb_game_id, :runoff, :user_id)
      winners = GotyWinner.where(year: vote.year).index_by(&:award)
      games = games_for(ballots.values.flatten | winners.values.map(&:gamedb_game_id))
      users = vote.decided_at ? users_for(votes.map(&:last).uniq) : {}
      hidden = !staff && !vote.voting_ended?(now)
      runoff_hidden = !staff && (hidden || vote.runoff_open?(now))

      ballots.map do |award, ids|
        mine = votes.select { |row| row[0] == award && viewer_id && row[3] == viewer_id.to_s }
        rows = votes.select { |row| row[0] == award }
        {
          award: award, name: Goty.award_name(award),
          ballot: ids.filter_map { |id| games[id] }.map { |game| GameSummaryResource.new(game).serializable_hash },
          cap: cap(vote, award, ids.size, now),
          runoff_ballot: Array(vote.runoff_ties[award]),
          pending_tie: Array(vote.pending_ties[award]),
          own_votes: mine.reject { |row| row[2] }.map { |row| row[1] },
          own_runoff_votes: mine.select { |row| row[2] }.map { |row| row[1] },
          tally: tally(ids, rows, hidden, runoff_hidden),
          result: vote.decided_at ? result(ids, rows, users) : nil,
          winner: winner(winners[award], games)
        }
      end
    end

    def ballots(vote)
      return Goty::Ballots.for(vote.year) if vote.candidates_frozen_at.nil?

      frozen = GotyCandidate.where(year: vote.year).order(:position).pluck(:award, :gamedb_game_id)
      Goty::AWARDS.keys.index_with { |award| frozen.select { |row| row[0] == award }.map(&:last) }
    end

    def cap(vote, award, size, now)
      return Voting::CastRules::RUNOFF_CAP if Goty::CastVote.runoff_open_for?(vote, award, now)

      Voting::CastRules.cap(size)
    end

    # Every candidate in ballot order with its votes on each ballot; empty
    # while the main counts are hidden. Runoff counts read 0 while hidden.
    def tally(ids, rows, hidden, runoff_hidden)
      games = hidden ? [] : ids.map do |id|
        { gamedb_game_id: id, votes: count(rows, id, false),
          runoff_votes: runoff_hidden ? 0 : count(rows, id, true) }
      end
      { counts_hidden: hidden, runoff_counts_hidden: runoff_hidden, games: games }
    end

    def result(ids, rows, users)
      ids.map do |id|
        { gamedb_game_id: id, votes: count(rows, id, false), runoff_votes: count(rows, id, true),
          voters: voters(rows, id, false, users), runoff_voters: voters(rows, id, true, users) }
      end
    end

    def winner(row, games)
      return nil if row.nil?

      game = games[row.gamedb_game_id]
      { gamedb_game_id: row.gamedb_game_id, decided_by: row.decided_by,
        game: game && GameSummaryResource.new(game).serializable_hash }
    end

    def count(rows, id, runoff)
      rows.count { |row| row[1] == id && row[2] == runoff }
    end

    def voters(rows, id, runoff, users)
      rows.select { |row| row[1] == id && row[2] == runoff }.filter_map { |row| users[row[3]] }
        .map { |user| UserSummaryResource.new(user).serializable_hash }
    end

    def games_for(ids)
      return {} if ids.empty?

      GamedbGame.where(game_id: ids).preload(:images).index_by(&:game_id)
    end

    def users_for(ids)
      return {} if ids.empty?

      RpgClubUser.without_images.where(user_id: ids).index_by(&:user_id)
    end
  end
end
