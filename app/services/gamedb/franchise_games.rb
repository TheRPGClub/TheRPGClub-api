# frozen_string_literal: true

module Gamedb
  # A Franchise's games as its page shows them (spec api#442): `mainline`,
  # `other`, and `add_ons`. An Add-on (GLOSSARY.md) is a game with a parent
  # game (`parent_igdb_id`), and it goes in `add_ons` whatever its Mainline
  # mark. Add-ons are grouped under their parent when the parent is in
  # GameDB, whether or not the parent is in this Franchise; the rest share a
  # last group with a null `parent`.
  #
  # Each game: `{ game_id, title, cover_url, release_year, mainline, source,
  # parent_game_name }`, oldest release first (undated last), then by title.
  module FranchiseGames
    GAME_COLUMNS = %i[game_id igdb_id title initial_release_date parent_igdb_id parent_game_name].freeze

    def self.of(franchise)
      links = GamedbGameFranchise.where(franchise_id: franchise.franchise_id).index_by(&:game_id)
      games = sorted(GamedbGame.where(game_id: links.keys).select(*GAME_COLUMNS).preload(:images))
      add_ons, full = games.partition { |game| game.parent_igdb_id.present? }
      mainline, other = full.partition { |game| links.fetch(game.game_id).mainline }

      {
        mainline: mainline.map { |game| entry(game, links.fetch(game.game_id)) },
        other: other.map { |game| entry(game, links.fetch(game.game_id)) },
        add_ons: add_on_groups(add_ons, links)
      }
    end

    def self.add_on_groups(add_ons, links)
      parents = GamedbGame.where(igdb_id: add_ons.map(&:parent_igdb_id).uniq)
        .select(*GAME_COLUMNS).preload(:images).index_by(&:igdb_id)
      grouped = add_ons.group_by { |game| parents[game.parent_igdb_id] }
      orphans = grouped.delete(nil)

      groups = sorted(grouped.keys).map do |parent|
        { parent: game_fields(parent).merge(in_franchise: links.key?(parent.game_id)),
          games: grouped.fetch(parent).map { |game| entry(game, links.fetch(game.game_id)) } }
      end
      groups << { parent: nil, games: orphans.map { |game| entry(game, links.fetch(game.game_id)) } } if orphans
      groups
    end

    def self.entry(game, link)
      game_fields(game).merge(mainline: link.mainline, source: link.source, parent_game_name: game.parent_game_name)
    end

    def self.game_fields(game)
      { game_id: game.game_id, title: game.title, cover_url: game.cover_url,
        release_year: game.initial_release_date&.year }
    end

    def self.sorted(games)
      games.sort_by { |game| [ game.initial_release_date ? 0 : 1, game.initial_release_date.to_i, game.title.to_s, game.game_id ] }
    end

    private_class_method :add_on_groups, :entry, :game_fields, :sorted
  end
end
