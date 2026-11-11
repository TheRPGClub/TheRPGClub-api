# frozen_string_literal: true

# The News Channel (spec #367, ticket #369): who last changed a News Item's
# News Category through "Change news category" (a Discord user id) and when.
# With picked_category_key (the bot's first pick, never changed) it lets the
# misses be listed to refresh the bot's category rules.
class AddCategoryChangeToNewsItems < ActiveRecord::Migration[8.1]
  def change
    change_table :news_items, bulk: true do |t|
      t.string :category_changed_by, limit: 30
      t.datetime :category_changed_at
    end
  end
end
