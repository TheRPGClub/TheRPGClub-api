# frozen_string_literal: true

# A Patch as the API serves it (spec api#510, ticket api#511).
#
#   counts      how many changes it lists as New, Improved and Fixed
#               (PatchNotes.counts)
#   posted_at, post_channel_id, post_message_id, edited_since_post
#               its Discord post, null while not posted (ticket api#513)
#
# A single Patch adds `previous_number` and `next_number`, and for writers
# `post_job` (PatchesController).
class PatchResource
  include BaseResource

  attributes :id, :number, :title, :status, :published_at, :rich_body, :body, :cut_body, :counts,
    :posted_at, :post_channel_id, :post_message_id, :edited_since_post, :created_at, :updated_at
end
