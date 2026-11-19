# frozen_string_literal: true

# A Pinned Page (GLOSSARY.md; spec api#416): one row per page a member pinned,
# with its place in their list. Rows are written only through PinnedPages,
# which keeps the list valid and keeps pins the member cannot see right now.
class MemberPinnedPage < ApplicationRecord
  # A page appears once per member. The unique index on (user_id, page_key)
  # is the guard: PinnedPages writes with insert_all!, which skips model
  # validations, after refusing a duplicate itself.
  belongs_to :user, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false
end
