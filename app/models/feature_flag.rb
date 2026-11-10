# frozen_string_literal: true

# A Feature Flag's stored state (spec #347): one row per Feature key, always
# Off, Preview or Live. Read states through Features.states / Features.state,
# which treat a registered key with no row as Preview, and change them only
# with FeatureFlag.change!, which also writes the change log.
class FeatureFlag < ApplicationRecord
  # Who `changed_by` names when no member made the change, e.g. the seed.
  SYSTEM = "system"

  # Sets Feature `key` to `state` and logs the change: `by` is "system" or the
  # acting member's Discord user id, `reason` is optional. Returns the logged
  # FeatureFlagChange, or nil when the Feature already reads as `state` (a
  # Feature with no stored state reads as Preview), which changes and logs
  # nothing. Raises KeyError for an unknown key, Features::InvalidState for a
  # state other than Off, Preview or Live (rows are written only here, never
  # through validations).
  #
  # Safe when two staff members set the same Feature at once: the row is
  # locked while it changes, and a Feature's first row is inserted with ON
  # CONFLICT DO NOTHING, so the slower writer waits and then changes the row
  # the faster one stored.
  #
  # This process's Features.cached_states is forgotten, so its next request
  # reads the new state.
  def self.change!(key, state, by:, reason: nil)
    key = Features.fetch(key).key
    state = Features.check_state!(state)

    transaction do
      from = lock.where(key: key).pick(:state)
      if from.nil?
        next if state == Features::DEFAULT_STATE
        next log_change(key, nil, state, by, reason) if insert_first(key, state)

        from = lock.where(key: key).pick(:state)
      end
      next if from == state

      where(key: key).update_all(state: state, updated_at: Time.current)
      log_change(key, from, state, by, reason)
    end.tap { Features.forget_cached_states! }
  end

  # Inserts a Feature's first stored state; false when another writer stored
  # it first.
  def self.insert_first(key, state)
    now = Time.current
    insert_all([ { key: key, state: state, created_at: now, updated_at: now } ], unique_by: :key, returning: [ :key ]).any?
  end
  private_class_method :insert_first

  def self.log_change(key, from, to, by, reason)
    FeatureFlagChange.create!(feature_key: key, from_state: from, to_state: to, changed_by: by.to_s, reason: reason.presence)
  end
  private_class_method :log_change
end
