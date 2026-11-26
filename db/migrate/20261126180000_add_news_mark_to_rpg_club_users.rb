# frozen_string_literal: true

# The News Mark (spec api#494, ticket api#495): the moment up to which a
# member has seen the News Hub's News Items. NULL until the website first sets
# it, which the News page shows as a first visit.
class AddNewsMarkToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :news_mark_at, :timestamptz,
      comment: "The member's News Mark: the moment up to which they have seen the News Hub; NULL until first set."
  end
end
