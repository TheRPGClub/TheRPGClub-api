# frozen_string_literal: true

# A Draft in the author's drafts listing (reviews#drafts): the ReviewFields
# columns, `updated_at` (when the author last touched it), its `kind` and the
# game with its GOTM / NR-GOTM track flags. `kind` is always "review" for now;
# Draft Revisions join the listing as "revision" (spec api#430).
class ReviewDraftEntryResource
  include BaseResource
  include ReviewFields

  attributes :updated_at
  attribute(:kind) { |_review| "review" }

  one :game, resource: GameResource, source: proc { tracked_game }
end
