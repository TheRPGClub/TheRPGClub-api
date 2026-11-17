# frozen_string_literal: true

# One time a member's Birth Date was set, changed or removed (ticket #380).
# The member's own changes count toward their limit of two per calendar
# month; staff changes are kept for the record but flagged `by_staff` and
# never count.
class MemberBirthDateChange < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id, inverse_of: false

  scope :by_member, -> { where(by_staff: false) }
end
