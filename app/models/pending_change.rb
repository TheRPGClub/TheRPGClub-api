# frozen_string_literal: true

# A Pending Change (GLOSSARY.md "Pending Change"; spec api#510, ticket
# api#514): one merged pull request of the club's api, bot or www, reported by
# the versioning job, waiting until staff cover it in a Patch or dismiss it.
# One per repo and pull request number.
#
# Its status follows from its columns: covered while a Patch covers it,
# dismissed once staff dismissed it, open otherwise (never both).
class PendingChange < ApplicationRecord
  REPOS = %w[api bot www].freeze
  # The pull request title types the title check allows (spec api#510).
  TYPES = %w[feat fix perf refactor chore docs test ci].freeze
  # The Patch section a type's change drafts into; every other type (only
  # reported when marked breaking) counts as Improved.
  SECTIONS = { "feat" => "new", "fix" => "fixed" }.freeze
  OPEN = "open"
  COVERED = "covered"
  DISMISSED = "dismissed"
  STATUSES = [ OPEN, COVERED, DISMISSED ].freeze
  VERSION_FORMAT = /\A\d+\.\d+\.\d+\z/
  TITLE_MAX = 300
  PATCH_NOTE_MAX = 500

  belongs_to :patch, optional: true

  validates :repo, inclusion: { in: REPOS }
  validates :change_type, inclusion: { in: TYPES }
  validates :pr_number, numericality: { only_integer: true, greater_than: 0, less_than: 2**31 }
  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :version, format: { with: VERSION_FORMAT }
  validates :patch_note, length: { maximum: PATCH_NOTE_MAX }

  normalizes :patch_note, with: ->(value) { value.strip.presence }

  scope :waiting, -> { where(patch_id: nil, dismissed_at: nil) }
  scope :covered, -> { where.not(patch_id: nil) }
  scope :dismissed, -> { where.not(dismissed_at: nil) }

  def status
    return COVERED if patch_id
    return DISMISSED if dismissed_at

    OPEN
  end

  def section = SECTIONS.fetch(change_type, "improved")

  def patch_number = patch&.number

  # Each repo's current version: the highest version among its Pending
  # Changes, compared number by number (so 1.10.0 beats 1.9.3 whatever order
  # they arrived in), nil until it has one.
  def self.versions
    latest = select("DISTINCT ON (repo) repo, version")
      .order(:repo, Arel.sql("string_to_array(version, '.')::numeric[] DESC"), id: :desc)
    REPOS.index_with(nil).merge(latest.to_h { |row| [ row.repo, row.version ] })
  end
end
