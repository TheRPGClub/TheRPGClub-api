# frozen_string_literal: true

module Challenges
  # The years a game fits as a Slots slot (GLOSSARY.md, "Slots"): its first
  # release year, and the year of any of its regional or platform releases in
  # the GameDB, so a game released in Japan in 1995 and in the West in 1999
  # fits both. A game's first release date is stored at midnight UTC, so its
  # year is its UTC year; a Release's date is a plain date (a vague one is the
  # start of its period, and a TBA Release has none).
  #
  #   Challenges::ReleaseYears.of([ 12, 34 ]) # => { 12 => [ 1995, 1999 ], 34 => [] }
  module ReleaseYears
    def self.of(game_ids)
      years = game_ids.to_h { |id| [ id, [] ] }
      return years if game_ids.empty?

      firsts = GamedbGame.where(game_id: game_ids).where.not(initial_release_date: nil)
        .pluck(:game_id, :initial_release_date)
      firsts.each { |id, at| years[id] |= [ at.utc.year ] }
      GamedbRelease.where(game_id: game_ids).where.not(release_date: nil).pluck(:game_id, :release_date)
        .each { |id, date| years[id] |= [ date.year ] }
      years.transform_values(&:sort)
    end

    # The same years for one game whose `releases` are loaded (no query when
    # they are preloaded, as ChallengeRunResource does for its entries).
    def self.of_game(game)
      first = game.initial_release_date&.utc&.year
      ([ first ] + game.releases.map { |release| release.release_date&.year }).compact.uniq.sort
    end
  end
end
