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
  PARTS = %w[history_event lore_entry fun_fact].freeze
  # History Event Kinds.
  KINDS = %w[founding staff platform rules milestone].freeze
  DATE_PRECISIONS = %w[day month year].freeze
  TITLE_MAX = 100
  # A Fun Fact's length, mention tokens included, so it reads well as a chat post.
  FUN_FACT_MAX = 300

  belongs_to :author, -> { without_images }, class_name: "RpgClubUser", foreign_key: :author_user_id,
    primary_key: :user_id, inverse_of: false
  has_many :mentions, class_name: "CodexEntryMention", foreign_key: :entry_id, dependent: nil, inverse_of: :entry

  validates :part, inclusion: { in: PARTS, message: "must be one of #{PARTS.join(', ')}" }
  validates :body, presence: true, length: { maximum: FUN_FACT_MAX }, if: :fun_fact?

  normalizes :body, with: ->(value) { value.strip }

  after_save :pull_mentions, if: :saved_change_to_body?

  scope :fun_facts, -> { where(part: "fun_fact") }

  def fun_fact? = part == "fun_fact"

  private

  def pull_mentions = ClubCodex::Mentions.pull!(self)
end
