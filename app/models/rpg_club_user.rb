# frozen_string_literal: true

class RpgClubUser < ApplicationRecord
  self.table_name = "rpg_club_users"
  self.primary_key = "user_id"

  BINARY_COLUMNS = %w[avatar_blob profile_image].freeze

  has_many :avatar_history,
    class_name: "RpgClubUserAvatarHistory",
    foreign_key: :user_id,
    primary_key: :user_id,
    dependent: nil,
    inverse_of: :user

  has_many :game_collections,
    class_name: "UserGameCollection",
    foreign_key: :user_id,
    primary_key: :user_id,
    dependent: nil,
    inverse_of: :user
  has_many :game_completions,
    class_name: "UserGameCompletion",
    foreign_key: :user_id,
    primary_key: :user_id,
    dependent: nil,
    inverse_of: :user
  has_many :game_favorites,
    class_name: "UserGameFavorite",
    foreign_key: :user_id,
    primary_key: :user_id,
    dependent: nil,
    inverse_of: :user
  has_many :game_backlog_entries,
    class_name: "UserGameBacklog",
    foreign_key: :user_id,
    primary_key: :user_id,
    dependent: nil,
    inverse_of: :user
  has_many :uploaded_game_images,
    class_name: "GamedbGameImage",
    foreign_key: :uploaded_by_user_id,
    primary_key: :user_id,
    dependent: nil,
    inverse_of: :uploaded_by

  has_many :socials,
    class_name: "UserSocial",
    foreign_key: :user_id,
    primary_key: :user_id,
    dependent: :destroy,
    inverse_of: :user
  has_many :platforms,
    through: :socials,
    source: :social_platform
  has_many :created_social_platforms,
    class_name: "SocialPlatform",
    foreign_key: :created_by_user_id,
    primary_key: :user_id,
    dependent: :nullify,
    inverse_of: :created_by_user

  scope :without_images, -> { select(*(column_names - BINARY_COLUMNS)) }

  validates :user_id, presence: true

  def self.upsert_from_discord!(payload)
    user = find_or_initialize_by(user_id: payload.fetch("id").to_s)
    user.is_bot = false if user.has_attribute?(:is_bot) && user.new_record?
    user.username = payload["username"] if user.has_attribute?(:username)
    user.global_name = payload["global_name"] if user.has_attribute?(:global_name)
    user.discord_avatar = payload["avatar"] if user.has_attribute?(:discord_avatar)
    user.last_fetched_at = Time.current if user.has_attribute?(:last_fetched_at)

    %w[role_admin role_moderator role_regular role_member role_newcomer donor_notify_on_claim].each do |column|
      user[column] = false if user.has_attribute?(column) && user[column].nil?
    end

    user.save!
    user
  end

  def membership
    {
      admin: role_admin?,
      moderator: role_moderator?,
      regular: role_regular?,
      member: role_member?,
      newcomer: role_newcomer?,
      active: server_left_at.nil?
    }
  end
end
