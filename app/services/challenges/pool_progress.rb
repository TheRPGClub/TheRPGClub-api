# frozen_string_literal: true

module Challenges
  # A Pool Challenge's progress by game (GET /api/v1/challenges/{id}/pool_progress):
  # for each Pool game, the members who Cleared it and those who have it In
  # Progress, read from the entries of the Runs that count now, so clients
  # need not read every Run.
  #
  # The Runs that count: a Seasonal Challenge's Runs of the Season running
  # today, or while it is Closed, of the last Season; every Run of an Always
  # Open Challenge. A member Cleared a game on a Run of any status (they did
  # Clear it); a game is In Progress only on a Run still counting play (an
  # Active Run, or a Finished one whose window is open), since the entries of
  # Expired and Abandoned Runs are frozen. Each member is named once per game
  # and list, at their earliest Clear.
  module PoolProgress
    # The first and last day of the Season whose Runs count on `today`, or
    # nil for an Always Open Challenge.
    def self.season(challenge, today)
      return nil unless challenge.seasonal?

      schedule = Schedule.for(challenge)
      return schedule.season_on(today) if schedule.open_on?(today)

      schedule.season_on(schedule.season_through(today).first.prev_year)
    end

    def self.runs(challenge, season)
      season ? challenge.runs.where(season_starts_on: season.first) : challenge.runs
    end

    # `{ game_id => { cleared_by: [member], in_progress: [member] } }` for
    # `game_ids`, each member as Challenges.member plus `run_id` (and
    # `cleared_on` when Cleared).
    def self.of(challenge, game_ids, season:, today:)
      progress = game_ids.to_h { |id| [ id, { cleared_by: [], in_progress: [] } ] }
      entries = ChallengeRunEntry.where(run_id: runs(challenge, season).select(:id), game_id: game_ids)
        .preload(run: %i[user challenge]).order(Arel.sql("cleared_on ASC NULLS LAST"), :id)
      entries.group_by(&:game_id).each do |game_id, rows|
        cleared, playing = rows.partition(&:cleared?)
        playing = playing.select { |entry| counting?(entry.run, today) }
        progress[game_id] = {
          cleared_by: cleared.uniq { |entry| entry.run.user_id }.map do |entry|
            Challenges.member(entry.run.user).merge(run_id: entry.run_id, cleared_on: entry.cleared_on&.iso8601)
          end,
          in_progress: playing.uniq { |entry| entry.run.user_id }.map do |entry|
            Challenges.member(entry.run.user).merge(run_id: entry.run_id)
          end
        }
      end
      progress
    end

    def self.counting?(run, today) = run.active? || (run.finished? && run.window.open_on?(today))
    private_class_method :counting?
  end
end
