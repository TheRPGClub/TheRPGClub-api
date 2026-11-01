# frozen_string_literal: true

# An Achievement Set: the full list of Achievements a Provider defines for one
# title, shared by every member (ADR 0001). `external_id` is the RA game id,
# Steam appid or PSN npCommunicationId; `np_service_name` is PSN only. A GameDB
# game may have several sets (e.g. separate PS4 and PS5 lists).
class AchievementSet < ApplicationRecord
  enum :provider, UserLinkedAccount::PROVIDERS.index_with(&:itself), validate: true

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :game_id,
    primary_key: :game_id,
    optional: true,
    inverse_of: :achievement_sets
  has_many :achievements,
    dependent: nil, # on delete cascade
    inverse_of: :achievement_set
  has_many :progress,
    class_name: "UserAchievementSetProgress",
    dependent: nil, # on delete cascade
    inverse_of: :achievement_set

  validates :external_id, presence: true, uniqueness: { scope: :provider }

  # Best-effort GameDB link (research §6); see Achievements::LinkSetToGame.
  after_create_commit { Achievements::LinkSetToGameJob.perform_later(self) }
end
