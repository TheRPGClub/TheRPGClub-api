# frozen_string_literal: true

# Feedback Board (spec api#498, ticket api#499): Suggestions become Feedback,
# each of exactly one kind. The tables, their key column, indexes and
# constraints are renamed; the multi-select `labels` become one `kind`
# (contains Bug -> bug_report; else contains New Feature -> feature_request;
# else suggestion), with a count per kind printed; `labels` is dropped. The
# bot's Discord review sessions are gone with their table.
#
# Down restores the old shape. Labels come back as the kind's one label, and
# review sessions come back empty.
class RenameSuggestionsToFeedback < ActiveRecord::Migration[8.1]
  KINDS = %w[feature_request suggestion bug_report].freeze
  # The old labels each kind maps back to on down.
  DOWN_LABELS = { "feature_request" => "New Feature", "suggestion" => "Improvement", "bug_report" => "Bug" }.freeze

  def up
    drop_table :rpg_club_suggestion_review_sessions

    rename_table :rpg_club_suggestions, :rpg_club_feedback
    rename_column :rpg_club_feedback, :suggestion_id, :feedback_id
    rename_index :rpg_club_feedback, "ix_rpg_club_suggestions_created", "ix_rpg_club_feedback_created"
    rename_index :rpg_club_feedback, "ix_rpg_club_suggestions_status", "ix_rpg_club_feedback_status"
    rename_constraint :rpg_club_feedback, "ck_rpg_club_suggestions_status", "ck_rpg_club_feedback_status"
    rename_key_sequence :rpg_club_feedback, :feedback_id, "rpg_club_feedback_feedback_id_seq"

    rename_table :rpg_club_suggestion_upvotes, :rpg_club_feedback_upvotes
    rename_column :rpg_club_feedback_upvotes, :suggestion_id, :feedback_id
    rename_index :rpg_club_feedback_upvotes, "ux_rpg_club_suggestion_upvotes_suggestion_user",
      "ux_rpg_club_feedback_upvotes_feedback_user"
    rename_index :rpg_club_feedback_upvotes, "ix_rpg_club_suggestion_upvotes_user", "ix_rpg_club_feedback_upvotes_user"
    rename_constraint :rpg_club_feedback_upvotes, "fk_rpg_club_suggestion_upvotes_suggestion",
      "fk_rpg_club_feedback_upvotes_feedback"
    rename_constraint :rpg_club_feedback_upvotes, "fk_rpg_club_suggestion_upvotes_user",
      "fk_rpg_club_feedback_upvotes_user"

    add_column :rpg_club_feedback, :kind, :string, limit: 32
    execute <<~SQL
      UPDATE rpg_club_feedback SET kind = CASE
        WHEN #{label_present('bug')} THEN 'bug_report'
        WHEN #{label_present('new feature')} THEN 'feature_request'
        ELSE 'suggestion'
      END
    SQL
    change_column_null :rpg_club_feedback, :kind, false
    add_check_constraint :rpg_club_feedback, "kind IN (#{KINDS.map { |k| "'#{k}'" }.join(', ')})",
      name: "ck_rpg_club_feedback_kind"
    add_index :rpg_club_feedback, :kind, name: "ix_rpg_club_feedback_kind"
    report_kinds
    remove_column :rpg_club_feedback, :labels
  end

  def down
    add_column :rpg_club_feedback, :labels, :string, limit: 200
    execute <<~SQL
      UPDATE rpg_club_feedback SET labels = CASE kind
        #{DOWN_LABELS.map { |kind, label| "WHEN '#{kind}' THEN '#{label}'" }.join(' ')}
      END
    SQL
    remove_index :rpg_club_feedback, name: "ix_rpg_club_feedback_kind"
    remove_check_constraint :rpg_club_feedback, name: "ck_rpg_club_feedback_kind"
    remove_column :rpg_club_feedback, :kind

    rename_constraint :rpg_club_feedback_upvotes, "fk_rpg_club_feedback_upvotes_user",
      "fk_rpg_club_suggestion_upvotes_user"
    rename_constraint :rpg_club_feedback_upvotes, "fk_rpg_club_feedback_upvotes_feedback",
      "fk_rpg_club_suggestion_upvotes_suggestion"
    rename_index :rpg_club_feedback_upvotes, "ix_rpg_club_feedback_upvotes_user", "ix_rpg_club_suggestion_upvotes_user"
    rename_index :rpg_club_feedback_upvotes, "ux_rpg_club_feedback_upvotes_feedback_user",
      "ux_rpg_club_suggestion_upvotes_suggestion_user"
    rename_column :rpg_club_feedback_upvotes, :feedback_id, :suggestion_id
    rename_table :rpg_club_feedback_upvotes, :rpg_club_suggestion_upvotes

    rename_constraint :rpg_club_feedback, "ck_rpg_club_feedback_status", "ck_rpg_club_suggestions_status"
    rename_index :rpg_club_feedback, "ix_rpg_club_feedback_status", "ix_rpg_club_suggestions_status"
    rename_index :rpg_club_feedback, "ix_rpg_club_feedback_created", "ix_rpg_club_suggestions_created"
    rename_column :rpg_club_feedback, :feedback_id, :suggestion_id
    rename_table :rpg_club_feedback, :rpg_club_suggestions
    rename_key_sequence :rpg_club_suggestions, :suggestion_id, "rpg_club_suggestions_suggestion_id_seq"

    create_table :rpg_club_suggestion_review_sessions, primary_key: :session_id,
      id: { type: :string, limit: 120 } do |t|
      t.timestamptz :created_at, null: false, default: -> { "statement_timestamp()" }
      t.bigint :current_index, null: false, default: 0
      t.string :reviewer_id, limit: 30, null: false
      t.string :suggestion_ids, limit: 4000, null: false
      t.bigint :total_count, null: false, default: 0
      t.timestamptz :updated_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_index :rpg_club_suggestion_review_sessions, :created_at, name: "ix_rpg_club_sug_rev_sess_created"
    add_index :rpg_club_suggestion_review_sessions, :reviewer_id, name: "ix_rpg_club_sug_rev_sess_reviewer"
  end

  private

  # Whether the comma-separated `labels` hold `label` (trimmed, any case).
  def label_present(label)
    "EXISTS (SELECT 1 FROM unnest(string_to_array(labels, ',')) AS l(label) " \
      "WHERE lower(btrim(l.label)) = '#{label}')"
  end

  def rename_constraint(table, from, to)
    execute "ALTER TABLE #{quote_table_name(table)} RENAME CONSTRAINT #{quote_column_name(from)} " \
            "TO #{quote_column_name(to)}"
  end

  # The key column's sequence, named for its table and column (Rails then
  # dumps a plain primary key). Skipped when the column owns no sequence or
  # rename_table already gave it that name.
  def rename_key_sequence(table, column, name)
    sequence = select_value("SELECT pg_get_serial_sequence(#{connection.quote(table.to_s)}, " \
                            "#{connection.quote(column.to_s)})")
    return if sequence.nil? || sequence.split(".").last.delete('"') == name

    execute "ALTER SEQUENCE #{sequence} RENAME TO #{quote_column_name(name)}"
  end

  def report_kinds
    counts = select_rows("SELECT kind, COUNT(*) FROM rpg_club_feedback GROUP BY kind").to_h
    say "Feedback kinds: #{KINDS.map { |kind| "#{kind}=#{counts.fetch(kind, 0)}" }.join(', ')}"
  end
end
