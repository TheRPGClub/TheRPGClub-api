# frozen_string_literal: true

# Serializes an NrGotmEntry, matching the legacy `NrGotmEntry#as_json`: all
# entry columns plus an optional embedded `game`. See GotmEntryResource for the
# full rationale — the embed is gated on the controller-supplied
# `include_game` Alba param and uses GameWithPlatformsResource (not
# GameResource, which would raise on the `gotm_won`/`nr_gotm_won` aliases that
# the plain-loaded GOTM game never carries).
class NrGotmEntryResource
  include BaseResource

  columns_of NrGotmEntry
  one :game, resource: GameWithPlatformsResource, if: proc { params[:include_game] }
end
