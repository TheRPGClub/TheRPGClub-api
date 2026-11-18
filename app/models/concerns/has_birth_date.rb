# frozen_string_literal: true

# A record that holds a Birth Date in `birth_month`, `birth_day` and
# `birth_year` (ADR 0011), read and written as one BirthDate, or nil.
module HasBirthDate
  extend ActiveSupport::Concern

  included do
    composed_of :birth_date, class_name: "BirthDate", allow_nil: true,
      mapping: [ %w[birth_month month], %w[birth_day day], %w[birth_year year] ]
  end
end
