# frozen_string_literal: true

# A small key/value store for the Achievement Hub's singletons: the bot's
# Highlight cursor and `psn_auth_expired_at`.
class AchievementHubState < ApplicationRecord
  validates :key, presence: true, uniqueness: true
end
