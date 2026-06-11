# frozen_string_literal: true

class CreateJournalMessageContexts < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:journal_message_contexts)

    create_table :journal_message_contexts, primary_key: %i[channel_id message_id] do |table|
      table.string :channel_id,    limit: 30, null: false
      table.string :message_id,    limit: 30, null: false
      table.bigint :created_at_ms,            null: false
      table.string :owner_user_id, limit: 30, null: false
      table.bigint :game_id,                  null: false
    end
  end

  def down
    drop_table :journal_message_contexts, if_exists: true
  end
end
