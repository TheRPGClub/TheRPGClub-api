# frozen_string_literal: true

module Voting
  # Writes a round's winners into gotm_entries / nr_gotm_entries, the tables
  # the rest of the app (and the bot) read winners from.
  module Winners
    module_function

    # The recorded winners per category, e.g. { "gotm" => [12], "nr_gotm" => [34] };
    # a category with no winner is left out.
    def for_round(round_number)
      Voting::CATEGORIES.each_key.with_object({}) do |category, found|
        ids = Voting.models_for(category).fetch(:entry).where(round_number: round_number)
          .order(:game_index).pluck(:gamedb_game_id)
        found[category] = ids if ids.any?
      end
    end

    # Appends after any slot already recorded for the round, so an admin's
    # manual entry is never overwritten. game_index counts from 0, as the
    # bot's round-setup wizard wrote it.
    def record!(entry_model, round, gamedb_game_ids)
      existing = entry_model.where(round_number: round.round_number)
      taken = existing.pluck(:gamedb_game_id)
      next_index = (existing.maximum(:game_index) || -1) + 1

      (gamedb_game_ids - taken).each_with_index do |game_id, offset|
        entry_model.create!(
          round_number: round.round_number,
          month_year: round.month_year,
          game_index: next_index + offset,
          gamedb_game_id: game_id
        )
      end
      # GameResource's gotm_won / nr_gotm_won are cached on other games'
      # behalf; see GotmEntriesController#create.
      Gamedb::GameRelationsCacheVersion.bump!
    end
  end
end
