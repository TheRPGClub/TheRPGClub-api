# frozen_string_literal: true

class CreateSocialPlatforms < ActiveRecord::Migration[8.1]
  PRESETS = [
    { label: "PSN",                position: 100 },
    { label: "Xbox Live",          position: 200 },
    { label: "Switch friend code", position: 300 },
    { label: "Steam",              position: 400 },
    { label: "Completionator",     position: 500 },
    { label: "Website",            position: 600 }
  ].freeze

  def up
    unless table_exists?(:social_platforms)
      create_table :social_platforms do |table|
        table.string :label, limit: 80, null: false
        table.integer :position, default: 1000, null: false
        table.string :created_by_user_id, limit: 30
        table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
        table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      end

      add_index :social_platforms, "LOWER(label)", unique: true, name: "index_social_platforms_on_lower_label"
      add_index :social_platforms, :position
    end

    PRESETS.each do |preset|
      execute(<<~SQL)
        INSERT INTO social_platforms (label, position)
        VALUES (#{connection.quote(preset[:label])}, #{preset[:position]})
        ON CONFLICT (LOWER(label)) DO NOTHING;
      SQL
    end
  end

  def down
    drop_table :social_platforms, if_exists: true
  end
end
