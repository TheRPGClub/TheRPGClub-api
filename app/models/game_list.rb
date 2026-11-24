# frozen_string_literal: true

# A Game List (GLOSSARY.md, "Game List"; spec api#442, ticket api#446): a
# named list of GameDB games a member keeps around any theme, or the club
# owns (`owner_user_id` null). Who may read and change one is
# GameLists::Actor's decision; deleting one and changing its visibility go
# through GameLists::Lifecycle, its entries through GameLists::Entries.
class GameList < ApplicationRecord
  MEMBERS = "members"
  PRIVATE = "private"
  VISIBILITIES = [ MEMBERS, PRIVATE ].freeze

  RANKED = "ranked"
  ALPHABETICAL = "alphabetical"
  ADDED = "added"
  SORTS = [ RANKED, ALPHABETICAL, ADDED ].freeze

  NAME_MAX = 100
  DESCRIPTION_MAX = 500
  ENTRIES_MAX = 500

  # How lists are listed: club lists first, then the most recently changed.
  INDEX_ORDER = Arel.sql("(game_lists.owner_user_id IS NULL) DESC, game_lists.updated_at DESC, game_lists.id DESC")

  belongs_to :owner, -> { without_images }, class_name: "RpgClubUser", foreign_key: :owner_user_id,
    primary_key: :user_id, optional: true, inverse_of: false
  belongs_to :taken_over_from, -> { without_images }, class_name: "RpgClubUser",
    foreign_key: :taken_over_from_user_id, primary_key: :user_id, optional: true, inverse_of: false
  # Rows go with the list (the foreign key cascades).
  has_many :entries, class_name: "GameListEntry", dependent: nil, inverse_of: :game_list

  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :description, length: { maximum: DESCRIPTION_MAX }
  validates :visibility, inclusion: { in: VISIBILITIES, message: "must be one of #{VISIBILITIES.join(', ')}" }
  validates :sort, inclusion: { in: SORTS, message: "must be one of #{SORTS.join(', ')}" }
  validate :club_lists_members_visible

  normalizes :name, with: ->(value) { value.strip }
  normalizes :description, with: ->(value) { value.strip.presence }

  # Members-visible lists, readable by any member.
  scope :members_visible, -> { where(visibility: MEMBERS) }

  def club? = owner_user_id.nil?
  def private? = visibility == PRIVATE

  def owned_by?(user_id) = user_id.present? && owner_user_id == user_id

  private

  # Private lists are owner-only, and the club is nobody's account.
  def club_lists_members_visible
    errors.add(:visibility, "of a club list must be members") if club? && private?
  end
end
