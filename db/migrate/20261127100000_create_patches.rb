# frozen_string_literal: true

# Patches (GLOSSARY.md "Patch"; spec api#510, ticket api#511): the numbered
# posts of Patch Notes. `number` comes from its own sequence, so a number is
# never handed out twice, even after its Patch is deleted.
class CreatePatches < ActiveRecord::Migration[8.1]
  def change
    create_table :patches, comment: "Patch Notes' numbered Patches (spec api#510)." do |t|
      t.serial :number, null: false, comment: "Assigned on creation from its own sequence; never reused."
      t.string :title, limit: 100, comment: "Optional, e.g. \"The Franchise update\"."
      t.jsonb :rich_body, null: false, default: [], comment: "The Plate value the website edits."
      t.text :body, null: false, default: "", comment: "The full text as Discord markdown, made by the website."
      t.text :cut_body, null: false, default: "",
        comment: "The Discord markdown cut to the Discord limit, made by the website; what the bot posts."
      t.string :status, null: false, default: "draft", comment: "draft or published."
      t.timestamptz :published_at, comment: "When it was last published; NULL while a draft."
      t.timestamps

      t.index :number, unique: true
      t.index %i[status number]
      t.check_constraint "status IN ('draft', 'published')", name: "ck_patches_status"
      t.check_constraint "(status = 'published') = (published_at IS NOT NULL)", name: "ck_patches_published_at"
    end
  end
end
