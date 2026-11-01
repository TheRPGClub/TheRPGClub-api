# frozen_string_literal: true

module Achievements
  module Providers
    # A full Achievement Set as a Provider defines it, plus one member's
    # Unlocks of it and their playtime. achievements are AchievementDefinitions,
    # unlocks are ProviderUnlocks; playtime_minutes is nil when unknown.
    SetDefinition = Data.define(
      :external_id, :title, :platform_label, :icon_url, :achievements, :unlocks, :playtime_minutes, :np_service_name
    ) do
      def initialize(np_service_name: nil, playtime_minutes: nil, **attributes)
        super
      end
    end
  end
end
