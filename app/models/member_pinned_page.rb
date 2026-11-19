# frozen_string_literal: true

# A Pinned Page (GLOSSARY.md; spec api#416): one row per page a member pinned,
# with its place in their list. Rows are written only through PinnedPages,
# which keeps the list valid and keeps pins the member cannot see right now.
class MemberPinnedPage < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false

  validates :page_key, uniqueness: { scope: :user_id }
end
