# frozen_string_literal: true

module Gamedb
  # Creates (or idempotently refreshes) a GamedbGame from an IGDB id: fetches
  # the full IGDB payload, upserts the game row + its taxonomy + releases, then
  # imports the cover/artwork/logo images through Gamedb::IgdbImageImporter so
  # the Backblaze artifacts match the batch jobs exactly (issue #122).
  #
  # Mirrors the Discord bot's "add a game from IGDB" flow so an API-created game
  # is indistinguishable from a bot-created one: missing lookup rows (genre,
  # company, platform, …) are created on the fly keyed by their `igdb_*_id`, and
  # releases are one-per-platform (earliest), skip Japan, and leave `format`
  # null (IGDB carries no physical/digital signal).
  class IgdbGameImporter
    class MissingIgdbGameError < StandardError; end
    class MissingIgdbIdError < StandardError; end

    Result = Struct.new(:game, :created, :images, keyword_init: true) do
      def as_json(*)
        {
          created: created,
          game_id: game.game_id,
          igdb_id: game.igdb_id,
          images: images.as_json
        }
      end
    end

    # IGDB `release_dates.region` enum -> local region code/name (the bot's
    # IGDB_REGION_MAP). A release whose region isn't listed is dropped.
    REGION_MAP = {
      1 => { code: "EU", name: "Europe" },
      2 => { code: "NA", name: "North America" },
      3 => { code: "AUS", name: "Australia" },
      4 => { code: "NZ", name: "New Zealand" },
      5 => { code: "JP", name: "Japan" },
      6 => { code: "CN", name: "China" },
      7 => { code: "AS", name: "Asia" },
      8 => { code: "WW", name: "Worldwide" }
    }.freeze

    # Region the bot excludes from auto-created releases (JP), and the fallback
    # region applied when a release date carries none (WW).
    SKIPPED_RELEASE_REGION = 5
    DEFAULT_RELEASE_REGION = 8

    def initialize(client: Igdb::Client.new, image_importer: IgdbImageImporter.new)
      @client = client
      @image_importer = image_importer
    end

    def import!(igdb_id)
      payload = @client.game(igdb_id)
      raise MissingIgdbGameError, "IGDB game #{igdb_id} was not found" if payload.blank?

      game, created = upsert_game!(payload)

      # Image import does external HTTP (IGDB download + Backblaze upload), so it
      # runs after the metadata transaction commits — never inside it. The
      # importer re-fetches via Igdb::Client#game_images so the cover/artwork/
      # logo formats and object keys stay identical to the jobs (image parity).
      images = @image_importer.import!(game)

      Result.new(game: game, created: created, images: images)
    end

    # Re-fetch the game's release dates from IGDB and rebuild its release rows
    # (the bot's `refreshReleaseDates`): drop the existing releases plus their
    # scheduled announcements, then re-run the same one-per-platform sync #import!
    # uses. Touches releases only — never images or the game's metadata/taxonomy.
    # Returns the (unchanged) GamedbGame so the caller can re-render its releases.
    def refresh_releases!(game_id)
      game = GamedbGame.find(game_id)
      raise MissingIgdbIdError, "Game #{game_id} has no IGDB id" if game.igdb_id.blank?

      payload = @client.game(game.igdb_id)
      raise MissingIgdbGameError, "IGDB game #{game.igdb_id} was not found" if payload.blank?

      GamedbGame.transaction do
        clear_releases!(game)
        # Drop any cached releases so sync_releases!'s `seen_platform_ids` lookup
        # reads the now-empty set rather than the pre-clear association cache.
        game.releases.reset
        sync_releases!(game, payload)
        # Bump updated_at so GamesController#relations_data's cache key (keyed
        # on it) changes -- releases live on a child table, so saving the game
        # itself wouldn't otherwise happen here.
        game.touch
      end

      game
    end

    private

    # Delete the game's releases and the announcements that hang off them
    # (announcements first — they FK to release_id). Mirrors the bot's
    # `clearReleaseDates`, which wipes both before re-inserting.
    def clear_releases!(game)
      release_ids = game.releases.pluck(:release_id)
      return if release_ids.empty?

      GamedbReleaseAnnouncement.where(release_id: release_ids).delete_all
      GamedbRelease.where(release_id: release_ids).delete_all
    end

    def upsert_game!(payload)
      GamedbGame.transaction do
        collection = resolve_collection(payload[:collection])
        game = GamedbGame.find_or_initialize_by(igdb_id: payload[:igdb_id])
        created = game.new_record?
        game.assign_attributes(game_attributes(payload, collection))
        game.save!

        sync_taxonomy!(game, payload)
        sync_releases!(game, payload)

        [ game, created ]
      end
    end

    def game_attributes(payload, collection)
      {
        title: payload[:name],
        slug: payload[:slug],
        description: payload[:summary],
        igdb_url: payload[:url],
        total_rating: payload[:total_rating],
        initial_release_date: payload[:first_release_date],
        parent_igdb_id: payload[:parent_igdb_id],
        parent_game_name: payload[:parent_game_name],
        collection_id: collection&.collection_id
      }
    end

    def sync_taxonomy!(game, payload)
      sync_simple!(game, GamedbGenre, :igdb_genre_id, GamedbGameGenre, :genre_id, payload[:genres])
      sync_simple!(game, GamedbTheme, :igdb_theme_id, GamedbGameTheme, :theme_id, payload[:themes])
      sync_simple!(game, GamedbPerspective, :igdb_perspective_id, GamedbGamePerspective, :perspective_id, payload[:perspectives])
      sync_simple!(game, GamedbGameModeDef, :igdb_game_mode_id, GamedbGameMode, :mode_id, payload[:game_modes])
      sync_simple!(game, GamedbEngine, :igdb_engine_id, GamedbGameEngine, :engine_id, payload[:engines])
      sync_simple!(game, GamedbFranchise, :igdb_franchise_id, GamedbGameFranchise, :franchise_id, payload[:franchises])
      sync_platforms!(game, payload[:platforms])
      sync_companies!(game, payload[:companies])
    end

    # Resolve each ref to a lookup row (creating a missing one keyed by its IGDB
    # id) and ensure the join row exists. Insert-only and idempotent: re-running
    # never duplicates and never prunes existing links.
    def sync_simple!(game, lookup_model, igdb_column, join_model, join_fk, refs)
      Array(refs).each do |ref|
        lookup = find_or_create_lookup(lookup_model, igdb_column, ref)
        join_model.find_or_create_by!(:game_id => game.game_id, join_fk => lookup.id)
      end
    end

    def find_or_create_lookup(model, igdb_column, ref)
      model.create_with(name: ref[:name]).find_or_create_by!(igdb_column => ref[:igdb_id])
    end

    def resolve_collection(ref)
      return if ref.blank?

      find_or_create_lookup(GamedbCollection, :igdb_collection_id, ref)
    end

    def sync_platforms!(game, refs)
      Array(refs).each do |ref|
        platform = ensure_platform(ref)
        next if platform.nil?

        GamedbGamePlatform.find_or_create_by!(game_id: game.game_id, platform_id: platform.platform_id)
      end
    end

    # One company can be both developer and publisher (two join rows); a company
    # that is neither is skipped (the join's `role` is NOT NULL / Developer|Publisher).
    def sync_companies!(game, companies)
      Array(companies).each do |company|
        roles = []
        roles << "Developer" if company[:developer]
        roles << "Publisher" if company[:publisher]
        next if roles.empty?

        record = find_or_create_lookup(GamedbCompany, :igdb_company_id, company)
        roles.each do |role|
          GamedbGameCompany.find_or_create_by!(game_id: game.game_id, company_id: record.company_id, role: role)
        end
      end
    end

    def sync_releases!(game, payload)
      seen_platform_ids = game.releases.pluck(:platform_id).to_set

      earliest_release_per_platform(payload[:release_dates]).each_value do |release|
        platform = ensure_platform(release[:platform])
        next if platform.nil? || seen_platform_ids.include?(platform.platform_id)

        region = ensure_region(release[:region])
        next if region.nil?

        GamedbRelease.create!(
          game_id: game.game_id,
          platform_id: platform.platform_id,
          region_id: region.region_id,
          format: nil,
          release_date: release[:date]
        )
        seen_platform_ids << platform.platform_id
      end
    end

    # IGDB returns many release_dates per game (one per region/platform). Keep
    # the earliest dated row per platform, skipping Japan and undated rows —
    # mirroring the bot so the same single release lands per platform.
    def earliest_release_per_platform(release_dates)
      Array(release_dates).each_with_object({}) do |release, earliest|
        next if release[:region] == SKIPPED_RELEASE_REGION

        igdb_platform_id = release.dig(:platform, :igdb_id)
        next if igdb_platform_id.blank? || release[:date].nil?

        current = earliest[igdb_platform_id]
        earliest[igdb_platform_id] = release if current.nil? || release[:date] < current[:date]
      end
    end

    def ensure_platform(ref)
      GamedbPlatform.create_with(
        platform_name: ref[:name].presence || "IGDB Platform #{ref[:igdb_id]}",
        platform_code: platform_code_for(ref[:name], ref[:igdb_id])
      ).find_or_create_by!(igdb_platform_id: ref[:igdb_id])
    end

    # Synthesize a unique platform_code (NOT NULL, <=20 chars) for a platform
    # IGDB knows but we don't: alphanumerics of the name + the IGDB id, mirroring
    # the bot's buildPlatformCode.
    def platform_code_for(name, igdb_id)
      base = name.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
      base = base[0, 12].presence || "PLATFORM"
      "#{base}#{igdb_id}"[0, 20]
    end

    def ensure_region(igdb_region_id)
      region_id = igdb_region_id || DEFAULT_RELEASE_REGION
      config = REGION_MAP[region_id]
      return if config.nil?

      GamedbRegion
        .create_with(region_code: config[:code], region_name: config[:name])
        .find_or_create_by!(igdb_region_id: region_id)
    end
  end
end
