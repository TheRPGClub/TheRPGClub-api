# frozen_string_literal: true

# The News Channel (spec #367, ticket #368): where a News Item's News Copy
# lives (the bot's copy in its News Category's thread: the copy's message id
# and the thread it is in, both set or both empty) and the News Category the
# bot first picked for it. The partial index serves the listing of News
# Items with a News Category but no News Copy, oldest first.
class AddNewsCopyToNewsItems < ActiveRecord::Migration[8.1]
  def change
    change_table :news_items, bulk: true do |t|
      t.string :news_copy_message_id, limit: 30
      t.string :news_copy_thread_id, limit: 30
      t.string :picked_category_key, limit: 64
      t.check_constraint "(news_copy_message_id IS NULL) = (news_copy_thread_id IS NULL)",
        name: "ck_news_items_news_copy"
    end

    add_index :news_items, %i[posted_at id],
      where: "category_key IS NOT NULL AND news_copy_message_id IS NULL", name: "ix_news_items_uncopied"
  end
end
