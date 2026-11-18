# frozen_string_literal: true

namespace :gamedb do
  desc "Refresh upcoming, vague and missing Releases from IGDB now (Gamedb::ReleaseRefreshJob, the weekly run). " \
       "Run once right after the Release Calendar migrations; safe to run again."
  task refresh_releases: :environment do
    game_ids = Gamedb::ReleaseRefreshJob.perform_now
    puts "Refreshed the Releases of #{game_ids.size} game(s); any that failed are logged."
  end
end
