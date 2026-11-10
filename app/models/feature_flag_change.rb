# frozen_string_literal: true

# The append-only log of Feature Flag changes (spec #347): which Feature, from
# and to which state, who changed it ("system" or a Discord user id), the
# optional reason, and when. `from_state` is null when the Feature had no
# stored state, which reads as Preview. Rows are never updated or deleted.
class FeatureFlagChange < ApplicationRecord
  validates :feature_key, :changed_by, presence: true
  validates :to_state, inclusion: { in: Features::STATES }
  validates :from_state, inclusion: { in: Features::STATES }, allow_nil: true

  def readonly?
    persisted? || super
  end
end
