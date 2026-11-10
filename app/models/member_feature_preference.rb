# frozen_string_literal: true

# A Feature Preference (GLOSSARY.md, "Features"; spec #347): one row per
# member per Feature they hid from their own view of the website. Only hidden
# Features are stored, so everything is shown by default. Core Features
# cannot be hidden. Preferences narrow what the website shows
# (Features::Access#shown?) and never who can use a Feature.
class MemberFeaturePreference < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false

  validates :feature_key, uniqueness: { scope: :user_id }
  validate :feature_is_hideable

  # The Feature keys `user_id` has hidden, in registry order.
  def self.hidden_keys(user_id)
    stored = where(user_id: user_id).pluck(:feature_key)
    Features.keys & stored
  end

  private

  def feature_is_hideable
    feature = Features.find(feature_key)
    if feature.nil?
      errors.add(:feature_key, "is not a registered Feature")
    elsif feature.core?
      errors.add(:feature_key, "is a Core Feature, which cannot be hidden")
    end
  end
end
