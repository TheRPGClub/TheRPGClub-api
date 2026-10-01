# frozen_string_literal: true

# A donated game key in the giveaway (bot parity, #42): a donor offers a key
# for a game, and a single user may claim it. The `key_value` is the secret
# code itself — it is never serialized in list responses and is revealed only
# to the claimer on a successful claim (see GameKeysController). No FK
# constraints back the `donor_user_id` / `claimed_by_user_id` columns
# (bot-sourced data), so both user associations are optional and may resolve to
# nil.
#
# `gamedb_game_id` (#42) optionally links the key to a GamedbGame so the API can
# embed its cover/art and metadata. It is nullable: the bot inserts keys with
# only the free-text `game_title` and never sets the id, and not every donated
# game exists in `gamedb_games` — so `game_title` is kept as the always-present
# label/fallback and `game` resolves to nil when the key is unlinked.
#
# `region` (#262) is where the key redeems. It is never null: a key donated
# without one is `Global` (the column default), and legacy rows were backfilled
# to it. The values are pinned by `ck_rpg_club_game_keys_region`.
class RpgClubGameKey < ApplicationRecord
  self.table_name = "rpg_club_game_keys"
  self.primary_key = "key_id"

  REGIONS = %w[Global NA EU UK RU/CIS Asia Unknown].freeze
  DEFAULT_REGION = "Global"

  belongs_to :donor,
    class_name: "RpgClubUser",
    foreign_key: :donor_user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :donated_game_keys
  belongs_to :claimant,
    class_name: "RpgClubUser",
    foreign_key: :claimed_by_user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :claimed_game_keys
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :game_keys

  # The unclaimed keys — the only ones the giveaway listing surfaces (#42).
  scope :available, -> { where(claimed_by_user_id: nil) }

  validates :game_title, :platform, :key_value, :donor_user_id, presence: true
  validates :region, inclusion: { in: REGIONS }
end
