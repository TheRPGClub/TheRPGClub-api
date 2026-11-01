# frozen_string_literal: true

module Achievements
  module Providers
    # A member's Unlock of one Achievement, keyed by the Achievement's
    # external_id. `hardcore` is RA only.
    ProviderUnlock = ValueObject.define(:achievement_external_id, :unlocked_at, :hardcore)
  end
end
