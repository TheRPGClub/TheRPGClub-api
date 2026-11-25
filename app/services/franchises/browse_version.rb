# frozen_string_literal: true

module Franchises
  # The version the /franchises tiles are cached under
  # (FranchisesController#browse): one cached number, read on every browse
  # in place of scanning the Franchise tables, and bumped by whatever
  # changes a tile: Gamedb::FranchiseEditor (every edit and undo), IGDB
  # imports (links, parents, release dates, covers), hand edits to a game
  # and its images, and the bot's Franchise upsert.
  #
  #   Franchises::BrowseVersion.current
  #   Franchises::BrowseVersion.bump!   # once the current transaction commits
  #
  # A missing number (a fresh or evicted cache) starts at the current time
  # in milliseconds, so it never lands on a version tiles were cached under
  # before. Club plays aren't covered: they change with every Now Playing
  # entry and Completion, so they age out with the cache instead.
  module BrowseVersion
    KEY = "franchise_browse_version"

    module_function

    def current
      Rails.cache.fetch(KEY) { (Time.current.to_f * 1000).to_i }
    end

    # Bumps after the current transaction commits (at once outside one), so a
    # browse racing the write can't cache what it read before the change
    # under the new version.
    def bump!
      ActiveRecord.after_all_transactions_commit do
        current
        Rails.cache.increment(KEY, 1)
      end
    end
  end
end
