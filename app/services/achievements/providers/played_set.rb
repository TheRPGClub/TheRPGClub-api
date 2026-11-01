# frozen_string_literal: true

module Achievements
  module Providers
    # One Achievement Set a member has played, as listed by a Provider.
    # external_id is the RA game id, Steam appid or PSN npCommunicationId;
    # np_service_name is PSN only. activity_at is the Provider's latest
    # activity signal for the member (last played, or last Unlock).
    PlayedSet = Data.define(
      :external_id, :title, :platform_label, :icon_url, :achievements_count, :activity_at, :np_service_name
    ) do
      def initialize(np_service_name: nil, **attributes)
        super
      end
    end
  end
end
