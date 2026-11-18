# frozen_string_literal: true

class CodexEntry
  # A Club Codex entry's date, as precise as the club remembers it (spec
  # #397): `occurred_on` with its `date_precision`, day, month or year. Both
  # are given, or neither. Whether a part must, may or mustn't be dated is
  # the part's own rule.
  #
  # A `month` or `year` date is stored at the start of its period, the 1st of
  # the month or 1 January, as Release dates are (ticket #407). Unlike a
  # Release, a vague date given on another day is moved there rather than
  # refused: members pick "March 2018" on a form, and whichever day comes
  # with it means nothing.
  #
  # `occurred_on` must arrive as a real `YYYY-MM-DD` date (or a Date). Any
  # other text is refused rather than read loosely or dropped.
  module Dated
    extend ActiveSupport::Concern

    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/

    # The day a date at `date_precision` is stored on: the 1st of its month,
    # 1 January of its year, or the day itself.
    def self.period_start(date, date_precision)
      case date_precision
      when "month" then date.beginning_of_month
      when "year" then date.beginning_of_year
      else date
      end
    end

    included do
      normalizes :date_precision, with: ->(value) { value.strip.presence }

      before_validation :snap_occurred_on

      validates :date_precision, inclusion: { in: DATE_PRECISIONS, message: "must be one of #{DATE_PRECISIONS.join(', ')}" },
        allow_nil: true
      validate :occurred_on_is_a_date
      validates :occurred_on, presence: true, if: -> { date_precision.present? && !unreadable_occurred_on? }
      validates :date_precision, presence: true, if: -> { occurred_on.present? && !unreadable_occurred_on? }
    end

    private

    def snap_occurred_on
      return if occurred_on.nil? || unreadable_occurred_on?

      self.occurred_on = Dated.period_start(occurred_on, date_precision)
    end

    # Text given for `occurred_on` that isn't a real `YYYY-MM-DD` date, which
    # would otherwise read as no date or be read loosely. Nil and blank are
    # no date.
    def unreadable_occurred_on?
      given = occurred_on_before_type_cast
      given.is_a?(String) && given.present? && (!given.match?(ISO_DATE) || occurred_on.nil?)
    end

    def occurred_on_is_a_date
      errors.add(:occurred_on, "must be a date (YYYY-MM-DD)") if unreadable_occurred_on?
    end
  end
end
