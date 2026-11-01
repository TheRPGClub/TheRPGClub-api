# frozen_string_literal: true

module Achievements
  module Providers
    # One Achievement as a Provider defines it. `rarity` / `rarity_hardcore` are
    # the Provider's global percentages (0-100), nil when unknown.
    AchievementDefinition = Data.define(
      :external_id, :name, :description, :icon_url, :icon_locked_url, :hidden, :points, :tier,
      :display_order, :rarity, :rarity_hardcore
    ) do
      def initialize(external_id:, name:, description: nil, icon_url: nil, icon_locked_url: nil, hidden: false,
                     points: nil, tier: nil, display_order: nil, rarity: nil, rarity_hardcore: nil)
        super
      end
    end
  end
end
