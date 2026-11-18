# frozen_string_literal: true

class CodexEntry
  # An entry's date, as precise as the club remembers it (spec #397):
  # `occurred_on` with its `date_precision`, day, month or year, given
  # together or not at all. A `month` date is kept on the 1st of its month
  # and a `year` date on 1 January, as with Release dates; a date anywhere
  # in the period is moved to its start rather than refused, since members
  # type these on a form.
  module Dated
    extend ActiveSupport::Concern

    included do
      before_validation :snap_occurred_on

      validates :date_precision, inclusion: { in: DATE_PRECISIONS, message: "must be one of #{DATE_PRECISIONS.join(', ')}" },
        allow_nil: true
      validate :occurred_on_is_a_date
      validates :occurred_on, presence: true, if: -> { date_precision.present? && !unreadable_occurred_on? }
      validates :date_precision, presence: true, if: -> { occurred_on.present? }
    end

    private

    def snap_occurred_on
      return if occurred_on.nil?

      self.occurred_on =
        case date_precision
        when "month" then occurred_on.beginning_of_month
        when "year" then occurred_on.beginning_of_year
        else occurred_on
        end
    end

    # A value given that isn't a real YYYY-MM-DD date, which would otherwise
    # read as no date at all.
    def unreadable_occurred_on? = occurred_on.nil? && occurred_on_before_type_cast.present?

    def occurred_on_is_a_date
      errors.add(:occurred_on, "must be a date (YYYY-MM-DD)") if unreadable_occurred_on?
    end
  end
end
