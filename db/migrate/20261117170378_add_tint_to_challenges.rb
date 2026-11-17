# frozen_string_literal: true

# The Challenge tint (spec #376; DESIGN.md "Challenges inks"): each Challenge
# keeps one colour pair, `tint_fill` (the flyer and banner ground, under paper
# type) and `tint_hi` (the same hue lifted for type and marks on ink), so the
# bot and the website show the same one. Lowercase #rrggbb.
#
# Existing Challenges get the tint a new one would (Challenges::Tint.fallback):
# holly for an Assignment Challenge (Secret Santa), otherwise one of the other
# seven curated tints, turning through them by id.
class AddTintToChallenges < ActiveRecord::Migration[8.1]
  ROTATION = [
    %w[#1f6b67 #6fd6cc], %w[#2c4f8e #9ab8f2], %w[#7a531c #e0b56e], %w[#3b5a2b #a9cf86],
    %w[#2a5ea6 #9cc2f5], %w[#3a3a52 #b4b4d6], %w[#8a6417 #e6c36a]
  ].freeze
  HOLLY = %w[#1c6545 #3fbf8a].freeze

  def up
    change_table :challenges, bulk: true do |t|
      t.string :tint_fill, limit: 7
      t.string :tint_hi, limit: 7
    end

    execute <<~SQL.squish
      UPDATE challenges SET
        tint_fill = CASE WHEN challenge_format = 'assignment' THEN '#{HOLLY[0]}' ELSE (#{array(0)})[id % 7 + 1] END,
        tint_hi = CASE WHEN challenge_format = 'assignment' THEN '#{HOLLY[1]}' ELSE (#{array(1)})[id % 7 + 1] END
    SQL

    change_table :challenges, bulk: true do |t|
      t.change_null :tint_fill, false
      t.change_null :tint_hi, false
      t.check_constraint "tint_fill ~ '^#[0-9a-f]{6}$' AND tint_hi ~ '^#[0-9a-f]{6}$'", name: "ck_challenges_tint"
    end
  end

  def down
    change_table :challenges, bulk: true do |t|
      t.remove_check_constraint name: "ck_challenges_tint"
      t.remove :tint_fill, :tint_hi
    end
  end

  private

  def array(index) = "ARRAY[#{ROTATION.map { |pair| "'#{pair[index]}'" }.join(', ')}]"
end
