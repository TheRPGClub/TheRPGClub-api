# frozen_string_literal: true

# An Upcoming Release on the Release Calendar (Gamedb::UpcomingReleases::UpcomingRelease):
# the game, the shared date and Date Precision, the `section` a client renders
# it under, its Releases, and when the game first came out if that was
# before this one.
class UpcomingReleaseResource
  include BaseResource

  attribute(:game) do |upcoming|
    { game_id: upcoming.game.game_id, title: upcoming.game.title, cover_url: upcoming.game.cover_url }
  end
  attribute(:date) { |upcoming| upcoming.date&.iso8601 }
  attributes :date_precision, :section
  attribute(:first_released_on) { |upcoming| upcoming.first_released&.date&.iso8601 }
  attribute(:first_released_precision) { |upcoming| upcoming.first_released&.date_precision }
  attribute(:releases) do |upcoming|
    upcoming.releases.map do |release|
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
