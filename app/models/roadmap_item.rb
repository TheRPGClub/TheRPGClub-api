# frozen_string_literal: true

# A Roadmap Item (GLOSSARY.md "Roadmap Item", "Shipped"; spec api#505): one
# planned change, in words members understand, sitting in exactly one
# Milestone at a `position` within it. It may say whether it touches the
# bot, the website or both, and name the GitHub issue it is tracked by.
# `shipped_at` is when staff marked it Shipped, null until then.
class RoadmapItem < ApplicationRecord
  TITLE_MAX = 120
  BLURB_MAX = 500
  GITHUB_ISSUE_URL_MAX = 300
  AREAS = %w[bot website both].freeze
  GITHUB_ISSUE_URL = %r{\Ahttps://github\.com/[\w.-]+/[\w.-]+/issues/\d+\z}

  belongs_to :milestone, class_name: "RoadmapMilestone", inverse_of: :items

  normalizes :title, :blurb, with: ->(value) { value.strip }
  normalizes :area, :github_issue_url, with: ->(value) { value.strip.presence }

  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :blurb, presence: true, length: { maximum: BLURB_MAX }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :area, inclusion: { in: AREAS, message: "must be one of #{AREAS.join(', ')}" }, allow_nil: true
  validates :github_issue_url, length: { maximum: GITHUB_ISSUE_URL_MAX },
    format: { with: GITHUB_ISSUE_URL, message: "must be a GitHub issue URL" }, allow_nil: true

  def shipped? = shipped_at.present?
end
