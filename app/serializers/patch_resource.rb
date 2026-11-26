# frozen_string_literal: true

# A Patch as the API serves it (spec api#510, ticket api#511).
#
#   counts      how many changes it lists as New, Improved and Fixed
#               (PatchNotes.counts)
#
# A single Patch adds `previous_number` and `next_number` (PatchesController).
class PatchResource
  include BaseResource

  attributes :id, :number, :title, :status, :published_at, :rich_body, :body, :cut_body, :counts,
    :created_at, :updated_at
end
