# frozen_string_literal: true

# The staff "show Preview features" setting (spec #347, ticket #352), on by
# default. Turned off, an Admin or Superadmin's session shows Features as a
# member would see them. It has no effect for anyone else.
class AddShowPreviewFeaturesToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :show_preview_features, :boolean, default: true, null: false,
      comment: "Staff setting: show Preview Features on the website (on by default)."
  end
end
