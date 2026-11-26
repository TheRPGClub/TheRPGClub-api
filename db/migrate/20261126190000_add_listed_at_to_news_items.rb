# frozen_string_literal: true

# `listed_at` (spec api#494, code-review fix pass): the moment a News Item
# first had a News Category, so members could see it. The News Mark counts
# News Items listed after it as new, so one the bot records late still shows
# as new. Existing News Items take their creation time, or their posting time
# where that is later: all of them were listed before the News Mark shipped,
# so none counts as new for a mark set after launch.
class AddListedAtToNewsItems < ActiveRecord::Migration[8.1]
  def up
    add_column :news_items, :listed_at, :datetime,
      comment: "When the News Item first had a News Category (members could first see it); NULL while unsorted."
    execute <<~SQL.squish
      UPDATE news_items SET listed_at = GREATEST(created_at, posted_at) WHERE category_key IS NOT NULL
    SQL
    add_check_constraint :news_items, "category_key IS NULL OR listed_at IS NOT NULL", name: "ck_news_items_listed_at"
    add_index :news_items, :listed_at, name: "ix_news_items_listed", where: "category_key IS NOT NULL"
  end

  def down
    remove_index :news_items, name: "ix_news_items_listed"
    remove_check_constraint :news_items, name: "ck_news_items_listed_at"
    remove_column :news_items, :listed_at
  end
end
