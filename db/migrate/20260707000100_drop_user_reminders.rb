# frozen_string_literal: true

# The personal (DM) reminders API was removed (#87) -- it was dead code, never
# called by the Discord bot. This drops the now-unused user_reminders table.
# The original create migration (20260507000300) is kept for history per the
# issue's acceptance criteria.
class DropUserReminders < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:user_reminders)

    drop_table :user_reminders
  end

  def down
    create_table :user_reminders, primary_key: :reminder_id do |table|
      table.string :user_id, limit: 32, null: false
      table.column :remind_at, "timestamp(6) with time zone", null: false
      table.string :content, limit: 400, null: false
      table.column :sent_at, "timestamp(6) with time zone"
      table.boolean :is_noisy, default: false, null: false
      table.bigint :failure_count, default: 0, null: false
      table.column :failed_at, "timestamp(6) with time zone"
      table.column :created_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
      table.column :updated_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
    end

    add_index :user_reminders, %i[user_id remind_at], name: "ux_user_reminders_user"
    add_index :user_reminders, %i[sent_at remind_at], name: "ux_user_reminders_due"
  end
end
