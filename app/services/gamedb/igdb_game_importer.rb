# frozen_string_literal: true

module Gamedb
  # Creates (or idempotently refreshes) a GamedbGame from an IGDB id: fetches
  # the full IGDB payload, upserts the game row + its taxonomy + releases, then
  # imports the cover/artwork/logo images through Gamedb::IgdbImageImporter so
  # the Backblaze artifacts match the batch jobs exactly (issue #122).
  #
  # Mirrors the Discord bot's "add a game from IGDB" flow so an API-created game
  # is indistinguishable from a bot-created one: missing lookup rows (genre,
  # company, platform, …) are created on the fly keyed by their `igdb_*_id`.
  # Releases are one per platform per region (the earliest, Japan included,
  # ADR 0010), carry IGDB's Date Precision (a TBA Release when IGDB has no
  # date yet, api#392) and leave `format` null (IGDB carries no physical/digital
  # signal); they are written through Gamedb::ReleaseSync, the in-place
  # refresh shared by import and refresh.
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

    # IGDB `release_dates.release_region` id -> local region code/name (the bot's
    # IGDB_REGION_MAP). A release whose region isn't listed is dropped.
    REGION_MAP = {
      1 => { code: "EU", name: "Europe" },
      2 => { code: "NA", name: "North America" },
      3 => { code: "AUS", name: "Australia" },
      4 => { code: "NZ", name: "New Zealand" },
      5 => { code: "JP", name: "Japan" },
      6 => { code: "CN", name: "China" },
      7 => { code: "AS", name: "Asia" },
      8 => { code: "WW", name: "Worldwide" },
      9 => { code: "KR", name: "Korea" },
      10 => { code: "BR", name: "Brazil" }
    }.freeze

    # The fallback region applied when a release date carries none (WW).
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

    # Re-fetch the game's release dates from IGDB and refresh its Releases in
    # place (ADR 0010) through the same sync #import! uses: IGDB Releases are
    # updated, added or removed, Manual Releases are adopted or left alone, and
    # announcements keep their delivery state. Touches Releases only, never
    # images or the game's metadata/taxonomy. Returns the GamedbGame so the
    # caller can re-render its releases.
    def refresh_releases!(game_id)
      game = GamedbGame.find(game_id)
      raise MissingIgdbIdError, "Game #{game_id} has no IGDB id" if game.igdb_id.blank?

      payload = @client.game(game.igdb_id)
      raise MissingIgdbGameError, "IGDB game #{game.igdb_id} was not found" if payload.blank?

      GamedbGame.transaction do
        sync_releases!(game, payload)
        # Bump updated_at so GamesController#relations_data's cache key (keyed
        # on it) changes -- releases live on a child table, so saving the game
        # itself wouldn't otherwise happen here.
        game.touch
      end

      game
    end

    private

    def upsert_game!(payload)
      result = GamedbGame.transaction do
        collection = resolve_collection(payload[:collection])
        game = GamedbGame.find_or_initialize_by(igdb_id: payload[:igdb_id])
        created = game.new_record?
        game.assign_attributes(game_attributes(payload, collection))
        game.save!

        sync_taxonomy!(game, payload)
        sync_releases!(game, payload)
        # sync_taxonomy!/sync_releases! can insert child rows (a platform,
        # taxonomy join, company role, release) even when the game's own
        # columns above are unchanged, in which case `save!` above wouldn't
        # have advanced updated_at. Touch unconditionally so
        # GamesController#relations_data's cache (keyed on it) always
        # invalidates after a re-import.
        game.touch

        [ game, created ]
      end

      # title/description/slug/... are GameResource fields embedded in other
      # games' cached `alternates` slice without touching this game's own row
      # from their perspective -- bump the shared version (after the
      # transaction commits) so those caches invalidate too.
      Gamedb::GameRelationsCacheVersion.bump!

      result
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
      sync_franchises!(game, payload[:franchises])
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

    # Franchises as #sync_simple! does, but around hand edits (spec api#442,
    # Gamedb::FranchiseEditor): a pair a person unlinked is never linked
    # again, and an existing link keeps its `source` and `mainline`. Like
    # every taxonomy sync it only adds links, so a `manual` link stays. A
    # merged Franchise's id resolves to its target and a deleted one is
    # skipped (GamedbFranchise.for_igdb_ref); an existing Franchise keeps its
    # name, so a rename (`name_locked`) stays.
    def sync_franchises!(game, refs)
      unlinked = GamedbFranchiseUnlink.where(game_id: game.game_id).pluck(:franchise_id).to_set
      Array(refs).each do |ref|
        franchise = GamedbFranchise.for_igdb_ref(ref)
        next if franchise.nil? || unlinked.include?(franchise.franchise_id)

        GamedbGameFranchise.create_with(source: "igdb")
          .find_or_create_by!(game_id: game.game_id, franchise_id: franchise.franchise_id)
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
      reported = earliest_release_per_platform_and_region(payload[:release_dates]).each_value.filter_map do |release|
        platform = ensure_platform(release[:platform])
        region = ensure_region(release[:region])
        next if platform.nil? || region.nil?

        ReleaseSync::Reported.new(
          platform_id: platform.platform_id, region_id: region.region_id,
          release_date: release[:date], date_precision: release[:date_precision]
        )
      end

      ReleaseSync.call(game, reported)
    end

    # IGDB can return several release_dates for one platform and region (a
    # re-release, an edition, a TBA placeholder). Keep the earliest per platform
    # per region, Japan included (ADR 0010): any dated row, exact or vague,
    # beats TBA, and on the same date the more precise row wins. A vague row is
    # passed over when a more precise row falls inside its period, so IGDB's
    # "Q3 2027" never hides the 2027-08-14 it also knows (a "Q2 2027" still
    # beats that later day). A platform and region with only TBA rows keeps one
    # TBA Release. A missing region counts as Worldwide, as ensure_region
    # stores it.
    def earliest_release_per_platform_and_region(release_dates)
      Array(release_dates)
        .select { |release| release.dig(:platform, :igdb_id).present? }
        .group_by { |release| [ release.dig(:platform, :igdb_id), release[:region] || DEFAULT_RELEASE_REGION ] }
        .transform_values do |releases|
          releases.reject { |vague| releases.any? { |sharper| sharpens?(sharper, vague) } }.min_by { |release| release_order(release) }
        end
    end

    # Whether `sharper` dates the same release more precisely than `vague`:
    # it is more precise and its date falls inside `vague`'s period.
    def sharpens?(sharper, vague)
      return false if sharper[:date].nil? || vague[:date].nil?
      return false unless precision_rank(sharper) < precision_rank(vague)

      GamedbRelease.period(vague[:date], vague[:date_precision]).cover?(sharper[:date])
    end

    # Sort key for "earliest": TBA (no date) last, then date, then precision.
    def release_order(release)
      [ release[:date] ? 0 : 1, release[:date] || Date.new(0), precision_rank(release) ]
    end

    def precision_rank(release)
      GamedbRelease.precision_rank(release[:date_precision]) || 0
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
