# frozen_string_literal: true

# The todos API was removed (#88) -- it was dead code, never called by the
# Discord bot. This drops the now-unused rpg_club_todos table. The original
# create migration (20260505002600) is kept for history per the issue's
# acceptance criteria.
class DropRpgClubTodos < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:rpg_club_todos)

    drop_table :rpg_club_todos
  end

  def down
    create_table :rpg_club_todos, primary_key: :todo_id do |table|
      table.string :title, null: false
      table.text :details
      table.string :created_by, limit: 50
      table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :completed_at, precision: 6
      table.string :completed_by, limit: 50
      table.boolean :is_completed, default: false, null: false
      table.string :category, limit: 100
      table.string :todo_category, limit: 100
      table.string :todo_size, limit: 50
    end

    add_index :rpg_club_todos, :is_completed
  end
end
