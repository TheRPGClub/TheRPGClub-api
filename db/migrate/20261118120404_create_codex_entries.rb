# frozen_string_literal: true

# The Club Codex (GLOSSARY.md, "Club Codex"; spec #397, ticket #404).
#
# One table holds the entries of all three parts, told apart by `part`:
# History Events, Lore Entries and Fun Facts. Mentions, "See also" links and
# images hang off the one entry id, so they work the same for every part.
# Every column the spec lists is here from the start, so each part's tickets
# add endpoints and model rules without changing this table:
#
#   title           History Events and Lore Entries (required); Fun Facts have none
#   rich_body       the Plate.js story or description, stored as given and never checked
#   body            the Discord-readable text: a Fun Fact itself (up to 300
#                   characters, mention tokens included), or the Discord
#                   markdown the website makes from `rich_body`, required with it
#   occurred_on,    required for History Events, optional for Lore Entries, absent
#   date_precision  for Fun Facts; given together. A `month` date is the first of
#                   its month and a `year` date 1 January, as with Release dates
#   kind            the History Event Kind; History Events only
#   author_user_id  the member who wrote it, kept when they leave the server
#   last_shown_at   Fun Facts only: when the queue last drew it; null until then
#
# The checks below hold what the spec settles for every part; finer rules
# (such as the 300-character Fun Fact) are also checked in CodexEntry, so a
# client gets a 422 rather than a constraint error.
#
# Mentions: the members a `body`'s `<@discord_id>` tokens name, one row per
# member per entry, pulled out on every save. They go with their entry.
class CreateCodexEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_entries do |t|
      t.string :part, limit: 16, null: false
      t.string :title, limit: 100
      t.jsonb :rich_body
      t.text :body
      t.date :occurred_on
      t.string :date_precision, limit: 8
      t.string :kind, limit: 16
      t.string :author_user_id, limit: 30, null: false
      t.timestamptz :last_shown_at
      t.timestamps

      t.check_constraint "part IN ('history_event', 'lore_entry', 'fun_fact')", name: "ck_codex_entries_part"
      t.check_constraint "kind IN ('founding', 'staff', 'platform', 'rules', 'milestone')",
        name: "ck_codex_entries_kind"
      t.check_constraint "(kind IS NOT NULL) = (part = 'history_event')", name: "ck_codex_entries_kind_part"
      t.check_constraint "(title IS NOT NULL) = (part <> 'fun_fact')", name: "ck_codex_entries_title_part"
      t.check_constraint "rich_body IS NULL OR body IS NOT NULL", name: "ck_codex_entries_body_with_rich_body"
      t.check_constraint "part = 'history_event' OR body IS NOT NULL", name: "ck_codex_entries_body_part"
      t.check_constraint "part <> 'fun_fact' OR (rich_body IS NULL AND char_length(body) <= 300)",
        name: "ck_codex_entries_fun_fact_body"
      t.check_constraint "date_precision IN ('day', 'month', 'year')", name: "ck_codex_entries_date_precision"
      t.check_constraint "(occurred_on IS NULL) = (date_precision IS NULL)", name: "ck_codex_entries_date_given_together"
      t.check_constraint "date_precision = 'day' OR EXTRACT(DAY FROM occurred_on) = 1", name: "ck_codex_entries_month_starts"
      t.check_constraint "date_precision <> 'year' OR EXTRACT(MONTH FROM occurred_on) = 1",
        name: "ck_codex_entries_year_starts"
      t.check_constraint "part <> 'history_event' OR occurred_on IS NOT NULL", name: "ck_codex_entries_history_dated"
      t.check_constraint "part <> 'fun_fact' OR occurred_on IS NULL", name: "ck_codex_entries_fun_fact_undated"
      t.check_constraint "part = 'fun_fact' OR last_shown_at IS NULL", name: "ck_codex_entries_last_shown_fun_fact"
    end
    # Club Lore and Fun Facts, newest first.
    add_index :codex_entries, %i[part created_at id], name: "ix_codex_entries_part_created"
    # Club History, in date order.
    add_index :codex_entries, %i[occurred_on id], where: "part = 'history_event'", name: "ix_codex_entries_history"
    # The Fun Fact queue: never shown first, then shown longest ago.
    add_index :codex_entries, %i[last_shown_at id], where: "part = 'fun_fact'", name: "ix_codex_entries_fun_fact_queue"
    add_index :codex_entries, :author_user_id, name: "ix_codex_entries_author"
    add_foreign_key :codex_entries, :rpg_club_users, column: :author_user_id, primary_key: :user_id,
      name: "fk_codex_entries_author"

    create_table :codex_entry_mentions, primary_key: %i[entry_id user_id] do |t|
      t.bigint :entry_id, null: false
      t.string :user_id, limit: 30, null: false
    end
    add_index :codex_entry_mentions, :user_id, name: "ix_codex_entry_mentions_user"
    add_foreign_key :codex_entry_mentions, :codex_entries, column: :entry_id, on_delete: :cascade,
      name: "fk_codex_entry_mentions_entry"
    add_foreign_key :codex_entry_mentions, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_codex_entry_mentions_user"
  end
end
