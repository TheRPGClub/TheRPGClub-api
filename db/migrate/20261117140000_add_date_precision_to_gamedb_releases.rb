# frozen_string_literal: true

# Release Calendar (api#392): a Release's date becomes a plain calendar date
# with no time zone, and every Release records its Date Precision (`day`,
# `month`, `quarter`, `year` or `tba`). Existing timestamps were written as UTC,
# so each keeps its UTC calendar day. Existing dated Releases read as `day`
# (their real precision was never recorded; a refresh corrects it), and an
# undated one reads as `tba`, the only precision that stores no date.
class AddDatePrecisionToGamedbReleases < ActiveRecord::Migration[8.1]
  def up
    change_column :gamedb_releases, :release_date, :date, using: "release_date::date"
    add_column :gamedb_releases, :date_precision, :string, limit: 10, null: false, default: "day"
    execute "UPDATE gamedb_releases SET date_precision = 'tba' WHERE release_date IS NULL"
    add_check_constraint :gamedb_releases, "date_precision IN ('day', 'month', 'quarter', 'year', 'tba')",
      name: "ck_gamedb_releases_date_precision"
    add_check_constraint :gamedb_releases, "(date_precision = 'tba') = (release_date IS NULL)",
      name: "ck_gamedb_releases_tba_has_no_date"
  end

  def down
    remove_check_constraint :gamedb_releases, name: "ck_gamedb_releases_tba_has_no_date"
    remove_check_constraint :gamedb_releases, name: "ck_gamedb_releases_date_precision"
    remove_column :gamedb_releases, :date_precision
    change_column :gamedb_releases, :release_date, :datetime, precision: 0, using: "release_date::timestamp"
  end
end
