# frozen_string_literal: true

class GamedbGameImage < ApplicationRecord
  self.table_name = "gamedb_game_images"
  self.primary_key = "image_id"

  KINDS = %w[cover artwork logo].freeze

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :game_id,
    primary_key: :game_id,
    inverse_of: :images

  belongs_to :uploaded_by,
    class_name: "RpgClubUser",
    foreign_key: :uploaded_by_user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :uploaded_game_images

  scope :primary_first, -> { order(is_primary: :desc, position: :asc, image_id: :asc) }

  validates :kind, inclusion: { in: KINDS }
  validates :object_key, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  def url
    Backblaze::Client.public_url_for(object_key)
  end
end
