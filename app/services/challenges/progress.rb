# frozen_string_literal: true

module Challenges
  # Run progress (spec #376, "Progress module"; docs/adr/0009): a Run's
  # entries come only from the member's Game Completions and Now Playing.
  #
  #   Challenges::Progress.refresh(user_id)  # => [Change]
  #
  # brings every Run of the member that can still change up to date and
  # returns the Runs whose status changed, so the caller can queue their
  # announcements (Challenges.refresh_runs! does both). It runs after every
  # commit that writes a Game Completion or Now Playing entry, whatever wrote
  # it (Challenges::CountsTowardRuns), and when a Run starts.
  #
  # Which games count, and when the goal is reached, depend on the Challenge
  # Format: each Format module (Challenges::Formats) answers
  #
  #   count(run, plays)       the games the Run counts now, as
  #                           Challenges::Counted, from the member's plays
  #                           inside its window (Challenges::InWindow); a
  #                           Format may keep the Run's hand-made entries
  #   summary(run, entries)   a Summary of the entries (Counted or stored)
  #
  # Slots (Challenges::Formats::Slots) keeps each game's slot year on the
  # entry, and a game the member moved (`picked_by_hand`) stays there while
  # it still holds.
  #
  # What stays the same for every Format lives here:
  # - The window (Challenges::Window) and what counts inside it
  #   (Challenges::Plays).
  # - Active Runs follow their member's records both ways: a deleted Game
  #   Completion un-Clears a game, and a game leaving Now Playing stops being
  #   In Progress.
  # - Finished is final. A Finished Run never goes back to Active, and its
  #   Cleared games stay Cleared even when their Game Completion is deleted,
  #   but until its window ends it keeps counting new play, so a member may
  #   play past a Pool's target.
  # - An Active Run whose goal is reached becomes Finished (Change event
  #   "run_finished"). One that becomes Caught Up (Slots) is announced
  #   (Change event "run_caught_up") once a year at most: Caught Up is worked
  #   out from the entries, never stored, and the Run only remembers the
  #   year it was last announced.
  module Progress
    # How far a Run is: games In Progress and Cleared, against the `target`
    # number of Cleared games, and whether the goal is reached. A Format
    # whose Runs can be Caught Up (Slots) says whether this one is, and it
    # is then served too; for the others it is nil.
    Summary = Data.define(:in_progress, :cleared, :target, :goal_reached, :caught_up) do
      def initialize(caught_up: nil, **) = super

      def as_json(*)
        json = { in_progress: in_progress, cleared: cleared, target: target }
        caught_up.nil? ? json : json.merge(caught_up: caught_up)
      end
    end

    # A Run whose status changed, and the announcement event for it.
    Change = Data.define(:run, :event)

    def self.refresh(user_id, now: Time.current)
      today = Challenges.today(now)
      ChallengeRun.transaction do
        runs = refreshable(user_id, today)
        plays = Plays.of(user_id) if runs.any?
        runs.filter_map { |run| refresh_run(run, plays, now, today) }
      end
    end

    # A Run's progress from its stored entries.
    def self.summary(run) = run.challenge.format_rules.summary(run, run.entries)

    # The member's Active Runs, and their Finished Runs whose window has not
    # ended, locked for the refresh.
    def self.refreshable(user_id, today)
      ChallengeRun.where(user_id: user_id)
        .where("status = 'active' OR (status = 'finished' AND (season_ends_on IS NULL OR season_ends_on >= ?))", today)
        .preload(:entries, :edition, challenge: [ :pool_franchises, :pool_collections, :pool_games ])
        .order(:id).lock.to_a
        .select { |run| run.active? || run.window.open_on?(today) }
    end
    private_class_method :refreshable

    def self.refresh_run(run, plays, now, today)
      format = run.challenge.format_rules
      counted = format.count(run, plays.within(run.window))
      counted = keep_cleared(run, counted) if run.finished?
      write_entries(run, counted)
      return unless run.active?

      summary = format.summary(run, counted)
      if summary.goal_reached
        run.update!(status: "finished", ended_at: now)
        Change.new(run: run, event: "run_finished")
      elsif summary.caught_up && run.caught_up_announced_year != today.year
        run.update!(caught_up_announced_year: today.year)
        Change.new(run: run, event: "run_caught_up")
      end
    end
    private_class_method :refresh_run

    # A Finished Run's stored Cleared games, over what would replace them.
    def self.keep_cleared(run, counted)
      by_game = counted.index_by(&:game_id)
      run.entries.select(&:cleared?).each do |entry|
        next if by_game[entry.game_id]&.cleared?

        by_game[entry.game_id] = Counted.cleared(entry.game_id, entry.completion_id, entry.cleared_on)
          .with(slot_year: entry.slot_year, picked_by_hand: entry.picked_by_hand)
      end
      by_game.values
    end
    private_class_method :keep_cleared

    # Writes `counted` as the Run's entries, touching only the rows that
    # change.
    def self.write_entries(run, counted)
      stored = run.entries.index_by(&:game_id)
      wanted = counted.index_by(&:game_id)
      gone = stored.keys - wanted.keys
      ChallengeRunEntry.where(run_id: run.id, game_id: gone).delete_all if gone.any?
      rows = wanted.values.reject { |entry| same?(stored[entry.game_id], entry) }.map do |entry|
        { run_id: run.id, game_id: entry.game_id, state: entry.state, completion_id: entry.completion_id,
          cleared_on: entry.cleared_on, slot_year: entry.slot_year, picked_by_hand: entry.picked_by_hand }
      end
      ChallengeRunEntry.upsert_all(rows, unique_by: :ux_challenge_run_entries_game) if rows.any?
      run.entries.reset if gone.any? || rows.any?
    end
    private_class_method :write_entries

    def self.same?(row, entry)
      row && row.state == entry.state && row.completion_id == entry.completion_id &&
        row.cleared_on == entry.cleared_on && row.slot_year == entry.slot_year && row.picked_by_hand == entry.picked_by_hand
    end
    private_class_method :same?
  end
end
