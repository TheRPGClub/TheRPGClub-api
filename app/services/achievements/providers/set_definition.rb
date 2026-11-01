# frozen_string_literal: true

module Achievements
  module Providers
    # An Achievement Set's definitions plus one member's Unlocks in it.
    # `version` is the Provider's definitions version (PSN trophySetVersion).
    SetDefinition = ValueObject.define(
      :external_id, :np_service_name, :title, :platform_label, :icon_url, :version,
      :achievements, :unlocks, :playtime_minutes
    )
  end
end
