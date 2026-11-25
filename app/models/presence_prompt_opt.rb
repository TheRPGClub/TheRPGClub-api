# frozen_string_literal: true

# A user's opt-out from presence prompts (bot parity, #48). The *presence* of a
# row means "do not prompt": scope `ALL` (sentinel `game_title_norm` =
# `__ALL__`) silences every game, while scope `GAME` silences a single
# normalized title. Opting back in is deleting the row. The whole set is
# exposed as one preference document — see PresencePromptOptsController.
class PresencePromptOpt < ApplicationRecord
  self.table_name = "rpg_club_presence_prompt_opts"
  self.primary_key = %i[user_id scope game_title_norm]

  # Sentinel `game_title_norm` stored for an ALL-scope opt-out (the bot's
  # OPT_OUT_ALL_TOKEN).
  ALL_TOKEN = "__ALL__"
  SCOPE_ALL = "ALL"
  SCOPE_GAME = "GAME"

  belongs_to :user, -> { without_images },
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :presence_prompt_opts

  validates :scope, inclusion: { in: [ SCOPE_ALL, SCOPE_GAME ] }

  # Mirror the bot's normalizePresenceGameTitle: lowercase, then strip every
  # character that isn't a-z or 0-9.
  def self.normalize_title(title)
    title.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end
end
