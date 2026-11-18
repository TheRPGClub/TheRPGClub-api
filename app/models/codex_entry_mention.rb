# frozen_string_literal: true

# A member a Club Codex entry mentions (spec #397): one of the `<@discord_id>`
# tokens in its `body` that names a known member. Kept by
# ClubCodex::Mentions on every save of the entry; goes with the entry.
class CodexEntryMention < ApplicationRecord
  self.primary_key = %i[entry_id user_id]

  belongs_to :entry, class_name: "CodexEntry", inverse_of: :mentions
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false
end
