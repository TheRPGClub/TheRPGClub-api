# frozen_string_literal: true

# Fixes the two RSS feed defects in #269.
#
# Deleting a feed failed with PG::ForeignKeyViolation once it had any seen-item
# rows: `fk_rss_feed_items_feed` came over from the Oracle->Neon sync without
# ON DELETE CASCADE. It is recreated here with the cascade, matching the
# model's `dependent: :delete_all`.
#
# Nothing stopped the same feed (feed_url + channel_id) being registered twice,
# which is how production ended up with the identical Humble Bundle feeds #24
# and #25. Before the unique index can go on, existing duplicates are folded
# into the lowest feed_id: their seen items move over (so the survivor does not
# re-post anything a duplicate already posted) and the extra rows are deleted.
# URLs are stripped first, matching the model's `normalizes :feed_url`.
#
# `down` restores the old constraint and drops the index; the deleted
# duplicates are not restored.
class DedupeAndCascadeRpgClubRssFeeds < ActiveRecord::Migration[8.1]
  FEEDS = :rpg_club_rss_feeds
  ITEMS = :rpg_club_rss_feed_items
  FK_NAME = "fk_rss_feed_items_feed"
  INDEX_NAME = "ux_rpg_club_rss_feeds_channel_url"

  def up
    execute <<~SQL
      UPDATE #{FEEDS}
         SET feed_url = regexp_replace(feed_url, '^\\s+|\\s+$', '', 'g')
       WHERE feed_url ~ '^\\s|\\s$'
    SQL

    execute <<~SQL
      CREATE TEMPORARY TABLE rss_feed_duplicates ON COMMIT DROP AS
      SELECT feed_id, keep_id
        FROM (SELECT feed_id, MIN(feed_id) OVER (PARTITION BY channel_id, feed_url) AS keep_id
                FROM #{FEEDS}) ranked
       WHERE feed_id <> keep_id
    SQL

    execute <<~SQL
      INSERT INTO #{ITEMS} (feed_id, item_id_hash, title, url, published_at, created_at)
      SELECT d.keep_id, i.item_id_hash, i.title, i.url, i.published_at, i.created_at
        FROM #{ITEMS} i
        JOIN rss_feed_duplicates d ON d.feed_id = i.feed_id
      ON CONFLICT (feed_id, item_id_hash) DO NOTHING
    SQL

    execute "DELETE FROM #{ITEMS} WHERE feed_id IN (SELECT feed_id FROM rss_feed_duplicates)"
    execute "DELETE FROM #{FEEDS} WHERE feed_id IN (SELECT feed_id FROM rss_feed_duplicates)"

    remove_foreign_key ITEMS, name: FK_NAME, if_exists: true
    add_foreign_key ITEMS, FEEDS, column: :feed_id, primary_key: :feed_id, name: FK_NAME, on_delete: :cascade

    add_index FEEDS, %i[channel_id feed_url], unique: true, name: INDEX_NAME
  end

  def down
    remove_index FEEDS, name: INDEX_NAME

    remove_foreign_key ITEMS, name: FK_NAME
    add_foreign_key ITEMS, FEEDS, column: :feed_id, primary_key: :feed_id, name: FK_NAME
  end
end
