# frozen_string_literal: true

# A member's Birth Date (ADR 0011): a month, a day and an optional year. A
# Birth Date without a year is a Birthday alone and counts as having no birth
# year. Served as "1990-05-04", or "05-04" without a year.
BirthDate = Data.define(:month, :day, :year) do
  def year? = !year.nil?

  def to_s
    year? ? format("%04d-%02d-%02d", year, month, day) : format("%02d-%02d", month, day)
  end
end
