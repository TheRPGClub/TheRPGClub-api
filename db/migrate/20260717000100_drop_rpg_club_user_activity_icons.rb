# frozen_string_literal: true

# The activity icons API was removed (#89) -- it was dead code, never called
# by the Discord bot. This drops the now-unused rpg_club_user_activity_icons
# table. The original create migration is kept for history per the issue's
# acceptance criteria.
class DropRpgClubUserActivityIcons < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:rpg_club_user_activity_icons)

    drop_table :rpg_club_user_activity_icons
  end

  def down
    create_table :rpg_club_user_activity_icons do |table|
      table.string :user_id, limit: 128, null: false
      table.string :username, limit: 256
      table.string :activity_name, limit: 256, null: false
      table.string :activity_name_norm, limit: 256, null: false
      table.string :icon_type, limit: 16, null: false
      table.string :source_ref, limit: 1024, null: false
      table.string :icon_url, limit: 2048, null: false
      table.datetime :first_seen_at, precision: 6, default: -> { "statement_timestamp()" }, null: false
      table.datetime :last_seen_at, precision: 6, default: -> { "statement_timestamp()" }, null: false
      table.bigint :seen_count, default: 1, null: false

      table.check_constraint "seen_count >= 1", name: "chk_rpg_club_user_activity_icon_count"
      table.check_constraint "icon_type::text = ANY (ARRAY['large'::character varying, 'small'::character varying]::text[])",
        name: "chk_rpg_club_user_activity_icon_type"
    end

    add_index :rpg_club_user_activity_icons, %i[user_id activity_name_norm icon_type source_ref],
      unique: true, name: "rpg_club_user_activity_icons_user_id_activity_name_norm_ico_key"
    add_index :rpg_club_user_activity_icons, %i[user_id last_seen_at activity_name_norm icon_type],
      name: "idx_rpg_club_user_activity_icons_lookup"
  end
end
