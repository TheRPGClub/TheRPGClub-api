# frozen_string_literal: true

# A Dashboard Panel (GLOSSARY.md; spec api#421): one row per panel a member
# shows on their dashboard, with its place in their list. Rows are written only
# through DashboardPanels, which keeps the list valid and keeps panels the
# member cannot see right now.
class MemberDashboardPanel < ApplicationRecord
  # A panel appears once per member. The unique index on (user_id, panel_key)
  # is the guard: DashboardPanels writes with insert_all!, which skips model
  # validations, after refusing a duplicate itself.
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false
end
