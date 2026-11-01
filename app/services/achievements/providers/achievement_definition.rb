# frozen_string_literal: true

module Achievements
  module Providers
    # One Achievement as the Provider defines it. `rarity` is the Provider's
    # global percentage; `tier` is PSN only; `points`/`rarity_hardcore` RA only.
    AchievementDefinition = ValueObject.define(
      :external_id, :name, :description, :icon_url, :icon_locked_url, :hidden,
      :points, :tier, :display_order, :rarity, :rarity_hardcore
    )
  end
end
