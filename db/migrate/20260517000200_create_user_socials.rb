# frozen_string_literal: true

class CreateUserSocials < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:user_socials)

    create_table :user_socials do |table|
      table.string :user_id, limit: 30, null: false
      table.bigint :platform_id, null: false
      table.string :display_text, limit: 80, null: false
      table.string :url, limit: 512
      table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    end

    add_index :user_socials, :user_id
    add_index :user_socials, :platform_id
    add_index :user_socials, %i[user_id platform_id display_text], unique: true,
                                                                   name: "index_user_socials_on_user_platform_display_text"
  end

  def down
    drop_table :user_socials, if_exists: true
  end
end
