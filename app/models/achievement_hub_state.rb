# frozen_string_literal: true

# A small key/value store for the Achievement Hub's singletons: the bot's
# Highlight cursor and `psn_auth_expired_at`. Values are JSON.
class AchievementHubState < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key)
    where(key: key).pick(:value)
  end

  def self.set(key, value)
    upsert({ key: key, value: value }, unique_by: :key)
    value
  end
end
