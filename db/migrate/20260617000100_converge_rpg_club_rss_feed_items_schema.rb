# frozen_string_literal: true

# Converges `rpg_club_rss_feed_items` onto the schema its creating migration
# (20260505002800) always intended: `feed_id, item_id_hash, title, url,
# published_at, created_at`.
#
# That create migration is a no-op (`return if table_exists?`) — the table was
# already present from the Oracle->Neon sync with the *old* column names
# (`item_guid`, `item_link`, `first_seen_at`), so the intended column set never
# actually landed. The new GET/POST `/api/v1/rss_feeds/:id/items` endpoints
# (#93) speak the intended contract (`title`/`url`), so this migration finally
# renames the columns to match.
#
# Lockstep with the bot: GameDB #794's seen-item migration drops the bot's
# direct-SQL `markItemsSeen` (which writes `item_guid`/`item_link`/
# `first_seen_at`) in favour of POSTing to the new endpoint. Until that bot
# deploy lands, the bot's old INSERT breaks — worst case the feed (hourly,
# non-time-critical) re-posts items it already saw. `getSeenItemHashes` only
# reads `item_id_hash`, which is untouched, so reads keep working throughout.
#
# `item_guid` is dropped: dedup is keyed on `item_id_hash` (the PK), so the raw
# guid carries no further value. Existing `item_link`/`first_seen_at` data is
# preserved through the rename; `title` backfills NULL (only matters for the
# display of newly-seen items, which the bot now supplies).
class ConvergeRpgClubRssFeedItemsSchema < ActiveRecord::Migration[8.1]
  TABLE = :rpg_club_rss_feed_items

  def up
    rename_column TABLE, :item_link, :url if column_exists?(TABLE, :item_link)
    change_column TABLE, :url, :string, limit: 2048 if column_exists?(TABLE, :url)

    rename_column TABLE, :first_seen_at, :created_at if column_exists?(TABLE, :first_seen_at)

    add_column TABLE, :title, :string unless column_exists?(TABLE, :title)

    remove_column TABLE, :item_guid if column_exists?(TABLE, :item_guid)
  end

  def down
    add_column TABLE, :item_guid, :string, limit: 512 unless column_exists?(TABLE, :item_guid)

    remove_column TABLE, :title if column_exists?(TABLE, :title)

    rename_column TABLE, :created_at, :first_seen_at if column_exists?(TABLE, :created_at)

    if column_exists?(TABLE, :url)
      change_column TABLE, :url, :string, limit: 512
      rename_column TABLE, :url, :item_link
    end
  end
end
