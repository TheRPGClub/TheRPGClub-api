# frozen_string_literal: true

# A member's Game of the Year nomination (GLOSSARY "Game of the Year"; spec
# api#471): one game they put forward for a year's GOTY Vote. A member nominates a game once a year and at most
# Goty::Nominate::CAP games; the cap lives in that service, under a lock.
class GotyNomination < ApplicationRecord
  belongs_to :goty_vote, foreign_key: :year, primary_key: :year, inverse_of: :nominations
  belongs_to :user, -> { without_images },
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :goty_nominations
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :goty_nominations

  validates :gamedb_game_id, uniqueness: { scope: %i[year user_id] }
end
