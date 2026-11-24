# frozen_string_literal: true

# Pool Proposals (spec api#442, ticket api#447; GLOSSARY.md "Pool Proposal"):
# a member proposes a game for a Pool Challenge, with an optional note, and
# the Host (staff for a club-hosted Challenge) accepts it as a Core or
# Optional Game, or declines it. Only one proposal per game per Challenge is
# pending at a time.
class CreateChallengePoolProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_pool_proposals do |t|
      t.bigint :challenge_id, null: false
      t.bigint :game_id, null: false
      t.string :user_id, limit: 30, null: false
      t.string :note, limit: 280
      t.string :status, limit: 16, null: false, default: "pending"
      t.string :accepted_as, limit: 16
      t.string :decided_by, limit: 30
      t.timestamptz :decided_at
      t.timestamps

      t.index %i[challenge_id game_id], unique: true, where: "status = 'pending'",
        name: "ux_challenge_pool_proposals_one_pending"
      t.index %i[challenge_id status created_at], name: "ix_challenge_pool_proposals_challenge"
      t.index :user_id, name: "ix_challenge_pool_proposals_user"
      t.check_constraint "status IN ('pending', 'accepted', 'declined')", name: "ck_challenge_pool_proposals_status"
      t.check_constraint "(status = 'accepted') = (accepted_as IS NOT NULL) AND " \
                         "(accepted_as IS NULL OR accepted_as IN ('core', 'optional'))",
        name: "ck_challenge_pool_proposals_accepted_as"
      t.check_constraint "(status = 'pending') = (decided_at IS NULL)", name: "ck_challenge_pool_proposals_decided"
    end
    add_foreign_key :challenge_pool_proposals, :challenges, on_delete: :cascade,
      name: "fk_challenge_pool_proposals_challenge"
    add_foreign_key :challenge_pool_proposals, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade, name: "fk_challenge_pool_proposals_game"
    add_foreign_key :challenge_pool_proposals, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_challenge_pool_proposals_user"
  end
end
