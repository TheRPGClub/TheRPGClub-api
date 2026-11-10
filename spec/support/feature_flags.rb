# frozen_string_literal: true

# The test database is loaded from schema.rb, so the seed migration that sets
# every Feature Live never runs there: every Feature reads as Preview until a
# spec sets its Feature Flag.
module FeatureFlagHelpers
  def set_feature_flag(key, state, by: FeatureFlag::SYSTEM, reason: nil)
    FeatureFlag.change!(key, state, by: by, reason: reason)
  end

  def set_all_feature_flags(state)
    Features.keys.each { |key| set_feature_flag(key, state) }
  end
end

RSpec.configure do |config|
  config.include FeatureFlagHelpers
end
