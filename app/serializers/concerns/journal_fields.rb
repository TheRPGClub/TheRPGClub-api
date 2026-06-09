# frozen_string_literal: true

# The journal-entry column set, shared by the embedded variants
# (JournalEntryGameResource / JournalEntryUserResource).
#
# Unlike the other resources (#36) there is no prior consumer to audit against
# — these endpoints are new (#39) — so the full meaningful contract is exposed:
# identity (`entry_id`, `user_id`, `gamedb_game_id`), content (`entry_title`,
# `entry_body`) and the `created_at`/`updated_at` timestamps a chronological
# journal needs. Every entry is public, so there is no visibility field.
module JournalFields
  extend ActiveSupport::Concern

  included do
    attributes :entry_id, :user_id, :gamedb_game_id,
               :entry_title, :entry_body,
               :created_at, :updated_at
  end
end
