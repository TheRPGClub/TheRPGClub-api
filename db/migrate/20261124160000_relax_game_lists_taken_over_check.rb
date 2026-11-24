# frozen_string_literal: true

# A taken-over Game List outlives the member it was taken over from: their
# row going nulls `taken_over_from_user_id` (fk_game_lists_taken_over_from,
# on delete nullify), which the old CHECK (both set or both null) refused,
# so the member's delete failed. Now a taken-over list keeps
# `taken_over_at` with no member; a member still needs the time.
class RelaxGameListsTakenOverCheck < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :game_lists, name: "ck_game_lists_taken_over_together"
    add_check_constraint :game_lists, "taken_over_from_user_id IS NULL OR taken_over_at IS NOT NULL",
      name: "ck_game_lists_taken_over_at"
  end

  def down
    remove_check_constraint :game_lists, name: "ck_game_lists_taken_over_at"
    add_check_constraint :game_lists, "(taken_over_from_user_id IS NULL) = (taken_over_at IS NULL)",
      name: "ck_game_lists_taken_over_together"
  end
end
