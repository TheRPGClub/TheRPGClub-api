# frozen_string_literal: true

# Feedback Board (spec api#498, ticket api#501): a reviewer can close Pending
# Feedback as a Duplicate of another (GLOSSARY.md "Duplicate"). Adds the
# `duplicate` status and `duplicate_of_id`, the root original it points at;
# a Duplicate always has one and no other status does.
class AddDuplicateToFeedback < ActiveRecord::Migration[8.1]
  OLD_STATUSES = %w[pending approved rejected withdrawn].freeze
  NEW_STATUSES = (OLD_STATUSES + %w[duplicate]).freeze

  def up
    add_column :rpg_club_feedback, :duplicate_of_id, :bigint
    add_index :rpg_club_feedback, :duplicate_of_id, name: "ix_rpg_club_feedback_duplicate_of"
    add_foreign_key :rpg_club_feedback, :rpg_club_feedback, column: :duplicate_of_id, primary_key: :feedback_id,
      name: "fk_rpg_club_feedback_duplicate_of"
    replace_status_check(NEW_STATUSES)
    add_check_constraint :rpg_club_feedback, "(status = 'duplicate') = (duplicate_of_id IS NOT NULL)",
      name: "ck_rpg_club_feedback_duplicate_of"
  end

  # Duplicates go back to rejected, the nearest old outcome.
  def down
    remove_check_constraint :rpg_club_feedback, name: "ck_rpg_club_feedback_duplicate_of"
    execute "UPDATE rpg_club_feedback SET status = 'rejected', " \
            "rejection_reason = COALESCE(rejection_reason, 'Duplicate of #' || duplicate_of_id) " \
            "WHERE status = 'duplicate'"
    replace_status_check(OLD_STATUSES)
    remove_foreign_key :rpg_club_feedback, name: "fk_rpg_club_feedback_duplicate_of"
    remove_index :rpg_club_feedback, name: "ix_rpg_club_feedback_duplicate_of"
    remove_column :rpg_club_feedback, :duplicate_of_id
  end

  private

  def replace_status_check(statuses)
    remove_check_constraint :rpg_club_feedback, name: "ck_rpg_club_feedback_status"
    add_check_constraint :rpg_club_feedback, "status IN (#{statuses.map { |s| "'#{s}'" }.join(', ')})",
      name: "ck_rpg_club_feedback_status"
  end
end
