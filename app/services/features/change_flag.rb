# frozen_string_literal: true

module Features
  # A staff member sets a Feature Flag (spec #347). In one transaction it sets
  # the state, writes the change log and enqueues the `feature_flag_changed`
  # bot job the bot posts in the admin channel. Setting the state a Feature
  # already reads as (a Feature with no stored state reads as Preview) changes,
  # logs and announces nothing.
  #
  # After an Achievement Hub change away from Off, the achievement sync chains
  # start at once instead of waiting for the next Sync Window; after a Voting &
  # GOTM change, the round sweep looks again on the next minute.
  #
  #   Features::ChangeFlag.call("journals", "off", by: "123", reason: "Journal sync broken")
  #   # => the FeatureFlagChange, or nil when nothing changed
  class ChangeFlag
    REASON_MAX = 500

    class Invalid < StandardError; end

    def self.call(...) = new(...).call

    # `by` is the acting member's Discord user id.
    def initialize(key, state, by:, reason: nil)
      @feature = Features.find(key) or raise KeyError, "unknown Feature: #{key}"
      @state = state.to_s
      @by = by.to_s
      @reason = reason.to_s.strip.presence
      raise Invalid, "state must be one of #{STATES.join(', ')}" unless STATES.include?(@state)
      raise Invalid, "reason is longer than #{REASON_MAX} characters" if @reason && @reason.length > REASON_MAX
    end

    def call
      change = FeatureFlag.transaction do
        FeatureFlag.change!(@feature.key, @state, by: @by, reason: @reason)&.tap { |logged| announce!(logged) }
      end
      after_change(change) if change
      change
    end

    private

    # Payload (kind feature_flag_changed): { key, name, from_state, to_state,
    # changed_by, changed_by_name, reason }. No `feature_key`: it goes to the
    # admin channel whatever the Feature's state, not where the Feature posts.
    def announce!(change)
      from = change.from_state || DEFAULT_STATE
      BotJob.enqueue!(
        kind: "feature_flag_changed",
        summary: "Feature Flag #{@feature.name}: #{from} to #{@state}",
        payload: {
          key: @feature.key, name: @feature.name, from_state: from, to_state: @state,
          changed_by: @by, changed_by_name: display_name, reason: @reason
        },
        requested_by: @by
      )
    end

    def display_name
      StaffList.display_names([ @by ]).fetch(@by, @by)
    end

    # Automated activity that waits while its Feature is Off picks up at once
    # instead of at its next scheduled look.
    def after_change(change)
      case @feature.key
      when "achievement_hub"
        Achievements::ProviderTickJob.enqueue_all if change.from_state == "off"
      when "voting_gotm"
        Voting::SweepSchedule.clear
      end
    end
  end
end
