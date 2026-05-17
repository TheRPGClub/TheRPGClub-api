# frozen_string_literal: true

class SocialPlatform < ApplicationRecord
  self.table_name = "social_platforms"

  has_many :user_socials,
    foreign_key: :platform_id,
    dependent: :restrict_with_error,
    inverse_of: :social_platform

  belongs_to :created_by_user,
    class_name: "RpgClubUser",
    foreign_key: :created_by_user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :created_social_platforms

  validates :label, presence: true
  validates :label, uniqueness: { case_sensitive: false }

  before_validation :strip_label

  private

  def strip_label
    self.label = label&.strip
  end
end
