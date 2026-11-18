# frozen_string_literal: true

# A Club Codex entry (GLOSSARY.md, "Club Codex"; spec #397): a History Event,
# a Lore Entry or a Fun Fact, told apart by `part`. One table holds all three
# so mentions, "See also" links and images hang off one entry id; the rules
# that apply to only some parts are checked here (and held by the table's
# checks, see the CreateCodexEntries migration).
#
# `body` is the Discord-readable text, with members mentioned as
# `<@discord_id>` tokens. Every save pulls those tokens into `mentions`
# (ClubCodex::Mentions), whatever the part.
class CodexEntry < ApplicationRecord
  HISTORY_EVENT = "history_event"
  LORE_ENTRY = "lore_entry"
  FUN_FACT = "fun_fact"
  PARTS = [ HISTORY_EVENT, LORE_ENTRY, FUN_FACT ].freeze
  # Each part as members read it, for messages.
  PART_NAMES = { HISTORY_EVENT => "History Event", LORE_ENTRY => "Lore Entry", FUN_FACT => "Fun Fact" }.freeze
  # History Event Kinds.
  KINDS = %w[founding staff platform rules milestone].freeze
  DATE_PRECISIONS = %w[day month year].freeze
  TITLE_MAX = 100
  # A Fun Fact's length, mention tokens included, so it reads well as a chat post.
  FUN_FACT_MAX = 300

  include Dated

  belongs_to :author, -> { without_images }, class_name: "RpgClubUser", foreign_key: :author_user_id,
    primary_key: :user_id, inverse_of: false
  has_many :mentions, class_name: "CodexEntryMention", foreign_key: :entry_id, dependent: nil, inverse_of: :entry
  # The gallery, by position. Rows go with the entry; ClubCodex::Images
  # removes their files from storage first.
  has_many :images, -> { order(:position) }, class_name: "CodexEntryImage", foreign_key: :entry_id, dependent: nil,
    inverse_of: :entry

  validates :part, inclusion: { in: PARTS, message: "must be one of #{PARTS.join(', ')}" }
  validates :body, presence: true, length: { maximum: FUN_FACT_MAX }, if: :fun_fact?
  # A Lore Entry's story, and any entry's `rich_body`, needs its Discord text.
  validates :body, presence: true, if: -> { lore_entry? || !rich_body.nil? }
  validates :title, presence: true, length: { maximum: TITLE_MAX }, unless: :fun_fact?
  # History Events: dated, with a History Event Kind.
  validates :kind, inclusion: { in: KINDS, message: "must be one of #{KINDS.join(', ')}" }, if: :history_event?
  validates :kind, absence: true, unless: :history_event?
  validates :occurred_on, presence: true, if: -> { history_event? && !unreadable_occurred_on? }
  validates :date_precision, presence: true, if: :history_event?

  normalizes :body, :title, with: ->(value) { value.strip }

  after_save :pull_mentions, if: :saved_change_to_body?

  scope :fun_facts, -> { where(part: FUN_FACT) }

  def fun_fact? = part == FUN_FACT
  def history_event? = part == HISTORY_EVENT
  def lore_entry? = part == LORE_ENTRY

  private

  def pull_mentions = ClubCodex::Mentions.pull!(self)
end
