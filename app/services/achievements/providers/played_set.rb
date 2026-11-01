# frozen_string_literal: true

module Achievements
  module Providers
    # One Achievement Set a member has played, as listed by a Provider.
    # external_id is the RA game id, Steam appid or PSN npCommunicationId;
    # np_service_name is PSN only. activity_at is the Provider's latest
    # activity signal for the member (RA MostRecentAwardedDate/LastPlayed,
    # Steam rtime_last_played, PSN lastUpdatedDateTime).
    PlayedSet = Data.define(
      :external_id, :title, :platform_label, :icon_url, :np_service_name, :activity_at, :playtime_minutes,
      :achievements_count
    ) do
      def initialize(external_id:, title:, platform_label: nil, icon_url: nil, np_service_name: nil,
                     activity_at: nil, playtime_minutes: nil, achievements_count: nil)
        super
      end
    end
  end
end
