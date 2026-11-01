# frozen_string_literal: true

module Achievements
  module Providers
    # One Achievement Set a member has played, as listed by a Provider.
    PlayedSet = Data.define(
      :external_id, :title, :platform_label, :icon_url, :np_service_name, :last_played_at, :playtime_minutes
    ) do
      def initialize(external_id:, title:, platform_label: nil, icon_url: nil, np_service_name: nil,
                     last_played_at: nil, playtime_minutes: nil)
        super
      end
    end
  end
end
