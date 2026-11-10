# frozen_string_literal: true

module Features
  # What staff see of every Feature on the flag desk and in `/flag list`
  # (spec #347): its Feature Flag state, Core/hideable, what it covers, and
  # the last change (from and to state, who, when, why).
  #
  # A Feature with no stored state reads as Preview and has no last change. A
  # change log row's missing `from_state` (the Feature had no stored state)
  # is shown as Preview, the state it read as.
  class StaffList
    # Display names (global name, else username, else the id) for the
    # members among `ids`, keyed by Discord user id. "system" and departed
    # members have none.
    def self.display_names(ids)
      RpgClubUser.where(user_id: ids.uniq - [ FeatureFlag::SYSTEM ])
        .pluck(:user_id, :global_name, :username)
        .to_h { |user_id, global_name, username| [ user_id, global_name.presence || username.presence || user_id ] }
    end

    def initialize(states: Features.states)
      @states = states
    end

    # Every Feature in registry order.
    def entries
      changes = last_changes(Features.keys)
      names = names_for(changes.values.map(&:changed_by))
      Features.all.map { |feature| entry(feature, changes[feature.key], names) }
    end

    # One Feature's entry.
    def entry_for(key)
      feature = Features.fetch(key)
      change = last_changes([ feature.key ])[feature.key]
      entry(feature, change, names_for([ change&.changed_by ].compact))
    end

    private

    def entry(feature, change, names)
      {
        key: feature.key,
        name: feature.name,
        state: @states.fetch(feature.key),
        core: feature.core?,
        hideable: feature.hideable?,
        coverage: feature.coverage,
        last_change: change && {
          from_state: change.from_state || DEFAULT_STATE,
          to_state: change.to_state,
          changed_by: change.changed_by,
          changed_by_name: names[change.changed_by],
          reason: change.reason,
          changed_at: change.created_at
        }
      }
    end

    def last_changes(keys)
      FeatureFlagChange.where(feature_key: keys)
        .select("DISTINCT ON (feature_key) *")
        .order(:feature_key, created_at: :desc, id: :desc)
        .index_by(&:feature_key)
    end

    def names_for(ids) = self.class.display_names(ids)
  end
end
