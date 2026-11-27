# frozen_string_literal: true

# The Member's Theme (spec api#523, ticket api#524; docs/adr/0017): the key
# of the Theme they chose. NULL follows the club's default Theme, so a later
# change of default reaches everyone who never chose, with no data migration.
class AddThemeToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :theme, :string, limit: 32,
      comment: "The member's Theme key; NULL follows the club's default Theme."
  end
end
