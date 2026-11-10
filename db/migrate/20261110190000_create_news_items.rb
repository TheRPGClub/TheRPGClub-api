# frozen_string_literal: true

# News Items (GLOSSARY.md, "News Hub"; spec #355, ticket #356): one row per
# Discord message a member posted in a News Category's thread (or, for the
# News Import, in the Game News Archive) that carries a link, an image, or
# both. Keyed on the Discord message id, so every write from the bot is
# idempotent. The author need not have a member record, so `author_id` has
# no foreign key and `author_name` keeps the name they had when recorded.
#
# `category_key` is a NewsCategory key; it may be empty only for an imported
# News Item staff have not sorted yet. `images` holds the message's image
# attachments in order, each `{ "url", "expires_at" }`: Discord's address
# and when it expires. `link_*` is the message's first link and the preview
# Discord generated for it. Nothing is copied into club storage.
class CreateNewsItems < ActiveRecord::Migration[8.1]
  def change
    create_table :news_items do |t|
      t.string :message_id, limit: 30, null: false
      t.string :channel_id, limit: 30, null: false
      t.string :author_id, limit: 30, null: false
      t.string :author_name, limit: 100, null: false
      t.string :category_key, limit: 64
      t.string :origin, limit: 16, null: false, default: "live"
      t.text :comment
      t.text :link_url
      t.text :link_title
      t.text :link_site_name
      t.text :link_description
      t.text :link_image_url
      t.jsonb :images, null: false, default: []
      t.datetime :posted_at, null: false
      t.datetime :edited_at
      t.timestamps

      t.check_constraint "origin IN ('live', 'import')", name: "ck_news_items_origin"
      t.check_constraint "category_key IS NOT NULL OR origin = 'import'", name: "ck_news_items_category"
    end

    add_index :news_items, :message_id, unique: true
    add_index :news_items, %i[posted_at id], order: { posted_at: :desc, id: :desc },
      where: "category_key IS NOT NULL", name: "ix_news_items_feed"
    add_index :news_items, %i[category_key posted_at], order: { posted_at: :desc },
      where: "category_key IS NOT NULL", name: "ix_news_items_category_feed"
  end
end
