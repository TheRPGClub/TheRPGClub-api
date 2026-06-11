# frozen_string_literal: true

# `display_text` on `user_socials` is a human-readable *label*, but it was
# enforced as a uniqueness key (NOT NULL + `index_user_socials_on_user_platform_display_text`).
# Generic labels ("Profile Link", "Steam", "My profile") naturally repeat, so a
# user linking a second account on the same platform got a bogus 422
# (TheRPGClub#80). The label is the one field that legitimately collides.
#
# This moves identity off the label and onto the URL:
#   * drop the `(user_id, platform_id, display_text)` unique index,
#   * make `display_text` nullable (callers no longer have to invent a label —
#     this is also why the Completionator backfill, 20260517000300, had to shove
#     the URL into `display_text` to satisfy NOT NULL),
#   * normalise `url` (trim, blank -> NULL) and dedupe true duplicate links,
#   * add a partial unique index on `(user_id, platform_id, lower(url))` for rows
#     that have a URL, so "one account per URL" still holds without ever
#     rejecting a label. URL-less platforms (PSN, Switch friend code) keep
#     multiple rows since NULLs are distinct — that's intended.
class RelaxUserSocialsDisplayTextUniqueness < ActiveRecord::Migration[8.1]
  OLD_INDEX = "index_user_socials_on_user_platform_display_text"
  NEW_INDEX = "index_user_socials_on_user_platform_url"

  def up
    remove_index :user_socials, name: OLD_INDEX, if_exists: true

    change_column_null :user_socials, :display_text, true

    # Normalise URLs first (trim, collapse blanks to NULL) so the partial index's
    # `url IS NOT NULL` predicate and the dedupe below see a consistent value.
    execute(<<~SQL.squish)
      UPDATE user_socials SET url = NULLIF(TRIM(url), '')
    SQL

    # Resolve existing collisions before adding the identity-based unique index:
    # for each (user_id, platform_id, lower(url)) group with a URL, keep the
    # lowest id and drop the rest.
    execute(<<~SQL.squish)
      DELETE FROM user_socials a
      USING user_socials b
      WHERE a.url IS NOT NULL
        AND b.url IS NOT NULL
        AND a.user_id = b.user_id
        AND a.platform_id = b.platform_id
        AND LOWER(a.url) = LOWER(b.url)
        AND a.id > b.id
    SQL

    add_index :user_socials, "user_id, platform_id, lower(url)",
              unique: true,
              where: "url IS NOT NULL",
              name: NEW_INDEX,
              if_not_exists: true
  end

  def down
    remove_index :user_socials, name: NEW_INDEX, if_exists: true

    # Re-establishing the NOT NULL label requires a value for every row: fall
    # back to the URL, then to a placeholder for genuinely label-less rows.
    execute(<<~SQL.squish)
      UPDATE user_socials
      SET display_text = COALESCE(NULLIF(TRIM(display_text), ''), url, 'link')
      WHERE display_text IS NULL OR TRIM(display_text) = ''
    SQL

    # Dedupe labels before restoring the old unique index.
    execute(<<~SQL.squish)
      DELETE FROM user_socials a
      USING user_socials b
      WHERE a.user_id = b.user_id
        AND a.platform_id = b.platform_id
        AND a.display_text = b.display_text
        AND a.id > b.id
    SQL

    change_column_null :user_socials, :display_text, false

    add_index :user_socials, %i[user_id platform_id display_text],
              unique: true,
              name: OLD_INDEX,
              if_not_exists: true
  end
end
