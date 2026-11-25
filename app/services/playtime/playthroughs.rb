# frozen_string_literal: true

module Playtime
  # Starting and ending Playthroughs (spec api#457, ticket api#459; GLOSSARY.md
  # "Playthrough"). A Playthrough's baseline is the member's Playtime when it
  # starts, so its measured time is the Playtime gained since
  # (UserGamePlaythrough#minutes_at). At most one is open per member and game.
  #
  #   Playtime::Playthroughs.start!(user_id:, game_id:)       # raises AlreadyOpen
  #   Playtime::Playthroughs.start_unless_open(user_id:, game_id:)
  #   Playtime::Playthroughs.abandon!(playthrough)                # raises Closed
  #   Playtime::Playthroughs.set_total!(playthrough, minutes)      # raises Closed
  #   Playtime::Playthroughs.close_for_completion!(completion)
  module Playthroughs
    class AlreadyOpen < StandardError; end
    class Closed < StandardError; end

    module_function

    # Opens a Playthrough with the member's Playtime now as its baseline.
    def start!(user_id:, game_id:)
      if UserGamePlaythrough.currently_open.exists?(user_id: user_id, gamedb_game_id: game_id)
        raise AlreadyOpen, "a Playthrough of this game is already open"
      end

      baseline = Ledger.for_game(user_id: user_id, game_id: game_id).total_minutes
      # A savepoint, so losing the race to the unique index leaves an outer
      # transaction usable.
      UserGamePlaythrough.transaction(requires_new: true) do
        UserGamePlaythrough.create!(user_id: user_id, gamedb_game_id: game_id, started_at: Time.current,
          baseline_minutes: baseline)
      end
    rescue ActiveRecord::RecordNotUnique
      raise AlreadyOpen, "a Playthrough of this game is already open"
    end

    # Opens one when none is open (adding a game to Now Playing); nil otherwise.
    def start_unless_open(user_id:, game_id:)
      start!(user_id: user_id, game_id: game_id)
    rescue AlreadyOpen
      nil
    end

    # Ends it as abandoned, keeping its time.
    def abandon!(playthrough)
      finish!(playthrough, "abandoned")
    end

    # Sets its time by hand; nil goes back to the measured time.
    def set_total!(playthrough, minutes)
      playthrough.with_lock do
        raise Closed, "this Playthrough has ended" unless playthrough.open?

        playthrough.update!(manual_total_minutes: minutes)
      end
      playthrough
    end

    # A Game Completion was logged: the member's open Playthrough of the game,
    # if any, ends as completed with the Completion and its time. An empty
    # `final_playtime_hrs` on the Completion takes that time in hours (2
    # decimals); a value the member gave wins. Runs inside the Completion's
    # create transaction.
    def close_for_completion!(completion)
      playthrough = UserGamePlaythrough.currently_open.lock
        .find_by(user_id: completion.user_id, gamedb_game_id: completion.gamedb_game_id)
      return unless playthrough

      finish!(playthrough, "completed", completion_id: completion.completion_id)
      return unless completion.final_playtime_hrs.nil?

      # Skips callbacks: the Completion's own commit runs them.
      completion.update_columns(final_playtime_hrs: (playthrough.final_minutes / 60.0).round(2))
    end

    # Locks and re-reads it first, so a Playthrough another request (a
    # Completion, an abandon) just ended is never ended again.
    def finish!(playthrough, reason, completion_id: nil)
      playthrough.with_lock do
        raise Closed, "this Playthrough has ended" unless playthrough.open?

        playtime = Ledger.for_game(user_id: playthrough.user_id, game_id: playthrough.gamedb_game_id).total_minutes
        minutes = playthrough.minutes_at(playtime)
        playthrough.update!(ended_at: Time.current, end_reason: reason, completion_id: completion_id,
          final_minutes: minutes)
      end
      playthrough
    end
    private_class_method :finish!
  end
end
