# frozen_string_literal: true

# Pending Changes (GLOSSARY.md "Pending Change"; spec api#510, ticket
# api#514): one per merged pull request, reported by the versioning job, until
# staff cover it in a Patch or dismiss it. Each repo's current version is the
# version of its newest Pending Change.
class CreatePendingChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_changes, comment: "Merged pull requests waiting for a Patch (spec api#510)." do |t|
      t.string :repo, null: false, comment: "api, bot or www."
      t.integer :pr_number, null: false, comment: "The merged pull request's number in its repo."
      t.string :change_type, null: false, comment: "The pull request title's type, e.g. feat, fix, perf."
      t.string :title, null: false, limit: 300, comment: "The pull request's title."
      t.string :version, null: false, limit: 50, comment: "The repo's version this merge produced."
      t.string :patch_note, limit: 500, comment: "The pull request's optional \"Patch note:\" line."
      t.references :patch, foreign_key: { on_delete: :nullify }, comment: "The Patch that covers it, if any."
      t.timestamptz :dismissed_at, comment: "When staff dismissed it; NULL unless dismissed."
      t.timestamps

      t.index %i[repo pr_number], unique: true
      t.check_constraint "repo IN ('api', 'bot', 'www')", name: "ck_pending_changes_repo"
      t.check_constraint "patch_id IS NULL OR dismissed_at IS NULL", name: "ck_pending_changes_covered_or_dismissed"
    end
  end
end
