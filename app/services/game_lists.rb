# frozen_string_literal: true

# Game Lists (GLOSSARY.md, "Game List"; spec api#442, ticket api#446). The
# API owns every rule: who may read and change a list (GameLists::Actor),
# deleting one and changing its visibility (GameLists::Lifecycle), its
# entries (GameLists::Entries), and how its games are ordered
# (GameLists.entry_order). Gated by the `game_lists` Feature.
module GameLists
  # A request the rules refuse: rendered with `status` as
  # `{ error: code, message:, **details }`.
  class Refused < StandardError
    attr_reader :code, :status, :details

    def initialize(code, message, status: :unprocessable_content, **details)
      @code = code
      @status = status
      @details = details
      super(message)
    end
  end

  # The SQL order of a list's entries (joined to gamedb_games) for `sort`:
  # ranked by position, alphabetical by title, or added newest first. Ties
  # fall back to the ranked order.
  def self.entry_order(sort)
    case sort
    when GameList::ALPHABETICAL then Arel.sql("lower(gamedb_games.title) ASC, game_list_entries.position ASC")
    when GameList::ADDED then Arel.sql("game_list_entries.added_at DESC, game_list_entries.position DESC")
    else Arel.sql("game_list_entries.position ASC")
    end
  end

  # A member as Game List JSON serves them (Members.summary).
  def self.member(user) = user && Members.summary(user)

  # The refusal messages members see, as the bot and the website show them.
  module Refusals
    CLUB = "Only Moderators and above can create a club Game List."
    EDIT = "Only its owner can edit this Game List; a Members-visible or club one, any Moderator or above."
    DELETE = "Only its owner or a Moderator can delete this Game List; a club one, an Admin."
    VISIBILITY = "Only its owner can change who sees this Game List."
  end
end
