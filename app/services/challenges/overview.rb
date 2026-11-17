# frozen_string_literal: true

module Challenges
  # What a Challenge shows on a list flyer besides its own columns: how many
  # Runs it has (any status), how many Finished, and its first Pool games
  # (Challenges::PoolCovers; empty for Slots and Assignment). Read for a whole
  # page of Challenges in a fixed number of queries (ChallengeResource).
  Overview = Data.define(:challenge_ids, :run_counts, :finished_counts, :pool_games) do
    # Pool games each Challenge carries.
    def self.pool_games_shown = 4

    def self.of(challenges)
      ids = challenges.map(&:id)
      counts = ids.empty? ? {} : ChallengeRun.where(challenge_id: ids).group(:challenge_id, :status).count
      pools = challenges.select { |challenge| challenge.challenge_format == Formats::Pool::KEY }.map(&:id)
      runs = Hash.new(0)
      finished = Hash.new(0)
      counts.each do |(id, status), count|
        runs[id] += count
        finished[id] += count if status == "finished"
      end
      new(challenge_ids: ids, run_counts: runs, finished_counts: finished,
        pool_games: PoolCovers.of(pools, limit: pool_games_shown))
    end

    # Whether it was read for `challenge`.
    def covers?(challenge) = challenge_ids.include?(challenge.id)

    def run_count(challenge) = run_counts[challenge.id]

    def finished_count(challenge) = finished_counts[challenge.id]

    def pool_games_of(challenge) = pool_games.fetch(challenge.id, [])
  end
end
