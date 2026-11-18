# frozen_string_literal: true

# An image in a Club Codex entry's gallery (spec #397, ticket #410): up to
# MAX_PER_ENTRY on a History Event or Lore Entry, never on a Fun Fact. The
# file lives in the Backblaze bucket the GameDB game images use, under
# `object_key`; ClubCodex::Images stores and removes it.
#
# `position` is 1..n in upload order; there's no reordering.
class CodexEntryImage < ApplicationRecord
  MAX_PER_ENTRY = 4

  belongs_to :entry, class_name: "CodexEntry", inverse_of: :images

  # Where the file is served from; nil while BACKBLAZE_PUBLIC_BASE_URL is unset.
  def url = Backblaze::Client.public_url_for(object_key)

  # The shape every entry payload's `images` carries, and the upload returns.
  def payload = { id: id, url: url, position: position }
end
