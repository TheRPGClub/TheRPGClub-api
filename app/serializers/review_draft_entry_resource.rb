# frozen_string_literal: true

# A Draft in the author's drafts listing (reviews#drafts): a Draft Review or
# a Draft Revision (`kind`), a row of `UserGameReview.takes(:drafts)`, with
# `updated_at` (when the author last touched it) and the game with its
# GOTM / NR-GOTM track flags and the months they were won. A Draft Revision's `previous_rating` is the
# Review's current score ("Revisiting · was 72").
class ReviewDraftEntryResource
  include BaseResource
  include ReviewTakeFields

  attributes :updated_at

  one :game, resource: TrackedGameResource, source: proc { tracked_game }
end
