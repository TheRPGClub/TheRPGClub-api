# frozen_string_literal: true

module Achievements
  module Providers
    # A member's Unlock of one Achievement, keyed by the Achievement's
    # external_id. `hardcore_unlocked_at` is RetroAchievements-only.
    ProviderUnlock = Data.define(:achievement_external_id, :unlocked_at, :hardcore_unlocked_at) do
      def initialize(achievement_external_id:, unlocked_at:, hardcore_unlocked_at: nil)
        super
      end
    end
  end
end
