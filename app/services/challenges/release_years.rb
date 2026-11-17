# frozen_string_literal: true

module Challenges
  # The years a game fits as a Slots slot (GLOSSARY.md, "Slots"): its first
  # release year, and the year of any of its regional or platform releases in
  # the GameDB, so a game released in Japan in 1995 and in the West in 1999
  # fits both. GameDB dates are stored at midnight UTC, so a date's year is
  # its UTC year.
  #
  #   Challenges::ReleaseYears.of([ 12, 34 ]) # => { 12 => [ 1995, 1999 ], 34 => [] }
  module ReleaseYears
    def self.of(game_ids)
      years = game_ids.to_h { |id| [ id, [] ] }
      return years if game_ids.empty?

      dates = GamedbGame.where(game_id: game_ids).where.not(initial_release_date: nil)
        .pluck(:game_id, :initial_release_date)
      dates += GamedbRelease.where(game_id: game_ids).where.not(release_date: nil).pluck(:game_id, :release_date)
      dates.each { |id, at| years[id] |= [ at.utc.year ] }
      years.transform_values(&:sort)
    end
  end
end
