# frozen_string_literal: true

# The Patch Mark (spec api#510, ticket api#512): the number of the newest
# Patch a member has seen. NULL until the website first sets it, so every
# published Patch reads as unseen on a member's first visit.
class AddPatchMarkToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :patch_mark, :integer,
      comment: "The member's Patch Mark: the number of the newest Patch they have seen; NULL until first set."
  end
end
