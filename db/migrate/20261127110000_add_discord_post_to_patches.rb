# frozen_string_literal: true

# A Patch's Discord post (spec api#510, ticket api#513): the message the bot
# posted to #patch-notes (or the staff test channel in Preview), when, and
# whether the Patch changed since, so staff know to update it.
class AddDiscordPostToPatches < ActiveRecord::Migration[8.1]
  def change
    change_table :patches, bulk: true do |t|
      t.string :post_channel_id, comment: "The channel the bot posted it in; NULL while not posted."
      t.string :post_message_id, comment: "The Discord message the bot posted; NULL while not posted."
      t.timestamptz :posted_at, comment: "When the bot first posted it; NULL while not posted."
      t.boolean :edited_since_post, null: false, default: false,
        comment: "Its text changed after the post; cleared when the bot records the edited post."
      t.check_constraint "(post_message_id IS NULL) = (posted_at IS NULL) AND " \
                         "(post_message_id IS NULL) = (post_channel_id IS NULL)",
        name: "ck_patches_post"
    end
  end
end
