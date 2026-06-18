# frozen_string_literal: true

# The consumer-audited completion allowlist (#36), shared by the game-embedded
# (CompletionEntryResource) and user-embedded (CompletionUserEntryResource)
# variants of the same entry.
#
# The entry PK (`completion_id`), `user_id`, `gamedb_game_id`, `platform_id`,
# `note` and the completion data (`completion_type`, `completed_at`,
# `final_playtime_hrs`) are read, plus `created_at` — the row's insert time, the
# only timestamp the table records (no `updated_at`). `created_at` is exposed for
# the bot's CSV export (`getAllCompletions`), which falls back to it when an
# entry has no `completed_at` (#102).
module CompletionFields
  extend ActiveSupport::Concern

  included do
    attributes :completion_id, :user_id, :gamedb_game_id, :platform_id, :note,
               :completion_type, :completed_at, :final_playtime_hrs, :created_at
  end
end
