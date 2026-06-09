# frozen_string_literal: true

module Gamedb
  class IgdbImageImporter
    class MissingIgdbIdError < StandardError; end
    class MissingIgdbGameError < StandardError; end

    Result = Struct.new(
      :game_id,
      :igdb_id,
      :title,
      :igdb_title,
      :images,
      keyword_init: true
    ) do
      def as_json(*)
        {
          game_id: game_id,
          igdb_id: igdb_id,
          title: title,
          igdb_title: igdb_title,
          images: GameImageResource.new(images).serializable_hash
        }
      end
    end

    def initialize(client: Igdb::Client.new, storage: GameImageStorage.new)
      @client = client
      @storage = storage
    end

    def import!(game_or_id)
      game = resolve_game(game_or_id)
      raise MissingIgdbIdError, "Game #{game.game_id} has no IGDB ID" if game.igdb_id.blank?

      igdb_images = @client.game_images(game.igdb_id)
      raise MissingIgdbGameError, "IGDB game #{game.igdb_id} was not found" if igdb_images.blank?

      imported = []
      imported << import_cover(game, igdb_images[:cover_image_id]) if igdb_images[:cover_image_id].present?
      imported.concat(import_artworks(game, igdb_images[:artworks]))
      imported.compact!
      prune_stale_imported_images!(game, imported)

      Result.new(
        game_id: game.game_id,
        igdb_id: game.igdb_id,
        title: game.title,
        igdb_title: igdb_images[:title],
        images: imported.compact
      )
    end

    private

    def import_cover(game, image_id)
      @storage.import_igdb!(
        game: game,
        kind: "cover",
        image_url: Igdb::Client.image_url(image_id, size: "cover_big"),
        position: 1,
        primary: true
      )
    end

    def import_artworks(game, artworks)
      logo_artworks, regular_artworks = Array(artworks).partition { |artwork| logo_artwork?(artwork) }

      import_artwork_kind(game, "artwork", regular_artworks) +
        import_artwork_kind(game, "logo", logo_artworks)
    end

    def import_artwork_kind(game, kind, artworks)
      Array(artworks).each_with_index.map do |artwork, index|
        @storage.import_igdb!(
          game: game,
          kind: kind,
          image_url: Igdb::Client.image_url(
            artwork.fetch(:image_id),
            size: "1080p",
            extension: artwork[:alpha_channel] ? "png" : "jpg"
          ),
          position: index + 1,
          primary: index.zero?
        )
      end
    end

    def logo_artwork?(artwork)
      artwork[:artwork_type_slug].to_s.start_with?("game-logo")
    end

    def prune_stale_imported_images!(game, imported)
      ids_by_kind = imported.group_by(&:kind).transform_values { |images| images.map(&:image_id) }
      GamedbGameImage::KINDS.each do |kind|
        stale_scope = game.images.where(kind: kind, uploaded_by_user_id: nil)
        image_ids = ids_by_kind.fetch(kind, [])
        stale_scope = stale_scope.where.not(image_id: image_ids) if image_ids.any?

        stale_scope.find_each { |image| @storage.delete!(image) }
      end
    end

    def resolve_game(game_or_id)
      return game_or_id if game_or_id.is_a?(GamedbGame)

      GamedbGame.find(game_or_id)
    end
  end
end
