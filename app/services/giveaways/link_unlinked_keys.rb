# frozen_string_literal: true

module Giveaways
  # Backfill for the `giveaways:link_keys` rake task: links every giveaway key
  # without a `gamedb_game_id` to the GameDB game its `game_title` matches,
  # with the same unique exact match new donations use
  # (Imports::UniqueTitleMatch). Ambiguous and unmatched keys stay unlinked.
  #
  # Each distinct title is matched once. With `dry_run: true` nothing is
  # written; the report is the same, so it shows what a real run would link.
  class LinkUnlinkedKeys
    # linked: key count; ambiguous / unmatched: the titles left unlinked,
    # each with its key count.
    Report = Data.define(:linked, :ambiguous, :unmatched)

    def self.call(dry_run: false)
      new(dry_run:).call
    end

    def initialize(dry_run:)
      @dry_run = dry_run
      @matcher = Imports::UniqueTitleMatch.new
    end

    def call
      linked = 0
      ambiguous = Hash.new(0)
      unmatched = Hash.new(0)

      RpgClubGameKey.where(gamedb_game_id: nil).find_each do |key|
        result = match(key.game_title)
        if result.matched?
          link(key, result.game_id)
          linked += 1
        elsif result.ambiguous?
          ambiguous[key.game_title] += 1
        else
          unmatched[key.game_title] += 1
        end
      end

      Report.new(linked:, ambiguous: ambiguous.sort.to_h, unmatched: unmatched.sort.to_h)
    end

    private

    def match(title)
      @matches ||= {}
      @matches[title.to_s.strip] ||= @matcher.call(title)
    end

    # update_columns: legacy bot rows are linked as they are, without
    # re-running validations they were never checked against.
    def link(key, game_id)
      key.update_columns(gamedb_game_id: game_id, updated_at: Time.current) unless @dry_run
    end
  end
end
