# frozen_string_literal: true

# The test database is loaded from schema.rb, so the seed migration that sets
# every Feature Live never runs there: every Feature reads as Preview until a
# spec sets its Feature Flag.
#
# Request specs start like production after the seed instead, with every
# Feature Live and the seed logged as "system", so endpoints behind the
# feature gate answer as they always have. Tag an example or group
# `feature_flags: :none` to start with no stored state (every Feature
# Preview).
module FeatureFlagHelpers
  def set_feature_flag(key, state, by: FeatureFlag::SYSTEM, reason: nil)
    FeatureFlag.change!(key, state, by: by, reason: reason)
  end

  def set_all_feature_flags(state)
    Features.keys.each { |key| set_feature_flag(key, state) }
  end

  # The seed migration's result in two inserts, cheap enough for every
  # request example.
  def seed_feature_flags_live
    now = Time.current
    FeatureFlag.insert_all!(Features.keys.map { |key| { key: key, state: "live", created_at: now, updated_at: now } })
    FeatureFlagChange.insert_all!(Features.keys.map do |key|
      { feature_key: key, from_state: nil, to_state: "live", changed_by: FeatureFlag::SYSTEM,
        reason: "Feature Flags shipped with every Feature Live", created_at: now }
    end)
    Features.forget_cached_states!
  end
end

RSpec.configure do |config|
  config.include FeatureFlagHelpers

  # A running achievement chain keeps "the Achievement Hub is not Off" for a
  # few seconds; each example starts without it.
  config.before do
    Achievements::ProviderTickJob.forget_hub_state!
    Features.forget_cached_states!
  end

  config.before(:each, type: :request) do |example|
    seed_feature_flags_live unless example.metadata[:feature_flags] == :none
  end
end
