# frozen_string_literal: true

module Achievements
  # The Provider clients and the shared value objects and errors they speak
  # (see providers/). Every client lists a member's played sets with
  # `played_sets(external_id, since:)` and imports one set with
  # `set_with_progress`; PSN's also takes the set's np_service_name.
  module Providers
    CLIENTS = {
      "retroachievements" => -> { Retroachievements::Client.new },
      "steam" => -> { Steam::Client.new },
      "psn" => -> { Psn::Client.new }
    }.freeze

    # A fresh client for a Provider name (a UserLinkedAccount / AchievementSet
    # `provider`). The single place sync and linking get a client from, so
    # specs stub this one method.
    def self.client_for(provider)
      factory = CLIENTS[provider.to_s]
      raise ArgumentError, "unknown Provider #{provider.inspect}" unless factory

      factory.call
    end
  end
end
