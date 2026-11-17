# frozen_string_literal: true

# An Upcoming Release on the Release Calendar (Gamedb::UpcomingReleases::Entry):
# the game, the shared date and Date Precision, the `section` a client renders
# it under, its Releases, and when the game first released if that was
# earlier.
class UpcomingReleaseResource
  include BaseResource

  attribute(:game) do |entry|
    { game_id: entry.game.game_id, title: entry.game.title, cover_url: entry.game.cover_url }
  end
  attribute(:date) { |entry| entry.date&.iso8601 }
  attributes :date_precision, :section
  attribute(:first_released_on) { |entry| entry.first_released_before&.date&.iso8601 }
  attribute(:first_released_precision) { |entry| entry.first_released_before&.date_precision }
  attribute(:releases) do |entry|
    entry.releases.map do |release|
      {
        release_id: release.release_id,
        platform_id: release.platform_id,
        platform_name: release.platform.platform_name,
        platform_abbreviation: release.platform.platform_abbreviation,
        region_id: release.region_id,
        region_code: release.region.region_code,
        region_name: release.region.region_name,
        format: release.format,
        source: release.source
      }
    end
  end
end
