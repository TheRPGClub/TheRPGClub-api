# frozen_string_literal: true

# Birthdays (api#398, ADR 0011): a Birth Date is stored as a month, a day and
# an optional year, so a member can give a Birthday without a birth year. The
# member's Birth Date and the audit of its changes both move to the same three
# columns; every existing date keeps its day, month and year.
#
# Going down puts dated Birth Dates back in the old date column. A year-less
# one can't be a date, so it is dropped.
class SplitBirthDateIntoDayMonthAndYear < ActiveRecord::Migration[8.1]
  TABLES = {
    rpg_club_users: "The member's Birth Date",
    member_birth_date_changes: "The Birth Date it was set to (null when removed)"
  }.freeze
  OLD_COMMENTS = {
    rpg_club_users: "The member's Birth Date. Only the member and staff see the full date.",
    member_birth_date_changes: "The Birth Date it was set to (null when removed)."
  }.freeze

  def up
    TABLES.each do |table, what|
      add_column table, :birth_month, :integer, limit: 2, comment: "#{what}: its month, 1 to 12."
      add_column table, :birth_day, :integer, limit: 2,
        comment: "#{what}: its day of the month (29 February allowed without a year)."
      add_column table, :birth_year, :integer, limit: 2,
        comment: "#{what}: its year, or null when the member gave only the day and month."
      execute <<~SQL.squish
        UPDATE #{table} SET birth_month = EXTRACT(MONTH FROM birth_date), birth_day = EXTRACT(DAY FROM birth_date),
          birth_year = EXTRACT(YEAR FROM birth_date)
        WHERE birth_date IS NOT NULL
      SQL
      remove_column table, :birth_date
      add_check_constraint table, <<~SQL.squish, name: "ck_#{table}_birth_date"
        (birth_month IS NULL AND birth_day IS NULL AND birth_year IS NULL)
        OR (birth_month BETWEEN 1 AND 12
            AND birth_day BETWEEN 1 AND (CASE WHEN birth_month = 2 THEN 29
                                              WHEN birth_month IN (4, 6, 9, 11) THEN 30 ELSE 31 END))
      SQL
    end
  end

  def down
    OLD_COMMENTS.each do |table, comment|
      add_column table, :birth_date, :date, comment: comment
      execute <<~SQL.squish
        UPDATE #{table} SET birth_date = make_date(birth_year, birth_month, birth_day) WHERE birth_year IS NOT NULL
      SQL
      remove_check_constraint table, name: "ck_#{table}_birth_date"
      remove_column table, :birth_month
      remove_column table, :birth_day
      remove_column table, :birth_year
    end
  end
end
