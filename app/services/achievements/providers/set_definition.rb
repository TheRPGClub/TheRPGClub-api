# frozen_string_literal: true

module Achievements
  module Providers
    # An Achievement Set with its definitions and one member's Unlocks of it.
    SetDefinition = Data.define(
      :external_id, :title, :platform_label, :icon_url, :np_service_name, :achievements, :unlocks, :playtime_minutes
    ) do
      def initialize(external_id:, title:, platform_label: nil, icon_url: nil, np_service_name: nil,
                     achievements: [], unlocks: [], playtime_minutes: nil)
        super
      end
    end
  end
end
