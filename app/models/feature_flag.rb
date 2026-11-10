# frozen_string_literal: true

# A Feature Flag's stored state (spec #347): one row per Feature key, always
# Off, Preview or Live. Read states through Features.states / Features.state,
# which treat a registered key with no row as Preview, and change them only
# with FeatureFlag.change!, which also writes the change log.
class FeatureFlag < ApplicationRecord
  # Who `changed_by` names when no member made the change, e.g. the seed.
  SYSTEM = "system"

  validates :key, presence: true, uniqueness: true
  validates :state, inclusion: { in: Features::STATES }
  validate :key_is_registered

  # Sets Feature `key` to `state` and logs the change: `by` is "system" or the
  # acting member's Discord user id, `reason` is optional. Setting the state a
  # Feature already has changes and logs nothing. Returns the FeatureFlag.
  def self.change!(key, state, by:, reason: nil)
    Features.fetch(key)
    transaction do
      flag = lock.find_or_initialize_by(key: key.to_s)
      from = flag.new_record? ? nil : flag.state
      next flag if from == state.to_s

      flag.update!(state: state.to_s)
      FeatureFlagChange.create!(feature_key: flag.key, from_state: from, to_state: flag.state,
        changed_by: by.to_s, reason: reason.presence)
      flag
    end
  end

  private

  def key_is_registered
    errors.add(:key, "is not a registered Feature") unless Features.known?(key)
  end
end
