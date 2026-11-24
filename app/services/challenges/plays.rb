# frozen_string_literal: true

module Challenges
  # What a member has played, read once per refresh (Challenges::Progress):
  # their dated Game Completions and their Now Playing. `within(window)`
  # narrows it to what counts toward one Run (spec #376, "Counting rules"):
  #
  #   Cleared      a Game Completion dated inside the window (its earliest
  #                there). An undated Game Completion never counts by itself.
  #   In Progress  a game in Now Playing, added on or before the window's
  #                last day, that is not Cleared. There is no Now Playing
  #                history, so a game that left Now Playing no longer counts.
  #   Earlier      a Game Completion dated before the window, or undated. It
  #                never counts by itself; with Counts past play a member
  #                may pick it for a Slots slot (Formats::Slots.pick!).
  #
  # A Game Completion's date and a Now Playing start are both the club day of
  # the stored moment (ClubDay.day_of; Game Completion days are stored at noon
  # club time, spec api#451).
  Plays = Data.define(:completions, :now_playing) do
    def self.of(user_id)
      completions = UserGameCompletion.where(user_id: user_id)
        .order(:completed_at, :completion_id).pluck(:completion_id, :gamedb_game_id, :completed_at)
        .map { |id, game_id, at| [ id, game_id, ClubDay.day_of(at) ] }
      now_playing = UserNowPlaying.where(user_id: user_id).where.not(gamedb_game_id: nil)
        .pluck(:gamedb_game_id, :added_at).map { |game_id, at| [ game_id, ClubDay.day_of(at) ] }
      new(completions: completions, now_playing: now_playing)
    end

    def within(window)
      cleared = {}
      earlier = {}
      completions.each do |id, game_id, date|
        if date && window.include?(date)
          cleared[game_id] ||= Counted.cleared(game_id, id, date)
        elsif date.nil? || date < window.starts_on
          earlier[id] = Counted.cleared(game_id, id, date)
        end
      end
      in_progress = now_playing.filter_map do |game_id, added_on|
        game_id if !cleared.key?(game_id) && (window.ends_on.nil? || added_on <= window.ends_on)
      end
      InWindow.new(cleared: cleared, in_progress: in_progress.uniq, earlier: earlier)
    end
  end
end
