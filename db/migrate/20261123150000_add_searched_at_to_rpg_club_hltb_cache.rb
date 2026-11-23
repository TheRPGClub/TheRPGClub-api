# frozen_string_literal: true

# When HowLongToBeat was last searched for the game, kept apart from
# scraped_at: a hand-entered row gets scraped_at by default without any
# search, and a forced re-search with no match leaves the saved times (and
# scraped_at) alone but still counts. A forced re-search is allowed once this
# is 30 days old (spec api#437). Existing rows came from a scrape, so they
# start at their scraped_at.
class AddSearchedAtToRpgClubHltbCache < ActiveRecord::Migration[8.1]
  def up
    add_column :rpg_club_hltb_cache, :searched_at, :datetime
    execute "UPDATE rpg_club_hltb_cache SET searched_at = scraped_at"
  end

  def down
    remove_column :rpg_club_hltb_cache, :searched_at
  end
end
