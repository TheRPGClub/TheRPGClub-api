# frozen_string_literal: true

# The embedded game shape plus its platforms, for the two consumers that render
# platform pills: the voting / nominations board (NominationResource) and the
# dashboard's GOTM / NR-GOTM cards (GotmEntryResource, NrGotmEntryResource).
# Everything else keeps the platform-free GameSummaryResource.
#
# This is a separate resource rather than `many :platforms` on GameFields
# because that concern is the consumer-audited allowlist (#36) shared by
# GameResource and GameSummaryResource, and fifteen resources embed the latter
# — every one of their controllers would need a new preload or take an N+1.
# Widening the allowlist is a decision to make on its own, not a side effect of
# adding pills to two screens.
#
# The only other source for this data is games#relations, which serves one game
# per request and so cannot answer for a board of 10–20 nominations.
#
# Controllers embedding this must preload `game: :platforms`; the association
# carries its own `order(:platform_name)` so the pills do not reshuffle between
# renders.
class GameWithPlatformsResource
  include BaseResource
  include GameFields

  many :platforms, resource: PlatformResource
end
