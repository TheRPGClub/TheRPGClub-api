# frozen_string_literal: true

module Achievements
  module Providers
    # One Achievement Set a member has played, as listed by the Provider.
    # `last_played_at` is the incremental-sync cursor; the counts are the
    # Provider's cheap per-set progress (nil when it has none).
    PlayedSet = ValueObject.define(
      :external_id, :np_service_name, :title, :platform_label, :icon_url,
      :last_played_at, :earned_count, :total_count
    )
  end
end
