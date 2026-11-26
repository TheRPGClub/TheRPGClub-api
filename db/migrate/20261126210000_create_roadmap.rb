# frozen_string_literal: true

# The Roadmap (GLOSSARY.md "Roadmap"; spec api#505, ticket api#506).
#
# Milestones: one ordered sequence by `position`, Reached or not. A Reached
# Milestone keeps its position, so taking it back from Reached puts it back
# among the open ones where it was. `target_date` is stored at its Date
# Precision as a Release's is (the first day of its month, quarter or year;
# none for TBA, the default). `reached_at` is null while it is open.
#
# Roadmap Items: each sits in exactly one Milestone, at a `position` within
# it, and stops a Milestone that still has items from being deleted.
# `shipped_at` is null until staff mark it Shipped. Positions are not unique,
# so a reorder or move can rewrite them in any order; reads break ties on id.
class CreateRoadmap < ActiveRecord::Migration[8.1]
  def change
    create_table :roadmap_milestones do |t|
      t.string :name, limit: 100, null: false
      t.string :blurb, limit: 280
      t.date :target_date
      t.string :date_precision, limit: 8, null: false, default: "tba"
      t.integer :position, null: false
      t.timestamptz :reached_at
      t.timestamps

      t.check_constraint "date_precision IN ('day', 'month', 'quarter', 'year', 'tba')",
        name: "ck_roadmap_milestones_date_precision"
      t.check_constraint "(date_precision = 'tba') = (target_date IS NULL)",
        name: "ck_roadmap_milestones_tba_has_no_date"
      t.check_constraint "position >= 1", name: "ck_roadmap_milestones_position"
    end
    add_index :roadmap_milestones, :position, name: "ix_roadmap_milestones_position"

    create_table :roadmap_items do |t|
      t.bigint :milestone_id, null: false
      t.string :title, limit: 120, null: false
      t.string :blurb, limit: 500, null: false
      t.integer :position, null: false
      t.string :area, limit: 8
      t.string :github_issue_url, limit: 300
      t.timestamptz :shipped_at
      t.timestamps

      t.check_constraint "area IN ('bot', 'website', 'both')", name: "ck_roadmap_items_area"
      t.check_constraint "position >= 1", name: "ck_roadmap_items_position"
    end
    add_index :roadmap_items, %i[milestone_id position], name: "ix_roadmap_items_milestone_position"
    add_foreign_key :roadmap_items, :roadmap_milestones, column: :milestone_id,
      on_delete: :restrict, name: "fk_roadmap_items_milestone"
  end
end
