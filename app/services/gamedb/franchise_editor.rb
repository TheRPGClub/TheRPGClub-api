# frozen_string_literal: true

module Gamedb
  # Every hand change to a Franchise goes through here (spec api#442,
  # "Franchises (API)"): linking and unlinking games, setting Mainline and
  # creating Franchises. Permission checks stay with the caller; this only
  # applies a change for the member who made it.
  #
  #   editor = Gamedb::FranchiseEditor.new(user_id: "123")
  #   editor.link!(franchise, game, mainline: true)
  #   editor.unlink!(franchise, game)
  #   editor.create!(name: "Soulslike")
  #
  # Edits survive IGDB re-imports (IgdbGameImporter#sync_franchises!): a link
  # added here is `manual`, which a re-import never removes; an unlink is
  # remembered in `gamedb_franchise_unlinks`, which a re-import never links
  # again; and a re-import never touches `mainline`.
  #
  # Each change is one Change, applied in a transaction by #apply!, which is
  # the single place that records it (the history, api#444, hooks in there)
  # and invalidates the cached game relations it shows in.
  class FranchiseEditor
    # One change to a Franchise. `action` is one of ACTIONS; `game` is nil
    # for a change to the Franchise itself; `before`/`after` hold the changed
    # values (nil when the thing didn't exist before, or doesn't after).
    Change = Data.define(:action, :franchise, :game, :before, :after, :user_id)

    ACTIONS = %w[link unlink mainline_on mainline_off create].freeze

    def initialize(user_id:)
      @user_id = user_id
    end

    # Link `game` to `franchise` (as `manual`) if it isn't already, and set
    # Mainline when `mainline` is true or false (nil leaves it as it is).
    # Linking forgets a past unlink of the pair. An IGDB link keeps its
    # source. Returns the link.
    def link!(franchise, game, mainline: nil)
      GamedbGameFranchise.transaction do
        link = GamedbGameFranchise.lock.find_by(franchise_id: franchise.franchise_id, game_id: game.game_id)
        link ||= add_link!(franchise, game)
        set_mainline!(link, franchise, game, mainline) unless mainline.nil? || link.mainline == mainline
        link
      end
    end

    # Remove `game` from `franchise` and remember it, so a re-import doesn't
    # add it back. Nothing happens when the game isn't linked.
    def unlink!(franchise, game)
      GamedbGameFranchise.transaction do
        link = GamedbGameFranchise.lock.find_by(franchise_id: franchise.franchise_id, game_id: game.game_id)
        next if link.nil?

        apply!(:unlink, franchise, game, before: link_values(link), after: nil) do
          link.destroy!
          GamedbFranchiseUnlink.upsert(
            { game_id: game.game_id, franchise_id: franchise.franchise_id, unlinked_by: @user_id,
              unlinked_at: Time.current },
            unique_by: %i[game_id franchise_id]
          )
        end
      end
    end

    # A new Franchise with no IGDB id. Raises ActiveRecord::RecordInvalid
    # for a blank or too-long name.
    def create!(name:)
      GamedbFranchise.transaction do
        franchise = GamedbFranchise.new(name: name.to_s.squish, created_by: @user_id)
        franchise.validate!
        apply!(:create, franchise, nil, before: nil, after: { "name" => franchise.name }) { franchise.save! }
        franchise
      end
    end

    private

    def add_link!(franchise, game)
      link = GamedbGameFranchise.new(franchise_id: franchise.franchise_id, game_id: game.game_id,
        source: "manual", mainline: false, created_by: @user_id, created_at: Time.current)
      apply!(:link, franchise, game, before: nil, after: link_values(link)) do
        GamedbFranchiseUnlink.where(franchise_id: franchise.franchise_id, game_id: game.game_id).delete_all
        link.save!
      end
      link
    end

    def set_mainline!(link, franchise, game, mainline)
      action = mainline ? :mainline_on : :mainline_off
      apply!(action, franchise, game, before: { "mainline" => link.mainline },
        after: { "mainline" => mainline }) do
        link.update!(mainline: mainline)
      end
    end

    def link_values(link) = { "source" => link.source, "mainline" => link.mainline }

    # The one path every change takes: apply it, record it, and invalidate
    # what shows it. Runs inside the caller's transaction.
    def apply!(action, franchise, game, before:, after:)
      yield
      record!(Change.new(action: action.to_s, franchise: franchise, game: game, before: before, after: after,
        user_id: @user_id))
      # A game's relations (GamesController#relations_data) are cached on
      # its updated_at and list its Franchises.
      game&.touch
    end

    # Where the Franchise history (api#444) records `change`.
    def record!(change); end
  end
end
