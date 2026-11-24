# frozen_string_literal: true

# Reusable OpenAPI component schemas for the rswag-generated `swagger.yaml`.
#
# WHY THIS FILE EXISTS (#78): the request specs used to document every response
# body as `{ type: :object, additionalProperties: true }` and every write body
# as a free-text `additionalProperties: true` blob. Those blobs drifted from the
# real models/serializers and a consumer (the Discord bot) copied a wrong field
# name verbatim, causing a production 500. Each schema here is cross-checked
# against three sources of truth and referenced from the specs via `$ref`:
#
#   1. DB columns       — db/schema.rb (column presence + null-ness)
#   2. Model            — app/models/** (validations, FK aliases, associations)
#   3. Serializer       — app/serializers/** (the actual response shape)
#
# Response shapes live here (one component per Alba resource, reused by every
# endpoint that returns it and composed for embeds). Write-body shapes stay
# inline in each spec — they are small, per-endpoint, and document only the
# writable subset (controller-injected and bot-managed columns are excluded
# there). Regenerate with `rake rswag:specs:swaggerize` after any change.
#
# `obj` auto-derives `required` as the always-present, non-null scalar columns
# (nullable columns, embedded `$ref`s and arrays are omitted, since an embed may
# be conditional or null). That keeps the documented "always present" set
# tracking the column null-ness without hand-maintaining a parallel list.
module OpenapiSchemas
  # The model's custom-facet-key regexp as an anchored ECMA pattern, which is
  # what JSON Schema's `pattern` speaks (`\A`/`\z` are Ruby-only, and an
  # unanchored pattern would match `custom:1` inside any longer string).
  CUSTOM_FACET_PATTERN = UserGameReview::CUSTOM_FACET_KEY.source.sub('\A', "^").sub('\z', "$")

  module_function

  def str(nullable: false, **opts) = { type: :string }.merge(nullable ? { nullable: true } : {}).merge(opts)
  def int(nullable: false) = { type: :integer }.merge(nullable ? { nullable: true } : {})
  def num(nullable: false) = { type: :number }.merge(nullable ? { nullable: true } : {})
  def bool(nullable: false) = { type: :boolean }.merge(nullable ? { nullable: true } : {})
  def ts(nullable: false) = { type: :string, format: "date-time" }.merge(nullable ? { nullable: true } : {})
  def date(nullable: false, **opts) = { type: :string, format: "date" }.merge(nullable ? { nullable: true } : {}).merge(opts)
  def json(nullable: true) = { type: :object, description: "Free-form JSON." }.merge(nullable ? { nullable: true } : {})
  def ref(name, nullable: false) = nullable ? { allOf: [ { "$ref" => "#/components/schemas/#{name}" } ], nullable: true } : { "$ref" => "#/components/schemas/#{name}" }
  def array_of(name) = { type: :array, items: { "$ref" => "#/components/schemas/#{name}" } }

  # Build an object schema from keyword properties, auto-deriving `required` as
  # the always-present, non-null scalar columns (nullable columns, embedded
  # `$ref`s and arrays are excluded). The `_required` / `_description` sentinel
  # keys override the auto list / set a schema description without colliding
  # with a real column named `required`/`description`.
  def obj(**props)
    required = props.delete(:_required)
    description = props.delete(:_description)
    req =
      if required
        Array(required).map(&:to_s)
      else
        props.reject { |_k, v| v[:nullable] || v.key?("$ref") || v[:allOf] || v[:type] == :array }.keys.map(&:to_s)
      end
    schema = { type: :object, properties: props }
    schema[:required] = req unless req.empty?
    schema[:description] = description if description
    schema
  end

  # Compose a base component with extra keyword properties (OpenAPI allOf).
  def extends(base, required: nil, **props)
    schema = obj(**props, **(required ? { _required: required } : {}))
    { allOf: [ { "$ref" => "#/components/schemas/#{base}" }, schema ] }
  end

  # The complete component set, merged into config.openapi_specs by
  # spec/swagger_helper.rb.
  def definitions
    {
      # ---- shared utility shapes -------------------------------------------
      Error: obj(
        error: str(example: "not_found"), message: str(example: "Couldn't find Record with id=42"),
        _required: %w[error]
      ),
      PaginationMeta: obj(
        page: { type: :integer, example: 1 },
        pages: { type: :integer, example: 5 },
        count: { type: :integer, example: 123 },
        per: { type: :integer, example: 50 },
        prev: { type: :integer, example: nil, nullable: true },
        next: { type: :integer, example: 2, nullable: true },
        _required: %w[page pages count per],
        _description: "Page-native pagination metadata (from pagy)."
      ),
      DeletedResponse: obj(deleted: { type: :boolean, example: true }, _required: %w[deleted]),
      # `delete_all`-style bulk deletes also return how many rows were removed.
      DeletedCountResponse: obj(
        deleted: { type: :boolean, example: true }, count: { type: :integer, example: 3 },
        _required: %w[deleted count]
      ),

      # ---- taxonomy / lookup master tables (read-only) ---------------------
      Company: obj(company_id: int, name: str, igdb_company_id: int(nullable: true)),
      Franchise: obj(franchise_id: int, name: str, igdb_franchise_id: int(nullable: true),
        created_by: str(nullable: true).merge(description: "Who created it by hand; null for IGDB's."),
        name_locked: bool.merge(description: "An Admin renamed it, so IGDB re-imports keep the name."),
        merged_into_id: int(nullable: true).merge(description: "The Franchise it was merged into. A merged " \
                                                                "Franchise is off the list and refuses changes.")),
      # A game's Franchise as the game's relations list it (spec api#442).
      GameFranchise: extends("Franchise",
        mainline: bool.merge(description: "Whether the game is Mainline in this Franchise.")),
      FranchiseGame: obj(
        _description: "A game on a Franchise's page.",
        game_id: int, title: str, cover_url: str(nullable: true), release_year: int(nullable: true),
        mainline: bool, source: str(enum: %w[igdb manual]).merge(description: "Where the link came from."),
        parent_game_name: str(nullable: true).merge(description: "An Add-on's parent game, as IGDB names it.")
      ),
      FranchiseAddOnGroup: obj(
        _description: "Add-ons under their parent game. The last group has a null parent and holds the " \
                      "Add-ons whose parent isn't in GameDB.",
        parent: {
          allOf: [ obj(game_id: int, title: str, cover_url: str(nullable: true), release_year: int(nullable: true),
            in_franchise: bool.merge(description: "Whether the parent is in this Franchise too.")) ],
          nullable: true
        },
        games: array_of("FranchiseGame")
      ),
      FranchisePage: extends("Franchise", required: %w[games viewer],
        games: obj(
          _required: %w[mainline other add_ons],
          mainline: array_of("FranchiseGame"),
          other: array_of("FranchiseGame"),
          add_ons: array_of("FranchiseAddOnGroup").merge(description: "Games with a parent game, by parent.")
        ),
        viewer: obj(
          can_edit: bool.merge(description: "Regulars and above: link, unlink, Mainline, create."),
          can_admin: bool.merge(description: "Admins and above.")
        )),
      FranchiseLink: obj(
        franchise_id: int, game_id: int, source: str(enum: %w[igdb manual]), mainline: bool,
        created_at: ts(nullable: true).merge(description: "Null for links older than Franchise editing."),
        created_by: str(nullable: true)
      ),
      FranchiseChange: obj(
        _description: "A row of a Franchise's history (spec api#442).",
        _required: %w[change_id franchise_id action user_id created_at can_undo],
        change_id: int, franchise_id: int,
        game_id: int(nullable: true).merge(description: "Set for a change to one game's link."),
        game_title: str(nullable: true),
        action: str(enum: GamedbFranchiseChange::ACTIONS),
        before: json.merge(description: "The values it changed, before: `{ source, mainline, created_at, " \
                                        "created_by }` for unlink (null for link, or `{ unlinked_by, " \
                                        "unlinked_at }` when the link replaced a removal), `{ mainline }`, " \
                                        "`{ name, name_locked }` for rename, `{ franchise_id, name, " \
                                        "igdb_franchise_id, games }` for merge (the Franchise merged in) and " \
                                        "`{ name, igdb_franchise_id, games }` for delete."),
        after: json.merge(description: "The values after (null for unlink and delete)."),
        user_id: str(nullable: true).merge(description: "Who made it."),
        username: str(nullable: true),
        created_at: ts,
        undone_at: ts(nullable: true),
        undone_by: str(nullable: true).merge(description: "Who undid it."),
        undone_by_username: str(nullable: true),
        can_undo: bool.merge(description: "The viewer may undo it now: an undoable action (link, unlink, " \
                                          "Mainline, rename), not undone, and nothing later touched the same " \
                                          "game or name.")
      ),
      Genre: obj(genre_id: int, name: str, igdb_genre_id: int(nullable: true)),
      Engine: obj(engine_id: int, name: str, igdb_engine_id: int(nullable: true)),
      Mode: obj(mode_id: int, name: str, igdb_game_mode_id: int(nullable: true)),
      Perspective: obj(perspective_id: int, name: str, igdb_perspective_id: int(nullable: true)),
      Theme: obj(theme_id: int, name: str, igdb_theme_id: int(nullable: true)),
      Region: obj(region_id: int, region_code: str, region_name: str, igdb_region_id: int(nullable: true)),
      # Game series. Trimmed shape (CollectionResource): only id + name are
      # exposed; the IGDB bookkeeping column is dropped.
      Collection: obj(collection_id: int, name: str),
      # The trimmed platform shape (PlatformResource), used by the embedded
      # `platform` on entries and the platforms list. `platform_abbreviation` and
      # `igdb_platform_id` were added for the Game read-path migration (#106).
      Platform: obj(
        platform_id: int, platform_code: str, platform_name: str,
        platform_abbreviation: str(nullable: true), igdb_platform_id: int(nullable: true)
      ),
      # platforms#show renders `as_json` — all columns, including the IGDB
      # bookkeeping the list trims.
      PlatformDetail: obj(
        platform_id: int, platform_code: str, platform_name: str,
        igdb_platform_id: int(nullable: true), platform_abbreviation: str(nullable: true),
        platform_slug: str(nullable: true), platform_checksum: str(nullable: true),
        igdb_updated_at: int(nullable: true)
      ),
      # social_platforms (all columns). `label` is unique (case-insensitive).
      SocialPlatform: obj(
        id: int, label: str, position: int, created_by_user_id: str(nullable: true),
        created_at: ts, updated_at: ts
      ),

      # ---- game shapes -----------------------------------------------------
      # The reusable embedded-game shape (GameSummaryResource / GameFields): a
      # consumer-audited subset of gamedb_games plus the derived image URLs.
      GameSummary: obj(
        game_id: int, title: str, description: str(nullable: true),
        igdb_id: int(nullable: true), slug: str(nullable: true),
        igdb_url: str(nullable: true), initial_release_date: ts(nullable: true),
        cover_url: str(nullable: true), art_url: str(nullable: true), logo_url: str(nullable: true)
      ),
      # games#index / #show / create-from-IGDB (GameResource): GameSummary plus
      # the GOTM/NR-GOTM winner flags selected by the `without_images` scope.
      Game: extends("GameSummary", gotm_won: bool, nr_gotm_won: bool, required: %w[gotm_won nr_gotm_won]),
      # TrackedGameResource, the game in the Review Feed and the drafts
      # listing: Game plus the month each track was last won.
      TrackedGame: extends("Game",
        gotm_month_year: str(nullable: true).merge(description: "The month it won GOTM (its latest win), " \
                                                                "e.g. \"November 2024\"; null if it never did."),
        nr_gotm_month_year: str(nullable: true).merge(description: "The month it won NR-GOTM (its latest win); " \
                                                                   "null if it never did."),
        required: %w[gotm_month_year nr_gotm_month_year]),
      # GameWithPlatformsResource: GameSummary plus the game's platforms, for
      # the two consumers that render platform pills — the nomination board and
      # the dashboard's GOTM / NR-GOTM cards. Ordered by `platform_name`; empty
      # when the game has no platform rows. Every other embedded game keeps the
      # platform-free GameSummary.
      GameWithPlatforms: extends("GameSummary", platforms: array_of("Platform")),
      # GamedbGameImage (all columns) plus the derived public `url`.
      GameImage: obj(
        image_id: int, game_id: int, kind: str, object_key: str,
        uploaded_by_user_id: str(nullable: true), is_primary: bool, position: int,
        created_at: ts, updated_at: ts, url: str
      ),
      # GamedbRelease (all columns) plus the flattened platform/region labels.
      Release: obj(
        release_id: int, game_id: int, platform_id: int, region_id: int,
        format: str(nullable: true), notes: str(nullable: true),
        release_date: date(nullable: true, description: "Plain calendar date (YYYY-MM-DD) at the Release's " \
          "Date Precision: the first day of its month or quarter, 1 January of its year, null when TBA."),
        date_precision: str(enum: GamedbRelease::DATE_PRECISIONS, description: "How exactly the date is " \
          "known: day, month, quarter, year, or tba (no date yet). Only day Releases are announced."),
        source: str(enum: GamedbRelease::SOURCES, description: "igdb: an IGDB Release, kept in step by the " \
          "IGDB refresh. manual: a Manual Release (staff or another import), never changed by a refresh."),
        platform_code: str, platform_name: str, region_code: str, region_name: str
      ),
      # One Release inside an Upcoming Release (UpcomingReleaseResource).
      UpcomingReleaseRelease: obj(
        release_id: int, platform_id: int, platform_name: str, platform_abbreviation: str(nullable: true),
        region_id: int, region_code: str, region_name: str,
        format: str(nullable: true, description: "Physical, Digital, or null when unknown."),
        source: str(enum: GamedbRelease::SOURCES)
      ),
      # An Upcoming Release on the Release Calendar (UpcomingReleaseResource,
      # spec #389): one game's Releases sharing a date and Date Precision.
      UpcomingRelease: obj(
        game: obj(game_id: int, title: str, cover_url: str(nullable: true)),
        date: date(nullable: true, description: "Plain calendar date (YYYY-MM-DD) shared by the Releases, at " \
          "their Date Precision: the first day of the month or quarter, 1 January of the year, null when TBA."),
        date_precision: str(enum: GamedbRelease::DATE_PRECISIONS),
        section: str(example: "July 2027", description: "The heading to list it under: the month " \
          "(\"July 2027\") for day and month Upcoming Releases, \"Q3 2027\" for a quarter, \"2027\" for a year, \"TBA\"."),
        first_released_on: date(nullable: true, description: "The game's earliest dated Release (any platform " \
          "or region, earliest date, then the more precise Date Precision) whose whole period ended before " \
          "this Upcoming Release's date (any dated Release for a TBA one), so a vague Release still running on the " \
          "Upcoming Release's date does not count. Null otherwise, so the game's first Upcoming Release has none."),
        first_released_precision: str(nullable: true, enum: [ *(GamedbRelease::DATE_PRECISIONS - %w[tba]), nil ],
          description: "The Date Precision of " \
          "`first_released_on` (day, month, quarter or year); null with it."),
        releases: array_of("UpcomingReleaseRelease"),
        _required: %w[game date date_precision section first_released_on first_released_precision releases]
      ),
      # `meta` of POST /games/{id}/refresh-releases: the count the bot reports.
      ReleaseRefreshMeta: obj(
        added: int, total: int,
        _description: "How many releases the refresh added (never negative) and the new total."
      ),
      # A GamedbGameCompany flattened to its company's columns plus the join `role`.
      GameCompany: obj(
        company_id: int, name: str, igdb_company_id: int(nullable: true), role: str
      ),
      # GamedbReleaseAnnouncement (all columns). The delivery columns
      # (`sent_at`, `skipped_at`, `skip_reason`) are admin/service-writable (the
      # bot PATCHes them to mark an announcement sent/missed, #109); the #skip
      # action remains a convenience for the skip-only path.
      ReleaseAnnouncement: obj(
        release_id: int, announce_at: ts, sent_at: ts(nullable: true),
        skipped_at: ts(nullable: true), skip_reason: str(nullable: true),
        created_at: ts, updated_at: ts
      ),
      # A single row of the release-announcements "due" feed
      # (ReleaseAnnouncementsController#due / DueReleaseAnnouncementResource): the
      # announcement joined to its release, game and platform. `id` and
      # `release_id` are the same value (the PK is the release_id, 1:1).
      DueReleaseAnnouncement: obj(
        id: int, release_id: int, game_id: int, title: str,
        release_date: date(description: "Plain calendar date (YYYY-MM-DD); always an exact day."),
        announce_at: ts, platform_name: str(nullable: true),
        platform_abbreviation: str(nullable: true), igdb_url: str(nullable: true)
      ),

      # ---- user shapes -----------------------------------------------------
      # The reusable embedded/members-list user shape (UserSummaryResource /
      # UserFields): a consumer-audited subset of rpg_club_users.
      UserSummary: obj(
        user_id: str, username: str(nullable: true), global_name: str(nullable: true),
        is_bot: bool, role_admin: bool, role_moderator: bool, role_regular: bool,
        server_left_at: ts(nullable: true)
      ),
      # The computed membership summary (RpgClubUser#membership). `admin`,
      # `moderator`, `regular` and `member` follow the member's Discord roles.
      Membership: obj(
        admin: bool, moderator: bool, regular: bool, member: bool, newcomer: bool, active: bool,
        _description: "Membership flags. admin, moderator, regular and member follow the member's " \
                      "Discord roles (refreshed at sign-in and on each bot role report)."
      ),
      # UserSocial (all columns; note the FK alias `platform_id`, NOT
      # `social_platform_id`) plus the embedded social platform.
      UserSocial: obj(
        id: int, user_id: str, platform_id: int, display_text: str(nullable: true),
        url: str(nullable: true), created_at: ts, updated_at: ts,
        social_platform: ref("SocialPlatform")
      ),
      # Per-user counts on the profile payload (UsersController#show). A count
      # that belongs to a Feature the viewer cannot use is left out.
      UserCounts: obj(
        now_playing: int, favorites: int, reviews: int, completions: int,
        backlog: int, collections: int, journal: int,
        _required: %w[favorites],
        _description: "Each count but `favorites` belongs to a Feature (now_playing: Now Playing, reviews: Reviews, " \
                      "completions: Game Completions, backlog: Backlog, collections: Collection, journal: Journals) " \
                      "and is left out when the viewer cannot use that Feature (Preview: staff only; Off: nobody). " \
                      "The service token gets every count."
      ),
      # The full users#show profile payload (UserResource): UserSummary plus
      # `membership`, the embedded socials, the four preview lists, the journal
      # grid and the counts summary.
      User: extends(
        "UserSummary",
        _description: "The Feature-owned previews (now_playing, reviews, completions, journal) are left out, like " \
                      "their `counts`, when the viewer cannot use that Feature.",
        membership: ref("Membership"),
        socials: array_of("UserSocial"),
        now_playing: array_of("NowPlayingEntry"),
        favorites: array_of("FavoriteEntry"),
        reviews: array_of("ReviewEntry"),
        completions: array_of("CompletionEntry"),
        journal: array_of("JournaledGame"),
        counts: ref("UserCounts"),
        birthday: ref("Birthday", nullable: true).merge(
          description: "The member's Birthday when they share it (api#399); null otherwise. Never the year."
        )
      ),
      # The members-list shape returned by users#index when filtered by
      # `has_platform` (#99, UserWithSocialsResource): UserSummary plus the
      # embedded `socials` list so the bot's `/mp-info` migration gets each
      # matched user's platform handles in one call. `socials` is present only
      # on that filtered variant (arrays are already excluded from `required`).
      UserWithSocials: extends("UserSummary", socials: array_of("UserSocial")),
      # The service-managed user shape (#105, UserServiceResource): UserSummary
      # plus the three Discord-sync columns the bot reads/writes. Returned by the
      # service-only upsert/update writes and the `has_emoji_name` index branch.
      UserService: extends(
        "UserSummary",
        server_joined_at: ts(nullable: true),
        last_seen_at: ts(nullable: true),
        emoji_name: str(nullable: true)
      ),
      # The result of the service-only role report (PUT /users/:user_id/roles):
      # the member's membership summary after the role flags were refreshed.
      UserRoleReport: obj(
        user_id: str, membership: ref("Membership"),
        _required: %w[user_id membership]
      ),
      # The bot's Feature access lookup (GET /users/:user_id/feature_access,
      # spec #347): Features::Access#lookup_features for a Discord user, with
      # staff read from the member's stored Admin and dev roles.
      FeatureAccess: obj(
        user_id: str,
        staff: { type: :boolean, description: "Admin or Superadmin by the member's stored roles. False for a " \
                                              "Discord user with no member record." },
        features: { type: :array, items: { "$ref" => "#/components/schemas/FeatureAccessEntry" },
                    description: "Every Feature in registry order, whatever its state." },
        _required: %w[user_id staff features]
      ),
      FeatureAccessEntry: obj(
        key: str, name: str,
        state: str(enum: %w[off preview live], description: "The Feature Flag state; a Feature with no stored " \
                                                            "state reads as preview."),
        can_use: { type: :boolean, description: "Live: everyone. Preview: staff only. Off: nobody." },
        preview: { type: :boolean, description: "True when the user can use the Feature only because they are " \
                                                 "staff (Preview), so the bot adds its Preview note." }
      ),
      # A Feature as staff see it on the flag desk and in `/flag list`
      # (GET /features, spec #347; Features::StaffList).
      FeatureFlagEntry: obj(
        key: str, name: str,
        state: str(enum: Features::STATES, description: "The Feature Flag state; a Feature with no stored state " \
                                                        "reads as preview."),
        core: bool.merge(description: "A Core Feature, which members cannot hide."),
        hideable: bool.merge(description: "Members may hide it with a Feature Preference (not Core)."),
        coverage: obj(
          website: { type: :array, items: str, description: "Pages and sections on the website." },
          bot: { type: :array, items: str, description: "Bot commands." },
          posts: { type: :array, items: str, description: "Automated posts." },
          _required: %w[website bot posts]
        ),
        last_change: ref("FeatureFlagLastChange", nullable: true).merge(
          description: "The latest logged change; null when the Feature has never been set."
        ),
        _required: %w[key name state core hideable coverage last_change]
      ),
      FeatureFlagLastChange: obj(
        from_state: str(enum: Features::STATES, description: "The state it read as before (preview when it had no " \
                                                             "stored state)."),
        to_state: str(enum: Features::STATES),
        changed_by: str(description: "The acting member's Discord user id, or `system` (the seed)."),
        changed_by_name: str(nullable: true, description: "The member's display name; null for `system`, or a " \
                                                          "member with no record."),
        reason: str(nullable: true),
        changed_at: ts,
        _required: %w[from_state to_state changed_by changed_by_name reason changed_at]
      ),
      # The result of the bulk `users#mark_departed` reconciliation (#105): the
      # count of users newly stamped as departed.
      MarkDepartedResult: obj(
        count: int, _description: "Number of users newly marked departed."
      ),

      # ---- user-game collection entries ------------------------------------
      # BacklogEntryResource: trimmed columns + embedded game/platform.
      BacklogEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        note: str(nullable: true), game: ref("GameSummary"), platform: ref("Platform", nullable: true)
      ),
      # backlog#pick (BacklogPickResource): the suggested entry, from the backlog
      # or the collection, with its game, platform and HLTB times. `hours` is the
      # parsed HLTB time `max_hours` compares (main, single player, main + sides).
      BacklogPick: obj(
        kind: str(enum: %w[backlog collection]), entry_id: int, gamedb_game_id: int,
        platform_id: int(nullable: true), note: str(nullable: true), hours: num(nullable: true),
        game: ref("GameSummary"), platform: ref("Platform", nullable: true), hltb: ref("Hltb", nullable: true)
      ),
      # A platform the backlog#pick filter can choose, with the distinct games on it.
      BacklogPickPlatform: obj(
        platform_id: int, platform_name: str(nullable: true), platform_abbreviation: str(nullable: true), count: int
      ),
      BacklogPickMeta: obj(
        seed: { type: :integer, minimum: 0, maximum: 0xffffffff, description: "The shuffle seed; repeat it to reroll." },
        position: { type: :integer, nullable: true, description: "Where the pick sits in the shuffled order (null with no pick)." },
        next_position: { type: :integer, nullable: true, description: "Pass as `position` to reroll (null with no pick)." },
        wrapped: { type: :boolean, description: "The walk passed the end of the list, so picks may repeat." },
        total: { type: :integer, description: "Candidates after the source and platform filters, before `max_hours`." },
        platforms: array_of("BacklogPickPlatform")
      ),
      # collections#index (CollectionEntryResource): trimmed columns + the joined
      # platform name/abbreviation (CollectionFields, #101; the bot reads the
      # flat pair) + the embedded game and platform (null with no platform).
      CollectionEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        ownership_type: str, note: str(nullable: true),
        platform_name: str(nullable: true), platform_abbreviation: str(nullable: true),
        game: ref("GameSummary"), platform: ref("Platform", nullable: true),
        _required: %w[entry_id user_id gamedb_game_id platform_id ownership_type note
                      platform_name platform_abbreviation game platform]
      ),
      # collections#game_index (CollectionUserEntryResource): the CollectionEntry
      # fields + the owning user, for the community-ownership view (#101).
      CollectionUserEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        ownership_type: str, note: str(nullable: true),
        platform_name: str(nullable: true), platform_abbreviation: str(nullable: true),
        user: ref("UserSummary")
      ),
      # collections#show / create / update (CollectionEntryDetailResource): the
      # CollectionEntry fields + the joined platform name/abbreviation (#101)
      # plus `is_shared` and the timestamps the list trims.
      CollectionEntryDetail: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        ownership_type: str, note: str(nullable: true),
        platform_name: str(nullable: true), platform_abbreviation: str(nullable: true),
        is_shared: bool, created_at: ts, updated_at: ts
      ),
      # collections#platform_summary: a per-platform tally (CollectionPlatformCount)
      # plus the user's total, mirroring the bot's `getOverviewForUser` (#101).
      CollectionPlatformCount: obj(
        platform_id: int(nullable: true), platform_name: str(nullable: true),
        platform_abbreviation: str(nullable: true), count: int
      ),
      CollectionPlatformSummary: obj(
        total_count: int, platform_counts: array_of("CollectionPlatformCount")
      ),
      # CompletionEntryResource (CompletionFields + game + platform). `created_at`
      # is the row's insert time (NOT NULL), exposed for the bot's CSV export (#102).
      CompletionEntry: obj(
        completion_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        note: str(nullable: true), completion_type: str, completed_at: ts(nullable: true),
        final_playtime_hrs: num(nullable: true), created_at: ts,
        game: ref("GameSummary"), platform: ref("Platform", nullable: true)
      ),
      # CompletionMemberEntryResource (CompletionEntry + user), the club-wide
      # feed (CompletionsController#recent).
      CompletionMemberEntry: extends("CompletionEntry", user: ref("UserSummary")),
      # CommonCompletionEntryResource (CompletionsController#common): a game both
      # members completed. `latest_shared_date` is the latest `completed_at`
      # across both members (null when every entry is undated); each side holds
      # that member's latest entry for the game and their completion count.
      CommonCompletionSide: obj(latest: ref("CompletionEntry"), count: int, _required: %w[latest count]),
      CommonCompletionEntry: obj(
        gamedb_game_id: int, latest_shared_date: ts(nullable: true), game: ref("GameSummary"),
        left: ref("CommonCompletionSide"), right: ref("CommonCompletionSide"),
        _required: %w[gamedb_game_id latest_shared_date game left right]
      ),
      CommonCompletionMeta: extends(
        "PaginationMeta", left_user_id: str, right_user_id: str
      ),
      # CompletionUserEntryResource (CompletionFields + user), for game-scoped lists.
      CompletionUserEntry: obj(
        completion_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        note: str(nullable: true), completion_type: str, completed_at: ts(nullable: true),
        final_playtime_hrs: num(nullable: true), created_at: ts, user: ref("UserSummary")
      ),
      # CompletionsController#leaderboard (CompletionLeaderboardEntryResource):
      # a user ranked by total completion count. An aggregate row, not a model
      # record — `completion_count` is the grouped `COUNT(*)`.
      CompletionLeaderboardEntry: obj(
        user_id: str, username: str(nullable: true), global_name: str(nullable: true),
        completion_count: int
      ),
      # FavoriteEntryResource (no platform association).
      FavoriteEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, note: str(nullable: true),
        game: ref("GameSummary")
      ),
      # The now-playing embedded game (NowPlayingEmbeds): the GameSummary shape
      # plus the game's linked Discord thread, derived per-entry (#104).
      NowPlayingGame: extends("GameSummary", linked_thread_id: str(nullable: true)),
      # NowPlayingEntryResource (NowPlayingFields + game + platform), the user's
      # own list. `gamedb_game_id` is nullable on user_now_playing. The journal
      # fields (#104) are correlated aggregates over the (user, game) pair.
      NowPlayingEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int(nullable: true),
        platform_id: int(nullable: true), note: str(nullable: true),
        sort_order: int(nullable: true), added_at: ts, note_updated_at: ts(nullable: true),
        has_journal_entry: bool, journal_count: int, last_journal_at: ts(nullable: true),
        game: ref("NowPlayingGame", nullable: true), platform: ref("Platform", nullable: true)
      ),
      # NowPlayingUserEntryResource (NowPlayingFields + user), for game-scoped lists.
      NowPlayingUserEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int(nullable: true),
        platform_id: int(nullable: true), note: str(nullable: true),
        sort_order: int(nullable: true), added_at: ts, note_updated_at: ts(nullable: true),
        has_journal_entry: bool, journal_count: int, last_journal_at: ts(nullable: true),
        user: ref("UserSummary")
      ),
      # NowPlayingMemberEntryResource (NowPlayingFields + user + game + platform),
      # the cross-member list / single-entry / update shape (#104).
      NowPlayingMemberEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int(nullable: true),
        platform_id: int(nullable: true), note: str(nullable: true),
        sort_order: int(nullable: true), added_at: ts, note_updated_at: ts(nullable: true),
        has_journal_entry: bool, journal_count: int, last_journal_at: ts(nullable: true),
        game: ref("NowPlayingGame", nullable: true), platform: ref("Platform", nullable: true),
        user: ref("UserSummary")
      ),
      # The per-category review scorecard (UserGameReview::FACET_KEYS, mirrored by
      # `www/lib/reviews/facets.ts`). Null on a "quick take" — a review with no
      # scorecard, which is what every review written before it existed is.
      # `order` carries the display order, which jsonb objects do not preserve,
      # and may hold a facet that has no score yet ("on the card, not yet scored").
      # `obj` derives `required` from non-null scalars only, so arrays and the
      # scores object need the explicit list.
      ReviewFacets: obj(
        template: {
          type: :string, enum: UserGameReview::FACET_TEMPLATES,
          description: "Which preset the card was last built from. Provenance, not a constraint — " \
                       "every preset is editable, so `order` is not checked against it."
        },
        order: {
          type: :array,
          items: {
            type: :string,
            anyOf: [
              { type: :string, enum: UserGameReview::FACET_KEYS },
              { type: :string, pattern: CUSTOM_FACET_PATTERN }
            ],
            description: "Either a catalogue key or a `custom:N` key the reviewer invented on this card."
          },
          maxItems: UserGameReview::MAX_FACETS,
          description: "The scorecard's facets in display order. Unique. A `custom:N` entry must have " \
                       "a non-empty `labels` entry — an unnamed custom row has nothing to render — " \
                       "which OpenAPI cannot express; the API enforces it with a 422."
        },
        labels: {
          type: :object,
          additionalProperties: { type: :string, maxLength: UserGameReview::MAX_LABEL_LENGTH },
          description: "Optional display names, keyed by facet. Keys must appear in `order` and values " \
                       "must be non-empty. On a catalogue facet this is a display override only — the " \
                       "key stays canonical, so a row renamed \"Job System\" still counts as `combat`. " \
                       "On a `custom:N` facet it is required."
        },
        scores: {
          type: :object, additionalProperties: { type: :integer, minimum: 0, maximum: 100 },
          description: "Facet key to score, on the same 0..100 scale as `rating`. Keys must appear in `order`."
        },
        weights: {
          type: :object,
          additionalProperties: { type: :integer, minimum: 0, maximum: UserGameReview::WEIGHT_TOTAL },
          description: "Optional per-facet share of the #{UserGameReview::WEIGHT_TOTAL}-point budget, " \
                       "used to weight `facet_average`. Absent means unweighted (every scored facet " \
                       "counts once). When present the keys are exactly those in `order` and the values " \
                       "sum to exactly #{UserGameReview::WEIGHT_TOTAL} — an invariant OpenAPI cannot " \
                       "express, enforced by the API with a 422."
        },
        _required: %w[template order]
      ),
      # reviews#show / create / update / publish render `as_json` (all columns,
      # including `updated_at`, which the curated shape trims). A Draft has a
      # null `published_at` and may have a null `rating`.
      Review: obj(
        review_id: int, user_id: str, gamedb_game_id: int,
        rating: int(nullable: true).merge(description: "The current score: the latest Published Revision's, " \
                                                       "else the Review's own. Null only on a Draft with no " \
                                                       "score yet."),
        original_rating: int(nullable: true).merge(description: "The original take's own score (the one an " \
                                                                "Edit to this Review changes)."),
        revisions: array_of("ReviewRevision").merge(description: "The Published Revisions, in publish order."),
        draft_revision: ref("ReviewRevision", nullable: true).merge(
          description: "The Draft Revision, for its author and Admins only; null for everyone else, or when " \
                       "the author isn't Revisiting."
        ),
        title: str(nullable: true, maxLength: 120), body: json,
        facets: ref("ReviewFacets", nullable: true),
        published_at: ts(nullable: true).merge(description: "When it was published; null while a Draft. " \
                                                             "Set once and never cleared."),
        edited_at: ts(nullable: true).merge(description: "When it was last Edited, if more than an hour after " \
                                                          "publishing (ADR 0013); null otherwise."),
        score_locks_at: ts(nullable: true).merge(description: "When the score stops being editable, 7 days " \
                                                                 "after publishing (ADR 0013): past it an Edit " \
                                                                 "that changes `rating` gets 422 `score_locked`. " \
                                                                 "Null while a Draft."),
        created_at: ts, updated_at: ts
      ),
      # A Revision (UserGameReviewRevision#as_json): a dated return to a
      # Published Review, served by the revision endpoints and inside the
      # Review shape (spec api#430, ticket #433).
      ReviewRevision: obj(
        revision_id: int, review_id: int,
        rating: int(nullable: true).merge(description: "This take's score. Null only on a Draft with no score yet."),
        previous_rating: int.merge(description: "The score this take replaced: on a Published Revision the " \
                                                "score just before it was published; on a Draft, the Review's " \
                                                "current score."),
        title: str(nullable: true, maxLength: 120), body: json,
        facets: ref("ReviewFacets", nullable: true),
        published_at: ts(nullable: true).merge(description: "When it was published; null while a Draft. " \
                                                             "Set once and never cleared."),
        edited_at: ts(nullable: true).merge(description: "When it was last Edited, if more than an hour after " \
                                                          "its own publishing (ADR 0013); null otherwise."),
        score_locks_at: ts(nullable: true).merge(description: "When the score stops being editable, 7 days " \
                                                                 "after this Revision was published (ADR 0013). " \
                                                                 "Null while a Draft."),
        created_at: ts, updated_at: ts
      ),
      # ReviewUserEntryResource (ReviewFields + user), for the game-scoped reviews list.
      ReviewUserEntry: obj(
        review_id: int, user_id: str, gamedb_game_id: int,
        rating: int.merge(description: "The current score: the latest Published Revision's, else the " \
                                     "Review's own (spec api#430)."),
        original_rating: int.merge(description: "The original take's score, whatever Revisions followed."),
        revised: bool.merge(description: "Whether it has Published Revisions (a newer take than the first)."),
        title: str(nullable: true, maxLength: 120), body: json,
        facets: ref("ReviewFacets", nullable: true), created_at: ts, published_at: ts,
        edited_at: ts(nullable: true).merge(description: "When it was last Edited, if more than an hour after " \
                                                          "publishing (ADR 0013); null otherwise."),
        user: ref("UserSummary")
      ),
      # ReviewEntryResource (ReviewFields + game): the user-scoped reviews list
      # (reviews#index) and the user profile preview.
      ReviewEntry: obj(
        review_id: int, user_id: str, gamedb_game_id: int,
        rating: int.merge(description: "The current score: the latest Published Revision's, else the " \
                                     "Review's own (spec api#430)."),
        original_rating: int.merge(description: "The original take's score, whatever Revisions followed."),
        revised: bool.merge(description: "Whether it has Published Revisions (a newer take than the first)."),
        title: str(nullable: true, maxLength: 120), body: json,
        facets: ref("ReviewFacets", nullable: true), created_at: ts, published_at: ts,
        edited_at: ts(nullable: true).merge(description: "When it was last Edited, if more than an hour after " \
                                                          "publishing (ADR 0013); null otherwise."),
        game: ref("GameSummary")
      ),
      # ReviewFeedEntryResource, one entry of the Review Feed
      # (ReviewsController#recent): a Published Review or Published Revision
      # with its author and its game (with the GOTM / NR-GOTM track flags).
      ReviewFeedEntry: obj(
        kind: str(enum: %w[review revision]).merge(
          description: "`review` for a Published Review, `revision` for a Published Revision (its own entry)."
        ),
        review_id: int,
        revision_id: int(nullable: true).merge(description: "The Revision, on a `revision` entry; null on a `review`."),
        user_id: str, gamedb_game_id: int,
        rating: int.merge(description: "This take's own score (not the Review's current one)."),
        previous_rating: int(nullable: true).merge(description: "The score the Revision replaced, on a " \
                                                                "`revision` entry; null on a `review`."),
        title: str(nullable: true, maxLength: 120), body: json,
        written: bool.merge(description: "Whether the body holds any text. False for a score-only quick take."),
        facets: ref("ReviewFacets", nullable: true), created_at: ts, published_at: ts,
        edited_at: ts(nullable: true).merge(description: "When it was last Edited, if more than an hour after " \
                                                          "publishing (ADR 0013); null otherwise."),
        user: ref("UserSummary"), game: ref("TrackedGame")
      ),
      # ReviewDraftEntryResource (a Draft Review or Draft Revision, with
      # updated_at and the game with its track flags), the author's drafts
      # listing (reviews#drafts).
      ReviewDraftEntry: obj(
        kind: str(enum: %w[review revision]).merge(
          description: "`review` for a Draft Review, `revision` for a Draft Revision of a Published Review."
        ),
        review_id: int,
        revision_id: int(nullable: true).merge(description: "The Revision, on a `revision` entry; null on a `review`."),
        user_id: str, gamedb_game_id: int,
        rating: int(nullable: true).merge(description: "This Draft's score; null until the author picks one."),
        previous_rating: int(nullable: true).merge(description: "On a `revision` entry, the Review's current " \
                                                                "score, which publishing would replace; null " \
                                                                "on a `review`."),
        title: str(nullable: true, maxLength: 120), body: json,
        facets: ref("ReviewFacets", nullable: true), created_at: ts,
        published_at: ts(nullable: true).merge(description: "Always null: a Draft is unpublished."),
        edited_at: ts(nullable: true).merge(description: "Always null: a Draft is never Edited."),
        updated_at: ts.merge(description: "When the author last touched it; the listing's order."),
        game: ref("TrackedGame")
      ),
      # JournalEntryGameResource (JournalFields + game), single-entry endpoints.
      JournalEntryGame: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, entry_title: str(nullable: true),
        entry_body: str, created_at: ts, updated_at: ts, game: ref("GameSummary")
      ),
      # JournalEntryUserResource (JournalFields + user), game-scoped public list.
      JournalEntryUser: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, entry_title: str(nullable: true),
        entry_body: str, created_at: ts, updated_at: ts, user: ref("UserSummary")
      ),
      # JournaledGameResource: a game summary plus the user's per-game aggregates.
      JournaledGame: obj(
        game: ref("GameSummary"), entry_count: int, last_entry_at: ts(nullable: true)
      ),
      # JournalEntryGameUserResource (JournalFields + game + author), the
      # cross-user search list (journal#search).
      JournalEntryGameUser: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, entry_title: str(nullable: true),
        entry_body: str, created_at: ts, updated_at: ts,
        game: ref("GameSummary"), user: ref("UserSummary")
      ),
      # JournalStatusResource (journal#status): a game's per-user entry count and
      # last-entry timestamp. An aggregate row — `entry_count` is the grouped
      # `COUNT(*)`, `last_entry_at` the grouped `MAX(created_at)`.
      JournalStatus: obj(
        gamedb_game_id: int, entry_count: int, last_entry_at: ts(nullable: true)
      ),
      # JournalContributorResource (journal#contributors): a user with at least
      # one journal entry, ranked by distinct journaled-game count. An aggregate
      # row — `game_count`/`entry_count` are the grouped `COUNT`s.
      JournalContributor: obj(
        user_id: str, username: str(nullable: true), global_name: str(nullable: true),
        game_count: int, entry_count: int
      ),

      # ---- RPGClub features ------------------------------------------------
      # SuggestionResource: every column plus the upvote count and whether
      # the viewer upvoted (#318). The review columns are null until review.
      Suggestion: obj(
        suggestion_id: int, title: str, details: str(nullable: true), created_by: str(nullable: true),
        created_at: ts, updated_at: ts, labels: str(nullable: true), created_by_name: str(nullable: true),
        status: str(enum: RpgClubSuggestion::STATUSES),
        reviewed_by: str(nullable: true).merge(description: "Discord user id of the reviewing Superadmin."),
        reviewed_at: ts(nullable: true),
        rejection_reason: str(nullable: true).merge(description: "Set when rejected."),
        target_repo: str(nullable: true).merge(description: "Repo the approval opened its GitHub issue in."),
        github_issue_number: int(nullable: true), github_issue_url: str(nullable: true),
        github_issue_state: str(nullable: true, enum: [ "open", "closed", nil ]).merge(
          description: "Approved only: the GitHub issue's state, cached about ten minutes. " \
                       "Null otherwise, or when GitHub cannot say."
        ),
        upvote_count: int,
        viewer_upvoted: bool.merge(description: "Whether the signed-in member upvoted it; false for the service."),
        last_activity_at: ts.merge(
          description: "The latest activity: the newest of its last change (submitted, reviewed or " \
                       "withdrawn, i.e. `updated_at`) and its newest upvote. `sort=recent` orders by it."
        )
      ),
      # SuggestionsController#approve / #reject meta: the queued outcome job,
      # so the website can poll GET /api/v1/bot_jobs/{id}.
      SuggestionReviewMeta: obj(
        outcome_job_id: int.merge(description: "The suggestion_outcome bot job (the bot announces the outcome).")
      ),
      # `suggestion_ids` is the stored JSON string, returned verbatim.
      SuggestionReviewSession: obj(
        session_id: str, reviewer_id: str, suggestion_ids: str, current_index: int,
        total_count: int, created_at: ts, updated_at: ts
      ),
      StarboardEntry: obj(
        message_id: str, channel_id: str, starboard_message_id: str, author_id: str,
        star_count: int, created_at: ts
      ),
      # `state_json` is the stored JSON string, returned verbatim.
      WizardSession: obj(
        session_id: str, command_key: str, owner_user_id: str, channel_id: str,
        guild_id: str(nullable: true), status: str, state_json: str,
        last_updated_at: ts, created_at: ts, updated_at: ts
      ),
      # CollectionCsvImportResource: every RpgClubCollectionCsvImport column
      # (#163). `current_index`/`total_count` let the bot resume a
      # paused/interrupted import. `test_mode` marks a dry-run session whose
      # subsequent writes are rolled back instead of persisted (#187).
      CollectionCsvImport: obj(
        import_id: int, user_id: str, status: str, current_index: int, total_count: int,
        source_file_name: str(nullable: true), source_file_size: int(nullable: true),
        template_version: str(nullable: true), test_mode: bool, created_at: ts, updated_at: ts
      ),
      # CollectionCsvImportItemResource: every RpgClubCollectionCsvImportItem
      # column (#163) — the raw parsed CSV fields plus the resolved match and
      # outcome once the bot's matcher has run the row.
      CollectionCsvImportItem: obj(
        item_id: int, import_id: int, row_index: int,
        raw_title: str(nullable: true), raw_platform: str(nullable: true),
        raw_ownership_type: str(nullable: true), raw_note: str(nullable: true),
        raw_gamedb_id: int(nullable: true), raw_igdb_id: int(nullable: true),
        platform_id: int(nullable: true), ownership_type: str(nullable: true), note: str(nullable: true),
        status: str, match_confidence: str(nullable: true), match_candidate_json: str(nullable: true),
        gamedb_game_id: int(nullable: true), collection_entry_id: int(nullable: true),
        result_reason: str(nullable: true), error_text: str(nullable: true)
      ),
      # collection_csv_imports#summary: item counts grouped by status and by
      # result_reason, replacing the bot's countItemsByStatus/countItemsByReason.
      CollectionCsvImportSummary: obj(
        import_id: int,
        by_status: { type: :object, description: "Item count keyed by status.", additionalProperties: { type: :integer } },
        by_result_reason: { type: :object, description: "Item count keyed by result_reason.", additionalProperties: { type: :integer } }
      ),
      # collection_csv_imports#create with `csv_text` (#290): the whole file is
      # rejected; `errors` lists every problem (row_index 1 is the header or
      # the file as a whole).
      InvalidCsvError: obj(
        error: str(example: "invalid_csv"),
        errors: {
          type: :array,
          items: obj(row_index: int, column: str(example: "platform"),
            message: str(example: "Platform not recognized. Use a platform name or id."))
        },
        _required: %w[error errors]
      ),
      # One GameDB match for an import row (Imports::Candidate), as returned
      # by the import workflow endpoints (#290).
      ImportCandidate: obj(game_id: int, title: str, cover_url: str(nullable: true)),
      # An IGDB search hit for an import row (igdb_candidates, #290): the
      # Igdb::Client#search candidate plus `already_imported`.
      ImportIgdbCandidate: obj(
        igdb_id: int, name: str, slug: str(nullable: true), summary: str(nullable: true),
        url: str(nullable: true), total_rating: num(nullable: true),
        first_release_date: str(nullable: true, description: "ISO 8601 timestamp."),
        cover_url: str(nullable: true), already_imported: bool
      ),
      # collection_csv_imports#advance and collection_csv_import_items#remap
      # (#290): the import, the item that needs a human (null when none is
      # left or the per-request auto-apply cap was reached; see the import's
      # status), its stored candidates and confidence, and the item counts.
      CollectionCsvImportReview: obj(
        import: ref("CollectionCsvImport"),
        item: ref("CollectionCsvImportItem", nullable: true),
        candidates: array_of("ImportCandidate"),
        match_confidence: str(nullable: true, enum: [ "exact", "fuzzy", "manual", nil ]),
        counts: ref("CollectionCsvImportSummary"),
        _required: %w[import item candidates match_confidence counts]
      ),
      # CompletionatorImportResource: every RpgClubCompletionatorImport column
      # (#164). `current_index`/`total_count` let the bot resume a
      # paused/interrupted import. `test_mode` marks a dry-run session whose
      # subsequent writes are rolled back instead of persisted (#188).
      CompletionatorImport: obj(
        import_id: int, user_id: str, status: str, current_index: int, total_count: int,
        source_filename: str(nullable: true), test_mode: bool, created_at: ts, updated_at: ts
      ),
      # CompletionatorImportItemResource: every RpgClubCompletionatorImportItem
      # column (#164) — the raw parsed Completionator export fields plus the
      # resolved match and outcome once the bot's matcher has run the row.
      CompletionatorImportItem: obj(
        item_id: int, import_id: int, row_index: int,
        game_title: str(nullable: true), platform_name: str(nullable: true),
        region_name: str(nullable: true), source_type: str(nullable: true),
        time_text: str(nullable: true), completed_at: ts(nullable: true),
        completion_type: str(nullable: true), playtime_hrs: num(nullable: true),
        status: str, gamedb_game_id: int(nullable: true), completion_id: int(nullable: true),
        error_text: str(nullable: true)
      ),
      # completionator_imports#summary: item counts grouped by status,
      # replacing the bot's countItemsByStatus.
      CompletionatorImportSummary: obj(
        import_id: int,
        by_status: { type: :object, description: "Item count keyed by status.", additionalProperties: { type: :integer } }
      ),
      # The Completionator import workflow (#291, Imports::CompletionatorWorkflow
      # via CompletionatorImportReview). completionator_imports#advance and
      # completionator_import_items#match return the collection CSV review
      # shape (#290) plus the Completionator steps: `next_step` tells the
      # client what to show; `candidates` are only set for choose_game;
      # `game` and `form` (and, with an existing completion,
      # `existing_completion` + `diff`) once a game is matched.
      CompletionatorDiff: obj(
        fields: { type: :array, items: { type: :string, enum: %w[type date playtime] },
                  description: "Row values that differ from the existing completion (update_completion options)." },
        confirm_same: bool.merge(description: "Both dates are set and differ: ask whether this is the same completion " \
                                              "(yes -> update_completion, no -> add_completion)."),
        _required: %w[fields confirm_same]
      ),
      CompletionatorForm: obj(
        completion_type: str(enum: [ "Main Story", "Main Story + Side Content", "Completionist" ]),
        platform_id: int(nullable: true).merge(description: "Default platform; null when it could not be resolved."),
        creates_release: bool.merge(description: "Adding with this platform_id creates the game's missing WW release."),
        platforms: array_of("Platform").merge(description: "Platform options: the game's platforms, then the standard platforms."),
        date_choice: str(enum: %w[csv unknown], description: "`csv` when the row has a date, else `unknown`."),
        completed_at: ts(nullable: true),
        final_playtime_hours: num(nullable: true),
        _required: %w[completion_type platform_id creates_release platforms date_choice completed_at final_playtime_hours]
      ),
      CompletionatorImportReview: obj(
        import: ref("CompletionatorImport"),
        item: ref("CompletionatorImportItem", nullable: true),
        candidates: array_of("ImportCandidate"),
        match_confidence: str(nullable: true, enum: [ "exact", "fuzzy", nil ]),
        counts: ref("CompletionatorImportSummary"),
        next_step: str(nullable: true, enum: [ "choose_game", "add_completion", "confirm_same", "update_completion",
                                               "auto_added", "auto_skipped", nil ],
                       description: "auto_added / auto_skipped only come from match (advance moves past them)."),
        game: ref("GameSummary", nullable: true),
        existing_completion: ref("CompletionEntry", nullable: true),
        diff: ref("CompletionatorDiff", nullable: true),
        form: ref("CompletionatorForm", nullable: true),
        auto_processed: int.merge(description: "Rows auto-added or auto-skipped by this advance call (0 for match)."),
        _required: %w[import item candidates match_confidence counts next_step game existing_completion diff form auto_processed]
      ),
      # SteamCollectionImportResource: every RpgClubSteamCollectionImport
      # column (#166). `current_index`/`total_count` let the bot resume a
      # paused/interrupted import. `test_mode` marks a dry-run session whose
      # subsequent writes are rolled back instead of persisted.
      SteamCollectionImport: obj(
        import_id: int, user_id: str, status: str, current_index: int, total_count: int,
        steam_id64: str, steam_profile_ref: str(nullable: true), source_profile_name: str(nullable: true),
        test_mode: bool, created_at: ts, updated_at: ts
      ),
      # SteamCollectionImportItemResource: every RpgClubSteamCollectionImportItem
      # column (#166) — the raw per-platform playtime pulled from the Steam
      # API plus the resolved match and outcome once the bot's matcher has
      # run the app.
      SteamCollectionImportItem: obj(
        item_id: int, import_id: int, row_index: int, steam_app_id: int, steam_app_name: str,
        playtime_forever_min: int(nullable: true), playtime_windows_min: int(nullable: true),
        playtime_mac_min: int(nullable: true), playtime_linux_min: int(nullable: true),
        playtime_deck_min: int(nullable: true), last_played_at: ts(nullable: true),
        status: str, match_confidence: str(nullable: true), match_candidate_json: str(nullable: true),
        gamedb_game_id: int(nullable: true), collection_entry_id: int(nullable: true),
        error_text: str(nullable: true), result_reason: str(nullable: true)
      ),
      # steam_collection_imports#counts: item counts grouped by status and by
      # result_reason, replacing the bot's countItemsByStatus/countItemsByReason.
      SteamCollectionImportCounts: obj(
        import_id: int,
        by_status: { type: :object, description: "Item count keyed by status.", additionalProperties: { type: :integer } },
        by_result_reason: { type: :object, description: "Item count keyed by result_reason.", additionalProperties: { type: :integer } }
      ),
      # AchievementSetLinkResource: an Achievement Set and its GameDB link
      # (admin PATCH /achievement_sets/:id).
      AchievementSetLink: obj(
        id: int, provider: str(enum: %w[retroachievements steam psn]), external_id: str,
        title: str(nullable: true), platform_label: str(nullable: true), icon_url: str(nullable: true),
        game_id: int(nullable: true)
      ),
      # SteamAppGamedbMapResource: every RpgClubSteamAppGamedbMap column
      # (#166) — the cached Steam app -> GameDB game mapping.
      SteamAppGamedbMap: obj(
        map_id: int, steam_app_id: int, gamedb_game_id: int(nullable: true), status: str,
        created_by: str(nullable: true), created_at: ts, updated_at: ts
      ),
      # steam_collection_imports#advance and steam_collection_import_items#remap
      # (#289), the same shape as CollectionCsvImportReview: the import, the
      # item that needs a human (null once the import is completed, or when
      # the per-request auto-apply cap was hit while the import is still
      # active), its GameDB candidates and confidence, and the item counts.
      SteamCollectionImportReview: obj(
        import: ref("SteamCollectionImport"),
        item: ref("SteamCollectionImportItem", nullable: true),
        candidates: array_of("ImportCandidate"),
        match_confidence: str(nullable: true, enum: [ "exact", "fuzzy", "manual", nil ]),
        counts: ref("SteamCollectionImportCounts"),
        _required: %w[import item candidates match_confidence counts]
      ),
      # Raw bot_voting_info columns plus the derived voting-window state
      # (VotingInfoResource): `vote_deadline` is the effective end of voting —
      # the `vote_ends_at` override or the default end of the first Sunday
      # at/after `next_vote_at` (US Eastern) — so clients can render
      # countdowns without re-implementing the timezone-sensitive rule.
      VotingInfo: obj(
        round_number: int, nomination_list_id: int(nullable: true), next_vote_at: ts,
        five_day_reminder_sent: bool, one_day_reminder_sent: bool,
        vote_ends_at: ts(nullable: true),
        vote_deadline: ts(nullable: true), voting_open: bool, voting_ended: bool
      ),
      # VotingRoundResource: a round keyed by the round being nominated for,
      # voted on and won, with the server's derived lifecycle state. Nominations
      # close and voting opens at `voting_opens_at`; `phase` is nominating ->
      # voting -> closed -> decided, with a runoff (a member vote on the tied
      # games) after the close when a category tied, and tie (awaiting an
      # admin pick) when the runoff tied again.
      VotingRound: obj(
        round_number: int, month_year: str,
        voting_opens_at: ts, voting_closes_at: ts, closed_at: ts(nullable: true),
        runoff_opens_at: ts(nullable: true), runoff_closes_at: ts(nullable: true),
        runoff_closed_at: ts(nullable: true), decided_at: ts(nullable: true),
        phase: str(enum: VotingRound::PHASES),
        nominations_open: bool, voting_open: bool, voting_ended: bool, runoff_open: bool, runoff_ended: bool,
        pending_ties: {
          type: :object, additionalProperties: array_of("GameSummary"),
          description: "Tied games per category (`gotm`, `nr_gotm`) still awaiting a decision: the runoff's " \
                       "ballot while it is open, then any category the runoff left tied for an admin pick. " \
                       "Empty when none."
        },
        runoff_ties: {
          type: :object, additionalProperties: array_of("GameSummary"),
          description: "The runoff's ballot as it opened: the games each category tied on in the main vote. " \
                       "Empty when the round had no runoff."
        }
      ),
      # VotingEventResource: a queued Discord post for the bot. `payload` holds
      # the ids the post needs (e.g. `winners` / `ties` per category).
      VotingEvent: obj(
        id: int, round_number: int, kind: str(enum: VotingEvent::KINDS), payload: json(nullable: false),
        available_at: ts, expires_at: ts(nullable: true), claimed_until: ts(nullable: true),
        delivered_at: ts(nullable: true), attempts: int
      ),
      # BotJobResource: a bot job's status as the website shows it (no payload).
      BotJob: obj(
        id: int, kind: str(enum: BotJob::KINDS),
        summary: str(maxLength: BotJob::SUMMARY_MAX).merge(
          description: "What the job does, in plain words, set when it was queued. Holds no secrets."
        ),
        status: str(enum: BotJob::STATUSES),
        requested_by_user_id: str(nullable: true).merge(
          description: "The member whose action queued the job; null for system jobs."
        ),
        requested_by: ref("UserSummary", nullable: true),
        attempts: int.merge(description: "Claims so far. A claim not acked within the lease counts too."),
        error_message: str(nullable: true).merge(description: "The bot's error, or the claim-timeout error."),
        result_text: str(nullable: true).merge(description: "What the bot reported when it acked the job done."),
        claimed_at: ts(nullable: true),
        lease_expires_at: ts(nullable: true).merge(
          description: "While claimed: when the claim goes back to the queue unless acked."
        ),
        finished_at: ts(nullable: true), created_at: ts, updated_at: ts
      ),
      # ImageBackfillRunResource: the image backfill's progress (#338).
      ImageBackfillRun: obj(
        id: int,
        status: str(enum: ImageBackfillRun::STATUSES).merge(
          description: "queued, then running, then completed; failed when the run stopped (see last_error)."
        ),
        total: int.merge(description: "Games with no stored images when the run started."),
        done: int.merge(description: "Games whose images were imported."),
        skipped: int.merge(description: "Games with no IGDB id."),
        failed: int.merge(description: "Games whose import failed."),
        started_by_user_id: str(nullable: true).merge(description: "The Superadmin who started it; null for the service."),
        started_at: ts(nullable: true), finished_at: ts(nullable: true),
        last_error: str(nullable: true).merge(description: "The latest failure, per game (\"Game 12: ...\") or for the run."),
        created_at: ts, updated_at: ts
      ),
      # LiveEventResource: a live event and the Discord ids the bot made (#336).
      LiveEvent: obj(
        id: int,
        topic: str(maxLength: LiveEvent::TOPIC_MAX),
        starts_at: ts, ends_at: ts,
        image_url: str(nullable: true).merge(
          description: "The image given as a URL, or the public Backblaze URL of the uploaded image; null for none."
        ),
        status: str(enum: LiveEvent::STATUSES).merge(
          description: "queued, then thread_created once the forum thread exists, then created once the " \
                       "Discord scheduled event exists too; failed when the bot gave up (see its bot job)."
        ),
        discord_thread_id: str(nullable: true).merge(description: "The forum thread, once made."),
        discord_event_id: str(nullable: true).merge(description: "The Discord scheduled event, once made."),
        created_by_user_id: str(nullable: true).merge(description: "The staff member who created it; null for the service."),
        bot_job_id: int(nullable: true).merge(
          description: "Its live_event_create bot job (GET /bot_jobs/:id for the bot's error when failed)."
        ),
        created_at: ts, updated_at: ts
      ),
      # The `say` bot job's payload (#337), as BotJobClaim.payload carries it.
      SayJobPayload: obj(
        _description: "Post `content` in `channel_id`, or reply to `reply_to.message_id` there. Send it with " \
                      "`allowed_mentions` as given: plain user mentions only, never @everyone, @here or roles.",
        channel_id: str.merge(description: "A synced text channel."),
        content: str(maxLength: BotSay::CONTENT_MAX),
        reply_to: obj(channel_id: str, message_id: str).merge(nullable: true,
          description: "The message to reply to (always in `channel_id`); null for a plain message."),
        allowed_mentions: obj(parse: { type: :array, items: str(enum: %w[users]) }, _required: %w[parse])
      ),
      # The News Hub's bot job payloads (#358), as BotJobClaim.payload carries them.
      NewsImagesRenewJobPayload: obj(
        _description: "Kind `news_images_renew`. The feed served a member this News Item with an expired " \
                      "Discord image address. Fetch the message and record it again with " \
                      "`PUT /api/v1/news_items/{message_id}` (fresh addresses and expiry times), or `DELETE` the " \
                      "News Item when the message is gone. At most one is open per message, and none is queued " \
                      "within six hours of the last one for that message ending. Posts nothing.",
        message_id: str.merge(description: "The News Item's Discord message id."),
        channel_id: str.merge(description: "The channel or thread the message is in (the News Channel, or a " \
                                           "News Category's thread for a News Item posted before it)."),
        feature_key: str(enum: %w[news_hub])
      ),
      NewsCatchUpJobPayload: obj(
        _description: "Kind `news_catch_up`. The News Hub's Feature Flag went from Off to Preview or Live: " \
                      "record News Channel messages posted while it was Off and post missing News Copies. " \
                      "The lease is 30 minutes.",
        from_state: str(enum: %w[off]),
        to_state: str(enum: %w[preview live]),
        feature_key: str(enum: %w[news_hub])
      ),
      # A member as Club Codex payloads show them (ClubCodex.member, spec #397).
      CodexMember: obj(
        user_id: str(description: "Their Discord id, which is also their profile's id."),
        name: str(description: "The name they go by now: their Discord display name, else their username " \
          "(their last known one once they have left)."),
        avatar_url: str(description: "Path of their stored avatar (GET /api/v1/users/{id}/avatar, 404 without one).")
      ),
      # What the acting member may do with a Club Codex entry (ClubCodex::Actor).
      CodexEntryViewer: obj(can_edit: bool, can_delete: bool),
      # CodexEntryLinkResource (spec #397, ticket #409): an entry's short link
      # shape, in "See also" links and the entry search.
      CodexEntryLink: obj(
        id: int,
        part: str(enum: CodexEntry::PARTS),
        title: str(description: "The entry's title, or a Fun Fact's opening words (at most " \
          "#{ClubCodex::Links::OPENING_WORDS_MAX} characters, ending in an ellipsis when cut, members " \
          "mentioned as @name).")
      ),
      # CodexEntryResource (spec #397, ticket #404): a Club Codex entry, the
      # same shape for every part; fields a part doesn't use are null.
      CodexEntry: obj(
        id: int,
        part: str(enum: CodexEntry::PARTS, description: "history_event (Club History), lore_entry (Club Lore) " \
          "or fun_fact."),
        title: str(nullable: true, maxLength: CodexEntry::TITLE_MAX,
          description: "History Events and Lore Entries; null for a Fun Fact."),
        rich_body: { type: :array, items: { type: :object, additionalProperties: true }, nullable: true,
                     description: "The Plate.js story of a Lore Entry or description of a History Event, as the " \
                                  "website saved it (never checked by the API); null for a Fun Fact." },
        body: str(nullable: true, description: "The Discord-readable text, members mentioned as `<@discord_id>` " \
          "tokens: a Fun Fact itself (up to #{CodexEntry::FUN_FACT_MAX} characters, tokens included), or the " \
          "Discord markdown the website made from `rich_body`. Show each token as its member in `mentions`; a " \
          "token not there names no known member and stays as text."),
        occurred_on: date(nullable: true, description: "When it happened, at `date_precision`: a month is its " \
          "first day, a year 1 January. Null for a Fun Fact and an undated Lore Entry."),
        date_precision: str(nullable: true, enum: [ *CodexEntry::DATE_PRECISIONS, nil ],
          description: "day, month or year; null with `occurred_on`."),
        kind: str(nullable: true, enum: [ *CodexEntry::KINDS, nil ],
          description: "The History Event Kind; null for other parts."),
        author: ref("CodexMember"),
        mentions: { type: :object, additionalProperties: ref("CodexMember"),
                    description: "Each known member `body` mentions, keyed by Discord id, as they are now." },
        images: { type: :array, items: obj(id: int, url: str, position: int),
                  description: "The entry's gallery, by position (History Events and Lore Entries)." },
        links: { type: :array, items: ref("CodexEntryLink"),
                 description: "Its \"See also\" entries, oldest first, as the caller may read them: a Visitor " \
                              "sees only History Events." },
        viewer: ref("CodexEntryViewer"),
        created_at: ts, updated_at: ts,
        _required: %w[id part title rich_body body occurred_on date_precision kind author mentions images links
                      viewer created_at updated_at]
      ),
      # ChallengeResource (spec #376, ticket #377): a Challenge with its
      # Challenge Format's settings under the Format's key.
      Challenge: obj(
        id: int, name: str(maxLength: Challenge::NAME_MAX), description: str,
        challenge_format: str(enum: Challenge::FORMATS),
        hosted_by_club: bool.merge(description: "True when the club itself is the Host (host is null)."),
        host: ref("ChallengeMember", nullable: true).merge(
          description: "The member who is the Host; null for a club-hosted Challenge."),
        schedule: str(enum: Challenge::SCHEDULES),
        ends_on: str(nullable: true, format: "date").merge(
          description: "An Always Open Challenge's last Open day, in the club's time zone; null for none."
        ),
        season: obj(
          start: str(example: "06-21"), end: str(example: "09-22"),
          crosses_new_year: bool.merge(description: "True when the Season runs across 1 January.")
        ).merge(nullable: true, description: "A Seasonal Challenge's Season, as MM-DD; null when Always Open."),
        open: bool.merge(description: "Open today in the club's time zone (America/New_York)."),
        pool: ref("ChallengePool", nullable: true),
        slots: ref("ChallengeSlots", nullable: true),
        assignment: ref("ChallengeAssignment", nullable: true),
        run_count: int.merge(description: "Every Run of it, whatever its status."),
        finished_count: int.merge(description: "Its Runs that Finished, in any Season."),
        pool_games: { type: :array, maxItems: 4, items: ref("ChallengePostGame"),
                      description: "Up to 4 games of a Pool Challenge's Pool for its flyer, those with a cover " \
                                   "first, then by title (empty for Slots and Assignment)." },
        tint: ref("ChallengeTint"),
        key_art_url: str(nullable: true).merge(
          description: "The picture behind the Challenge's banner and on its posts: for a Pool Challenge, the " \
                       "artwork of the first Pool game by title that has artwork, else the first one's cover; null " \
                       "without either, and for Slots and Assignment Challenges (draw the Format's picture in the " \
                       "tint instead). Show and announcements only; null in lists."
        ),
        hidden: bool.merge(description: "Hidden by a Moderator: listed only for Moderators and above and the Host."),
        ended_at: ts(nullable: true).merge(
          description: "When an Always Open Challenge reached its end date and Closed for good (set the day after " \
                       "ends_on); its schedule and end date can no longer change. Null otherwise."
        ),
        created_by: str(nullable: true), updated_by: str(nullable: true), created_at: ts, updated_at: ts
      ),
      ChallengeTint: obj(
        _description: "The Challenge tint: the one colour it wears on the bot's posts and the website, as a pair " \
                      "of lowercase #rrggbb. A new Challenge gets a curated tint (Secret Santa's holly for an " \
                      "Assignment Challenge, otherwise the other seven in turn); the Host or a Moderator may " \
                      "change it. Curated: #{Challenges::Tint::CURATED.map { |name, pair| "#{name} #{pair.fill} / #{pair.hi}" }.join(', ')}.",
        _required: %w[fill hi],
        fill: str(example: "#1f6b67").merge(description: "The flyer and banner ground. Paper type (#f4f4f0) on it " \
                                                          "clears 4.5:1; set only paper type on it."),
        hi: str(example: "#6fd6cc").merge(description: "The same hue lifted for type and marks on ink (#0b0b0d, " \
                                                       "#141417), where it clears 4.5:1.")
      ),
      ChallengePool: obj(
        _description: "A Pool Challenge's settings. A game is in the Pool if it belongs to a chosen franchise or " \
                      "collection and is not excluded, or if it is included by hand; it is resolved against the " \
                      "GameDB when read.",
        target: { oneOf: [ { type: :integer, minimum: 1 }, { type: :string, enum: %w[all] } ],
                  description: "Cleared games needed to Finish, or \"all\" for every game in the Pool." },
        franchises: { type: :array, items: obj(franchise_id: int, name: str) },
        collections: { type: :array, items: obj(collection_id: int, name: str) },
        included_games: { type: :array, items: obj(game_id: int, title: str) },
        excluded_games: { type: :array, items: obj(game_id: int, title: str) },
        game_count: int(nullable: true).merge(description: "Games in the Pool now. Show and announcements only.")
      ),
      ChallengeSlots: obj(
        _description: "A Slots Challenge's range: one slot per release year (ticket #381).",
        first_year: { oneOf: [ { type: :integer }, { type: :string, enum: %w[birth_year] } ],
                      description: "A fixed year, or \"birth_year\" for each member's birth year." },
        last_year: { oneOf: [ { type: :integer }, { type: :string, enum: %w[current_year] } ],
                     description: "A fixed year, or \"current_year\": the range gains a slot every 1 January." },
        counts_past_play: bool.merge(description: "Counts past play (ticket #382, Always Open only): members may " \
                                                  "pick Game Completions dated before their Run started for open slots.")
      ),
      ChallengeAssignment: obj(
        _description: "An Assignment (Secret Santa) Challenge's Edition calendar, as MM-DD, coming in this order " \
                      "through the year (ticket #383). Defaults: 12-01, 12-15, 12-25.",
        signup_cutoff: str(example: "12-01").merge(description: "Sign-up closes at the start of this day, and the " \
                                                                 "draw happens."),
        pick_deadline: str(example: "12-15").merge(description: "Santas pick before this day."),
        reveal: str(example: "12-25").merge(description: "The picks are revealed, and the Edition is named by " \
                                                          "this day's year."),
        edition: ref("ChallengeEditionSummary", nullable: true).merge(
          description: "The latest Edition; null before the first one opens."
        )
      ),
      # ChallengeEditionResource.summary (ticket #383).
      ChallengeEditionSummary: obj(
        _description: "An Edition's year, phase and dates, as the club's dates (America/New_York).",
        id: int, year: int.merge(description: "The year of its reveal."),
        phase: str(enum: ChallengeEdition::PHASES),
        signup_opens_on: str(format: "date").merge(description: "The day after the previous reveal, or the day " \
                                                                 "the Challenge was created."),
        signup_cutoff_on: str(format: "date").merge(description: "Sign-up is open until the start of this day."),
        pick_deadline_on: str(format: "date"), reveal_on: str(format: "date"),
        ends_on: str(format: "date").merge(description: "The next reveal date: the year to Clear the game ends.")
      ),
      # ChallengeEditionResource (spec #376, tickets #383, #384): an Edition
      # with the members signed up and, from the reveal, the assignments.
      ChallengeEdition: obj(
        id: int, year: int, phase: str(enum: ChallengeEdition::PHASES),
        challenge: obj(id: int, name: str),
        signup_opens_on: str(format: "date"), signup_cutoff_on: str(format: "date"),
        pick_deadline_on: str(format: "date"), reveal_on: str(format: "date"), ends_on: str(format: "date"),
        signup_open: bool.merge(description: "Members may sign up and withdraw today."),
        signed_up_count: int,
        signed_up: bool.merge(description: "The member reading is signed up (false for the bot without " \
                                           "acting_user_id, and in bot job payloads)."),
        members: { type: :array, description: "The members signed up, first first.", items: obj(
          user_id: str, username: str, global_name: str(nullable: true),
          discord_avatar: str(nullable: true), avatar_url: str,
          left_out: bool.merge(description: "The draw left them out: fewer than 5 games in their backlog by then."),
          withdrawn: bool.merge(description: "They withdrew after the draw; their recipient gets a random pick."),
          picked: bool(nullable: true).merge(description: "While Santas pick: a game is picked for them (their " \
                                                          "Santa's pick, kept when the Santa withdraws, or the " \
                                                          "random pick at the deadline). Null in other phases and " \
                                                          "for members the draw left out. Never names the Santa " \
                                                          "or the game.")
        ) },
        picked_count: int(nullable: true).merge(description: "While Santas pick: how many members have a game " \
                                                             "picked for them. Null in other phases."),
        drawn_at: ts(nullable: true).merge(description: "When the draw happened (or cancelled the Edition)."),
        assignments: {
          type: :array, nullable: true,
          description: "Who gives what to whom, by recipient: served from the reveal on, and to staff (Moderators " \
                       "and above) from the draw on; null otherwise.",
          items: obj(
            _required: %w[recipient picked_randomly],
            recipient: ref("ChallengeMember"),
            game: ref("GameSummary", nullable: true).merge(description: "The game picked; null while nothing " \
                                                                         "is, and before the reveal on the " \
                                                                         "reader's own row."),
            picked_randomly: bool(nullable: true).merge(description: "A random pick at the deadline: the Santa " \
                                                                     "didn't pick, withdrew or left the server. " \
                                                                     "Null while the game is hidden."),
            santa: ref("ChallengeMember", nullable: true).merge(description: "Null before the Edition ends, " \
                                                                             "except to staff the draw didn't " \
                                                                             "give a Santa in it."),
            run: obj(id: int, status: str(enum: ChallengeRun::STATUSES), progress: json(nullable: false))
              .merge(nullable: true, description: "The recipient's Run of the Edition.")
          )
        },
        picks_closed_at: ts(nullable: true).merge(description: "When the random picks were made at the deadline."),
        viewer: obj(
          _required: %w[backlog_count eligible],
          backlog_count: int.merge(description: "Games in the member's backlog."),
          eligible: bool.merge(description: "backlog_count meets the 5-game minimum to sign up.")
        ).merge(nullable: true, description: "The member reading. Null for the bot without acting_user_id, and " \
                                             "in bot job payloads.")
      ),
      # GameListResource (spec api#442, ticket api#446): a Game List. A
      # single list (show, and every write that returns one) adds `entries`.
      GameList: obj(
        id: int, name: str(maxLength: GameList::NAME_MAX),
        description: str(nullable: true, maxLength: GameList::DESCRIPTION_MAX),
        visibility: str(enum: GameList::VISIBILITIES, description: "members (any member reads it) or private " \
          "(only its owner, never staff). A club list is always members."),
        sort: str(enum: GameList::SORTS, description: "How its games are shown: ranked (by `position`), " \
          "alphabetical (by title) or added (newest first)."),
        club: bool.merge(description: "True when the club owns it (owner is null)."),
        owner: ref("ChallengeMember", nullable: true).merge(description: "The member who owns it; null for a club list."),
        taken_over_from: ref("ChallengeMember", nullable: true).merge(
          description: "The member the club took this list over from; null unless taken over."),
        taken_over_at: ts(nullable: true),
        entry_count: int,
        preview_games: { type: :array, maxItems: GameLists::Overview::PREVIEW_MAX,
                         items: obj(game_id: int, title: str, cover_url: str(nullable: true)),
                         description: "Its first games in its own sort's order, for covers." },
        viewer: ref("GameListViewer"),
        entries: { type: :array, items: ref("GameListEntry"),
                   description: "A single list only: every game, in its sort's order." },
        created_at: ts, updated_at: ts,
        _required: %w[id name description visibility sort club owner taken_over_from taken_over_at entry_count
                      preview_games viewer created_at updated_at]
      ),
      # What the caller may do with a Game List (GameLists::Actor).
      GameListViewer: obj(can_edit: bool, can_delete: bool),
      # GameListEntryResource (spec api#442, ticket api#446): a game in a list.
      GameListEntry: obj(
        game_id: int,
        position: int.merge(description: "Its place in the ranked order, from 1, whatever the list's sort."),
        note: str(nullable: true, maxLength: GameListEntry::NOTE_MAX),
        added_at: ts,
        game: ref("GameSummary"),
        _required: %w[game_id position note added_at game]
      ),
      ChallengeMember: obj(
        user_id: str, username: str, global_name: str(nullable: true),
        discord_avatar: str(nullable: true).merge(
          description: "The member's Discord avatar hash from their last website login; null if unknown. " \
                       "https://cdn.discordapp.com/avatars/{user_id}/{discord_avatar}.png"
        ),
        avatar_url: str(example: "/api/v1/users/123/avatar").merge(
          description: "The API path of the avatar image the bot stores (404 when it has none)."
        )
      ),
      # GET /api/v1/challenge_editions/{id}/santa (ticket #384).
      ChallengeSanta: obj(
        _description: "The acting member's side as a Santa.",
        edition_id: int, year: int,
        challenge: obj(id: int, name: str),
        reveal_on: str(format: "date").merge(description: "The picks are revealed on this day."),
        recipient: ref("ChallengeMember"),
        taste: obj(
          genres: { type: :array, maxItems: 3, items: obj(genre_id: int, name: str),
                    description: "The recipient's top 3 genres, most played first." },
          platform: obj(platform_id: int, platform_name: str, platform_abbreviation: str(nullable: true))
            .merge(nullable: true, description: "The platform the recipient plays most on; null if none recorded.")
        ).merge(description: "Taste hints about the recipient, worked out from the games in their Game " \
                             "Completions and backlog (each game counted once)."),
        pick: obj(game: ref("GameSummary"), picked_at: ts, picked_randomly: bool)
          .merge(nullable: true, description: "The game picked for the recipient; null while nothing is."),
        pick_deadline_on: str(format: "date").merge(description: "Picks are open until the start of this day."),
        picks_open: bool,
        backlog: { type: :array, items: { allOf: [ ref("BacklogEntry"), obj(
                     hours: num(nullable: true).merge(description: "The HowLongToBeat time backlog#pick compares " \
                                                                   "(main, single player, main + sides); null without."),
                     hltb: ref("Hltb", nullable: true)
                   ) ] },
                   description: "The recipient's backlog minus the games they have Cleared (any Game Completion), " \
                                "narrowed by `q`." }
      ),
      # ChallengeRunResource (spec #376, ticket #378): a Run with its progress.
      ChallengeRun: obj(
        id: int,
        challenge: obj(id: int, name: str, challenge_format: str(enum: Challenge::FORMATS),
          schedule: str(enum: Challenge::SCHEDULES),
          counts_past_play: bool.merge(description: "Counts past play is on (Slots only; false otherwise)."),
          tint: ref("ChallengeTint"),
          slots: ref("ChallengeSlots", nullable: true).merge(description: "Slots only: the Challenge's range " \
                                                                          "and Counts past play.")),
        user: ref("ChallengeMember"),
        edition: obj(id: int, year: int).merge(nullable: true,
          description: "Assignment only: the Edition the Run was drawn in."),
        assignment: obj(
          game: ref("GameSummary", nullable: true).merge(description: "The game picked for the member: null " \
                                                                       "before the reveal (except to staff, " \
                                                                       "on Runs not their own)."),
          picked_randomly: bool(nullable: true).merge(description: "Null until the game is shown."),
          santa: ref("ChallengeMember", nullable: true).merge(description: "Null before the Edition ends, " \
                                                                           "except to staff the draw didn't " \
                                                                           "give a Santa in it.")
        ).merge(nullable: true, description: "Assignment only: the member's assigned game and their Santa."),
        status: str(enum: ChallengeRun::STATUSES),
        started_at: ts,
        ended_at: ts(nullable: true).merge(description: "When it became Finished, Expired or Abandoned."),
        window: obj(
          starts_on: str(format: "date"),
          ends_on: str(nullable: true, format: "date").merge(description: "Null while it has no end.")
        ).merge(description: "When play counts toward the Run, as the club's dates (both included): the Season " \
                             "it belongs to, from its start to an Always Open Challenge's end date, or an " \
                             "Edition's reveal to the day before its end."),
        progress: obj(
          _required: %w[in_progress cleared target],
          in_progress: int.merge(description: "Games In Progress: in the member's Now Playing."),
          cleared: int.merge(description: "Games Cleared by a Game Completion dated inside the window; for " \
                                           "Slots, the slots filled."),
          target: int.merge(description: "Cleared games needed to Finish; for Slots, the Run's slots so far."),
          caught_up: bool.merge(description: "Slots only (absent otherwise): an Active Run whose range ends at " \
                                             "the current year, with every slot so far Cleared. Worked out " \
                                             "when read, so it lapses on 1 January.")
        ),
        entries: { type: :array, description: "The games counted on the Run, Cleared first.", items: obj(
          game_id: int, title: str,
          cover_url: str(nullable: true).merge(description: "The game's cover, null when it has none."),
          state: str(enum: ChallengeRunEntry::STATES),
          cleared_on: str(nullable: true, format: "date"),
          completion_id: int(nullable: true).merge(
            description: "The Game Completion that Cleared it; null on a Finished Run after it was deleted."
          ),
          slot_year: int(nullable: true).merge(description: "Slots: the year this Cleared game fills; null " \
                                                           "when In Progress, waiting for an open year, or not Slots."),
          picked_by_hand: bool.merge(description: "The member placed it there themselves (a slot move or a " \
                                                  "past-play pick)."),
          release_years: { type: :array, items: { type: :integer }, nullable: true,
                           description: "Slots only (null otherwise): every year the game fits, its first " \
                                        "release year and the year of each regional or platform release, " \
                                        "oldest first; intersect with the Run's open years." }
        ) },
        slots: obj(
          first_year: int.merge(description: "Copied when the Run started; kept if the Birth Date changes."),
          last_year: int.merge(description: "The last year so far: the current year for a range that grows."),
          growing: bool.merge(description: "The range ends at the current year and gains a slot every 1 January."),
          years: { type: :array, items: obj(year: int, game_id: int(nullable: true), title: str(nullable: true)) }
        ).merge(nullable: true, description: "Slots only: each year so far and the game filling it (null while open).")
      ),
      # Challenges::Activity (spec api#421, ticket api#424): one event of the
      # club-wide Challenge Activity feed.
      ChallengeActivityEvent: obj(
        _required: %w[kind occurred_on challenge],
        kind: str(enum: Challenges::Activity::KINDS).merge(
          description: "run_started: a Run started (an Assignment Run: at the draw). game_cleared: a game " \
                       "Cleared on a Run, with `game`. run_finished: a Run Finished. signups_opened: an " \
                       "Edition's sign-up opened. edition_revealed: an Edition's picks were revealed."
        ),
        occurred_on: date.merge(description: "The club date it happened on."),
        occurred_at: ts(nullable: true).merge(description: "When it happened; null for game_cleared, " \
                                                          "signups_opened and edition_revealed, which are " \
                                                          "known only by their date."),
        challenge: obj(id: int, name: str, challenge_format: str(enum: Challenge::FORMATS),
          tint: ref("ChallengeTint")),
        user: ref("ChallengeMember", nullable: true).merge(description: "The Run's member; null for Edition " \
                                                                        "events."),
        game: ref("GameSummary", nullable: true).merge(description: "game_cleared only: the game Cleared."),
        run_id: int(nullable: true).merge(description: "The Run's id; null for Edition events."),
        edition: obj(id: int, year: int).merge(nullable: true, description: "The Edition: for Edition events " \
                                                                            "and Assignment Runs.")
      ),
      ChallengePoolGameProgress: obj(
        _description: "A Pool game with who Cleared it and who has it In Progress.",
        game_id: int, title: str, initial_release_date: ts(nullable: true),
        cover_url: str(nullable: true).merge(description: "The game's cover, null when it has none."),
        cleared_by: { type: :array, description: "Members who Cleared it, earliest first.", items: {
          allOf: [ ref("ChallengeMember"), obj(run_id: int, cleared_on: str(nullable: true, format: "date")) ]
        } },
        in_progress: { type: :array, description: "Members playing it on a Run that still counts play.", items: {
          allOf: [ ref("ChallengeMember"), obj(run_id: int) ]
        } }
      ),
      ChallengeOpenSignup: obj(
        _description: "A member's sign-up for an Edition still in sign-up (no Run until the draw).",
        edition_id: int, year: int, phase: str(enum: %w[signup]),
        challenge: obj(id: int, name: str),
        signed_up_at: ts,
        signup_cutoff_on: str(format: "date").merge(description: "Sign-up closes at the start of this day, and " \
                                                                 "the draw happens on it."),
        pick_deadline_on: str(format: "date"), reveal_on: str(format: "date")
      ),
      ChallengeWarning: obj(
        code: str(enum: %w[duplicate_name]), message: str,
        challenge_ids: { type: :array, items: int, description: "The other Challenges with the same name." }
      ),
      ChallengePoolSource: obj(
        kind: str(enum: %w[franchise collection]), id: int.merge(description: "franchise_id or collection_id."),
        name: str, game_count: int
      ),
      # The Challenges bot job payload (#377), as BotJobClaim.payload carries it.
      ChallengeAnnounceJobPayload: obj(
        _description: "Kind `challenge_announce`. Post in the #challenges channel, or the staff test channel " \
                      "while the Feature is in Preview. `event` says what to announce: `challenge_created`, " \
                      "a new Challenge; `run_finished`, a member's Run that just Finished, or `run_caught_up`, a " \
                      "member's Slots Run that just became Caught Up (at most once a year), both with `run`; or " \
                      "`season_opened`, a Seasonal Challenge's Season that just opened (with `season`). An " \
                      "Edition's sign-up: `signup_opened`; `signup_closing` (with `days_left`); and at the draw, " \
                      "`signup_closed`, or `edition_cancelled` when fewer than 2 members could be drawn (both " \
                      "with `joined` and `left_out`), all with `edition`; and `edition_revealed` on the reveal " \
                      "date, whose `edition` carries every assignment (never the Santas).",
        _required: %w[event challenge feature_key],
        event: str(enum: %w[challenge_created run_finished run_caught_up season_opened signup_opened signup_closing
          signup_closed edition_cancelled edition_revealed]),
        challenge: ref("Challenge"),
        run: ref("ChallengeRun").merge(description: "run_finished and run_caught_up only: the Run as GET /api/v1/challenge_runs/{id} serves it."),
        season: ref("ChallengeSeasonDates").merge(description: "season_opened only: the Season that opened."),
        pool_games: { type: :array, maxItems: 10, items: ref("ChallengePostGame"),
                      description: "challenge_created and season_opened only: up to 10 games of a Pool " \
                                   "Challenge's Pool for a cover wall, those with a cover first, then by title " \
                                   "(empty for Slots and Assignment)." },
        last_season_finishers: { type: :array, items: ref("ChallengeMember"),
                                 description: "season_opened only: the members whose Run of the Season before " \
                                              "Finished, in the order they Finished (show their names; no pings)." },
        edition: ref("ChallengeEdition").merge(description: "Edition events only: the Edition as GET " \
                                                             "/api/v1/challenge_editions/{id} serves it."),
        days_left: int.merge(example: 3, description: "signup_closing only: days from today to the cutoff."),
        signup_post: obj(channel_id: str, message_id: str).merge(
          nullable: true, description: "signup_closing, signup_closed, edition_cancelled and edition_revealed only: " \
                                       "the Edition's sign-up opening post, as the bot stored it (PUT " \
                                       "/api/v1/challenge_editions/{id}/signup_post), to reply to; null if none."
        ),
        joined: int.merge(description: "signup_closed and edition_cancelled only: the members drawn."),
        left_out: int.merge(description: "signup_closed and edition_cancelled only: the members left out for " \
                                         "having fewer than `minimum` games in their backlog."),
        minimum: int.merge(example: 5, description: "signup_closed and edition_cancelled only: the backlog " \
                                                    "minimum to be drawn."),
        feature_key: str(enum: %w[challenges])
      ),
      ChallengePostGame: obj(
        game_id: int, title: str,
        cover_url: str(nullable: true).merge(description: "The game's cover, null when it has none.")
      ),
      ChallengeSeasonDates: obj(
        starts_on: str(format: "date", example: "2026-06-21"), ends_on: str(format: "date", example: "2026-09-22"),
        _description: "One Season's first and last day, as the club's dates (America/New_York), both included."
      ),
      # The Challenge DM bot job payload (#379), as BotJobClaim.payload carries it.
      ChallengeDmJobPayload: obj(
        _description: "Kind `challenge_dm`. DM the member `user_id`; post nothing publicly. `event` says what " \
                      "about: `season_ending`, a reminder that the Season of the member's unFinished Run ends " \
                      "soon (with `run`, `season` and `days_left`), sent only to members who keep Challenge DMs " \
                      "on; `left_out_of_draw`, the draw left the member out of an Edition they signed up for " \
                      "(with `edition`, `backlog_count` and `minimum`), sent to every member still in the server; " \
                      "`pick_reminder`, 2 days before an Edition's pick deadline, a Santa who hasn't picked for " \
                      "their `recipient` (with `edition` and `days_left`), sent only to members who keep Challenge " \
                      "DMs on.",
        _required: %w[event user_id challenge feature_key],
        event: str(enum: %w[season_ending left_out_of_draw pick_reminder]),
        user_id: str.merge(description: "The member to DM."),
        challenge: ref("Challenge"),
        run: ref("ChallengeRun").merge(description: "season_ending only: the member's Run, as GET " \
                                                     "/api/v1/challenge_runs/{id} serves it."),
        season: ref("ChallengeSeasonDates").merge(description: "season_ending only."),
        days_left: int.merge(example: 7, description: "season_ending: days from today to the Season's last day " \
                                                      "(7 unless sent late); pick_reminder: days to the pick " \
                                                      "deadline (2 unless sent late)."),
        edition: ref("ChallengeEdition").merge(description: "left_out_of_draw and pick_reminder: the Edition."),
        recipient: ref("ChallengeMember").merge(description: "pick_reminder only: the member the Santa picks for."),
        backlog_count: int.merge(description: "left_out_of_draw only: the games in the member's backlog."),
        minimum: int.merge(example: 5, description: "left_out_of_draw only: the backlog minimum."),
        feature_key: str(enum: %w[challenges])
      ),
      # The Daily Fun Fact bot job payload (#406), as BotJobClaim.payload carries it.
      DailyFunFactJobPayload: obj(
        _description: "Kind `daily_fun_fact`. Post the Fun Fact `entry_id` (GET /api/v1/codex/fun_facts/{id}) " \
                      "in general chat, or the staff test channel while the Club Codex is in Preview, with no " \
                      "pings. Queued once per club day at 15:00 America/New_York. Drop it, acked done, when " \
                      "`club_date` is no longer today in New York or the Fun Fact has been deleted (404).",
        _required: %w[club_date entry_id feature_key],
        club_date: str(format: "date", example: "2026-11-18").merge(description: "The club day it is for."),
        entry_id: int.merge(description: "The Fun Fact drawn for the day; the queue already counts it shown."),
        feature_key: str(enum: %w[club_codex])
      ),
      # The Birthday Post bot job payload (#401), as BotJobClaim.payload carries it.
      BirthdayPostJobPayload: obj(
        _description: "Kind `birthday_post`. Post one Birthday Post in `channel_id` greeting every member in " \
                      "`user_ids`, @mentioning each so they are pinged. Queued at 10:00 America/New_York, only " \
                      "on a day with Birthdays. If `club_date` is no longer today in New York, ack it done " \
                      "without posting. Right before posting, re-read GET /api/v1/birthdays/upcoming and greet " \
                      "only the `user_ids` listed there with `today: true`, so a member who stopped sharing or " \
                      "left since it was queued isn't pinged. Birthdays are not a Feature: no `feature_key`, " \
                      "and no Feature Flag routes it.",
        _required: %w[club_date user_ids channel_id],
        club_date: str(format: "date", example: "2026-05-04").merge(
          description: "The club day (America/New_York) whose Birthdays these are."
        ),
        user_ids: { type: :array, minItems: 1, items: str,
                    description: "The members to greet, by display name: Discord user ids, still in the server, " \
                                 "sharing their Birthday. No year or age is sent." },
        channel_id: str(example: "191941851757019136",
          description: "The Discord channel to post in: general chat (the API's DiscordChannels::GENERAL).")
      ),
      # BotJobClaimResource: a claimed bot job as the bot receives it.
      BotJobClaim: obj(
        id: int, kind: str(enum: BotJob::KINDS), summary: str(maxLength: BotJob::SUMMARY_MAX),
        payload: json(nullable: false).merge(
          description: "Per kind; a breaking change gets a new kind name. A kind that posts publicly also " \
                       "carries `feature_key`, the key of the Feature that owns the post " \
                       "(BotJob::PUBLIC_POST_FEATURES), so the bot can route it by that Feature's Flag. A kind " \
                       "that does a Feature's work without posting carries it too (BotJob::FEATURE_WORK). " \
                       "birthday_post is a public post no Feature owns and carries none. " \
                       "Documented payloads: SayJobPayload, NewsImagesRenewJobPayload, NewsCatchUpJobPayload, " \
                       "ChallengeAnnounceJobPayload, ChallengeDmJobPayload, DailyFunFactJobPayload, " \
                       "BirthdayPostJobPayload."
        ),
        status: str(enum: BotJob::STATUSES), requested_by_user_id: str(nullable: true), attempts: int,
        error_message: str(nullable: true), result_text: str(nullable: true), claimed_at: ts(nullable: true),
        lease_expires_at: ts(nullable: true).merge(
          description: "Ack before this or the job is handed out again: five minutes unless the kind has a longer lease."
        ),
        finished_at: ts(nullable: true), created_at: ts, updated_at: ts
      ),
      # AchievementHighlightResource: an announceable Unlock as the bot posts
      # it, with the www set page path.
      AchievementHighlight: obj(
        id: int, highlight: str(enum: UserAchievementUnlock::HIGHLIGHTS), hardcore: bool,
        unlocked_at: ts.merge(description: "The Highlight's date: a Mastery's hardcore time, otherwise the Unlock time."),
        user_id: str, display_name: str,
        url_path: str.merge(description: "The www set page path: /members/{user_id}/achievements/{set_id}."),
        achievement: obj(
          id: int, name: str(nullable: true), description: str(nullable: true), icon_url: str(nullable: true),
          tier: str(enum: Achievement::TIERS, nullable: true), points: int(nullable: true),
          rarity: num(nullable: true),
          hidden: bool.merge(description: "A hidden Achievement: mask its name and description when posting."),
          _required: %w[id name description icon_url tier points rarity hidden]
        ),
        achievement_set: obj(
          id: int, title: str(nullable: true), provider: str(enum: UserLinkedAccount::PROVIDERS),
          platform_label: str(nullable: true), icon_url: str(nullable: true)
        ),
        _required: %w[id highlight hardcore unlocked_at user_id display_name url_path achievement achievement_set]
      ),
      # Achievements::HighlightOutbox.alerts: the PSN auth alert. Post it while
      # `psn_auth_expired_at` is set and `psn_auth_alerted` is false, then ack.
      AchievementHubAlerts: obj(
        psn_auth_expired_at: ts(nullable: true), psn_auth_alerted: bool,
        _required: %w[psn_auth_expired_at psn_auth_alerted]
      ),
      PublicReminder: obj(
        reminder_id: int, channel_id: str, message: str, due_at: ts,
        recur_every: int(nullable: true), recur_unit: str(nullable: true), enabled: bool,
        created_by: str(nullable: true), created_at: ts, updated_at: ts
      ),
      RssFeed: obj(
        feed_id: int, feed_name: str(nullable: true), feed_url: str, channel_id: str,
        include_keywords: str(nullable: true), exclude_keywords: str(nullable: true),
        created_at: ts, updated_at: ts
      ),
      # GameKeyResource. `key_value` (the secret) is omitted from list responses;
      # it is rendered only in the response to a successful claim, to the
      # restricted single-key GET, and to the claimer's own claimed-keys list.
      GameKey: obj(
        key_id: int, game_title: str, platform: str,
        region: str(enum: RpgClubGameKey::REGIONS, description: "Where the key redeems. Defaults to Global."),
        gamedb_game_id: int(nullable: true),
        donor_user_id: str, claimed_by_user_id: str(nullable: true), claimed_at: ts(nullable: true),
        donor_notify_on_claim: bool, created_at: ts, updated_at: ts,
        key_value: str(nullable: true).merge(description: "The key secret. Present only in the response to a successful claim, to GET /api/v1/game_keys/{id}, and to the claimer reading their own GET /api/v1/users/{user_id}/claimed_game_keys."),
        game: ref("GameSummary", nullable: true)
      ),
      # CompletionsController#create meta: the queued announce bot job, so the
      # website can poll GET /api/v1/bot_jobs/{id}.
      CompletionCreateMeta: obj(
        announce_job_id: int(nullable: true).merge(
          description: "The completion_announce bot job. Null when `announce` was not set."
        )
      ),
      # GotmRoundWrites (round create, entry update) meta: the queued
      # gotm_cache_reload bot job, so the website can poll GET /api/v1/bot_jobs/{id}.
      GotmReloadMeta: obj(
        reload_job_id: int(nullable: true).merge(
          description: "The gotm_cache_reload bot job. Null when none was queued (the service's own entry edits)."
        )
      ),
      # NominationsController single-user delete: `deleted` plus the queued
      # nomination_deleted bot job, so the website can poll GET /api/v1/bot_jobs/{id}.
      NominationDeletedResponse: obj(
        deleted: { type: :boolean, example: true },
        meta: obj(
          announce_job_id: int(nullable: true).merge(
            description: "The nomination_deleted bot job. Null when none was queued (owner and service deletes)."
          )
        ),
        _required: %w[deleted meta]
      ),
      # GameKeysController#claim meta: the queued claim notice bot job, so the
      # website can poll GET /api/v1/bot_jobs/{id}.
      GameKeyClaimMeta: obj(
        claim_notice_job_id: int(nullable: true).merge(
          description: "The giveaway_claim_notice bot job (DM the key, log the claim, notify the donor). " \
                       "Null when the bot service token claimed, since the bot does that work itself."
        )
      ),
      # GiveawaySettingsController. The donor's notify-on-claim preference,
      # derived from rpg_club_users.donor_notify_on_claim.
      GiveawaySettings: obj(user_id: str, notify_on_claim: bool),
      # FeaturePreferencesController (spec #347, ticket #352). A member's
      # Feature Preferences: the hideable Features they hid from their own view
      # of the website, and (staff only) the show-Preview setting.
      FeaturePreference: obj(
        key: str(example: "reviews"),
        name: str(example: "Reviews"),
        state: str(enum: %w[preview live], description: "The Feature Flag state. Preview only reaches staff."),
        preview: bool.merge(description: "True when the viewer can use it only because they are staff (Preview)."),
        hidden: bool.merge(description: "The member hid this Feature from their view of the website."),
        website: { type: :array, items: str, description: "Where the Feature shows up on the website." },
        _required: %w[key name state preview hidden website]
      ),
      FeaturePreferences: obj(
        user_id: str,
        hidden: { type: :array, items: str,
                  description: "Every Feature key the member hid, in registry order, including ones whose " \
                               "Feature Flag currently hides them (a preference survives any flag change)." },
        show_preview_features: bool(nullable: true).merge(
          description: "Staff only: show Preview Features on the website (on by default). Null for anyone " \
                       "who is not an Admin or Superadmin."
        ),
        features: array_of("FeaturePreference").merge(
          description: "The Features the member may hide, in registry order: every hideable Feature they can " \
                       "use (Live, plus Preview for staff). Empty when there is none, e.g. no hideable Feature is Live."
        ),
        _required: %w[user_id hidden show_preview_features features]
      ),

      # PinnedPagesController (spec api#416, tickets api#418, api#419). A
      # member's Pinned Pages: the ones they can see right now, in their order,
      # and whether they saved their own list.
      PinnedPages: obj(
        user_id: str,
        pages: { type: :array, items: str(example: "voting"),
                 description: "Pinned Page keys the member can see right now, in their order: the club default " \
                              "(voting, games, members, news) until they save their own list. Keys: voting, " \
                              "gotm_history, challenges, games, reviews, releases, achievements, journals, members, news, " \
                              "codex, giveaways, suggestions, staff_desk, voting_console, synonyms, live_events, " \
                              "public_reminders, suggestion_review." },
        customised: bool.merge(description: "Whether the member saved their own list. False while they follow " \
                                            "the club default, which then reaches them when it changes."),
        _required: %w[user_id pages customised]
      ),

      # DashboardPanelsController (spec api#421, ticket api#422). A member's
      # Dashboard Panels: the ones they show and can see right now, in their
      # order; every panel they can see; and whether they saved their own list.
      DashboardPanels: obj(
        user_id: str,
        panels: { type: :array, items: str(example: "news"),
                  description: "Dashboard Panel keys the member shows and can see right now, in their order: the " \
                               "club default (news, now_playing_club, releases, achievements_club, " \
                               "challenges_club) until they save their own list." },
        catalogue: { type: :array, items: { "$ref" => "#/components/schemas/DashboardPanel" },
                     description: "Every panel the member can see right now, shown or not, in the club's order." },
        customised: bool.merge(description: "Whether the member saved their own list. False while they follow " \
                                            "the club default, which then reaches them when it changes."),
        _required: %w[user_id panels catalogue customised]
      ),

      DashboardPanel: obj(
        key: str(description: "Panel key: news, now_playing_club, releases, achievements_club, challenges_club, " \
                              "now_playing_mine, achievements_mine, challenge_runs_mine, completions_club, " \
                              "completions_mine, backlog_pick, reviews, journals, giveaways, suggestions, codex, " \
                              "birthdays.", example: "news"),
        scope: str(enum: %w[club mine], description: "Whether the panel shows club activity or the member's own."),
        new: bool.merge(description: "Whether the panel reached the site since the member last opened dashboard " \
                                     "edit mode. For a member who never opened it, true only for panels added " \
                                     "after launch."),
        _required: %w[key scope new]
      ),

      # ChallengeSettingsController (spec #376, ticket #379): the member's
      # Challenge DM opt-out.
      ChallengeSettings: obj(
        user_id: str,
        dms: bool.merge(description: "Whether the member gets Challenge reminder DMs; true until they turn it off."),
        _required: %w[user_id dms]
      ),

      # BirthDatesController (spec #376, ticket #380). A member's Birth Date,
      # served only to the member and staff, and the member's changes left.
      BirthDate: obj(
        user_id: str,
        birth_date: str(nullable: true, pattern: '^(\\d{4}-)?\\d{2}-\\d{2}$', example: "1990-05-04",
          description: "The member's Birth Date: \"1990-05-04\", or \"05-04\" when they gave only the day and " \
                       "month (api#398). Null until they enter it."),
        birthday_shared: bool.merge(
          description: "Whether the member shares their Birthday, the day and month (never the year). Off until " \
                       "the member turns it on; removing the Birth Date turns it off (api#399)."
        ),
        changes_left_this_month: int.merge(
          example: 1,
          description: "How many more times the member may set or change it this calendar month (US Eastern), " \
                       "0 to 2. Entering it the first time counts; staff changes don't."
        ),
        next_change_on: str(nullable: true, format: "date", example: "2026-12-01",
          description: "When changes_left_this_month is 0, the first day of next month, when the member may " \
                       "change it again; null otherwise."),
        _required: %w[user_id birth_date birthday_shared changes_left_this_month next_change_on]
      ),
      BirthDateRefusal: obj(
        error: str(description: "Why it was refused. For the limit, names the date the member may change it " \
                                "again. `birth_date_required` when sharing a Birthday without a Birth Date."),
        message: str(description: "Only with `birth_date_required`: what the member is told."),
        next_change_on: str(format: "date", example: "2026-12-01",
          description: "Only when the member reached the limit: the first day of next month (US Eastern)."),
        _required: %w[error]
      ),
      # A Birthday (spec #396): the month and day of a Birth Date, never the
      # year.
      Birthday: obj(
        month: int.merge(minimum: 1, maximum: 12, example: 5),
        day: int.merge(minimum: 1, maximum: 31, example: 4),
        _description: "A Birthday: the month and day of a member's Birth Date, never the year."
      ),
      # Birthdays::Upcoming (spec #396, api#400). One shared Birthday in the
      # next 30 club days. Never the year or the age.
      UpcomingBirthday: { allOf: [
        ref("ChallengeMember"), ref("Birthday"),
        obj(display_name: str(example: "Ava",
              description: "The name the member goes by: their Discord display name, else their username."),
            on: date(example: "2026-05-04",
              description: "The date the Birthday falls on this time, in club days (America/New_York). A 29 " \
                           "February Birthday falls on 28 February in years that aren't leap years."),
            today: bool.merge(description: "Whether `on` is today in club time."))
      ] },
      # Birthdays::Upcoming.next_beyond (owner decision 11): the first shared
      # Birthday after the 30 days, without the member.
      NextBirthday: extends("Birthday",
        _description: "The first shared Birthday after the 30 days of Upcoming Birthdays, with no member: the " \
                      "bot's empty /birthdays says when the next one is. A Birthday in the 30 days counts with " \
                      "its date next year.",
        on: date(example: "2026-07-01",
          description: "The date it falls on, in club days (America/New_York). A 29 February Birthday falls " \
                       "on 28 February in years that aren't leap years.")),

      # ---- News Hub (spec #355) --------------------------------------------
      # NewsCategory: the fixed, ordered list in code. Keys are stable.
      NewsCategory: obj(
        key: str(enum: NewsCategory.keys, example: "releases",
          description: "Stable key. News Items, the bot's thread configuration and the News Import store it."),
        name: str(example: "Releases & Updates", description: "Display name."),
        position: int.merge(example: 2, description: "1-based place in the list; the list is served in this order."),
        _required: %w[key name position]
      ),
      # HiddenPlatformsController (spec api#421, ticket api#427). A member's
      # Hidden Platforms: the platforms they leave out of their own Release
      # Calendar and Upcoming Releases panel.
      HiddenPlatform: obj(
        platform_id: int,
        platform_name: str(example: "PlayStation 5"),
        platform_abbreviation: str(nullable: true, example: "PS5"),
        _required: %w[platform_id platform_name platform_abbreviation]
      ),
      HiddenPlatforms: obj(
        user_id: str,
        platform_ids: { type: :array, items: int,
                        description: "The member's Hidden Platform ids, in platform name order." },
        platforms: array_of("HiddenPlatform").merge(
          description: "The same platforms with their names, in platform name order."
        ),
        _required: %w[user_id platform_ids platforms]
      ),
      # UpcomingReleasesController#index meta: pagination plus the Hidden
      # Platforms left out of this result (ticket api#427).
      UpcomingReleasesMeta: extends("PaginationMeta",
        hidden_platform_ids: {
          type: :array, items: int,
          description: "The signed-in member's Hidden Platforms left out of this result, sorted. Empty when " \
                       "nothing was left out: the member hides nothing, `platform_id` or `show_hidden=1` was " \
                       "given, or the caller is the service token."
        },
        required: %w[hidden_platform_ids]),

      # NewsCategoryPreferencesController (ticket #357): a member's News
      # Category Preferences, the News Categories they switched off.
      NewsCategoryPreference: extends("NewsCategory",
        hidden: bool.merge(description: "The member switched this News Category off: it is left out of their " \
                                        "default News Hub view."),
        required: %w[hidden]),
      NewsCategoryPreferences: obj(
        user_id: str,
        hidden: { type: :array, items: str(enum: NewsCategory.keys),
                  description: "Every News Category key the member switched off, in News Category order." },
        categories: array_of("NewsCategoryPreference").merge(
          description: "Every News Category, in order, each marked switched off or not."
        ),
        _required: %w[user_id hidden categories]
      ),
      # NewsItemsController#index meta: pagination plus the category rail.
      NewsFeedMeta: extends("PaginationMeta",
        category_counts: {
          type: :object,
          description: "How many News Items each News Category holds for the current search (`q`), ignoring " \
                       "`category` and the member's News Category Preferences. Keyed by every News Category " \
                       "key in order, 0 for none. Only sorted News Items count.",
          properties: NewsCategory.keys.index_with { { type: :integer } },
          required: NewsCategory.keys,
          example: NewsCategory.keys.index_with(0).merge("releases" => 12, "industry" => 3)
        },
        hidden_categories: {
          type: :array, items: str(enum: NewsCategory.keys),
          description: "The News Category keys the member switched off, in order, whatever this request " \
                       "filters by: the default view leaves these out. Empty for the service token."
        },
        required: %w[category_counts hidden_categories]),
      # NewsItemResource: a News Item as the website and the bot read it.
      NewsItem: obj(
        message_id: str(example: "1300000000000000003",
          description: "The Discord message's snowflake: the News Item's identity."),
        category_key: str(enum: NewsCategory.keys, nullable: true,
          description: "The News Category's key. Always set in the member feed; null only for an imported " \
                       "News Item staff have not sorted yet, which members never see."),
        origin: str(enum: NewsItem::ORIGINS,
          description: "live: recorded from the News Channel as it was posted. import: brought in by the " \
                       "News Import from before the News Hub."),
        picked_category_key: str(enum: NewsCategory.keys, nullable: true,
          description: "The News Category the bot first picked for it, kept when the category is corrected; " \
                       "null when the bot reported none (imported News Items, and items recorded before the " \
                       "News Channel)."),
        news_copy: ref("NewsCopy", nullable: true).merge(
          description: "Where the News Copy (the bot's copy in the News Category's thread) lives; null while " \
                       "the News Item has none."
        ),
        comment: str(nullable: true,
          description: "The member's own words: the message text as a reader sees it, without the link " \
                       "address. Null when there are none."),
        posted_at: ts.merge(description: "When the message was posted in Discord."),
        edited_at: ts(nullable: true).merge(description: "When the message was last edited; null if never."),
        link: ref("NewsItemLink", nullable: true).merge(
          description: "The message's first link and Discord's preview of it. Null for an image-only News Item."
        ),
        images: array_of("NewsItemImage").merge(
          description: "The message's image attachments in posted order; empty when there are none."
        ),
        author: ref("NewsItemAuthor"),
        _required: %w[message_id category_key origin comment posted_at edited_at link images author
                      picked_category_key news_copy]
      ),
      NewsCategoryChange: obj(
        changed: bool.merge(description: "False when the News Item already had that News Category and nothing " \
                                         "changed: the News Copy stays where it is."),
        previous_category_key: str(enum: NewsCategory.keys, nullable: true,
          description: "The News Category before this request (the same as `category_key` when nothing " \
                       "changed); null for an imported News Item staff had not sorted."),
        _required: %w[changed previous_category_key]
      ),
      NewsItemRemoval: obj(
        removed: bool.merge(description: "True when a News Item was recorded for the message and is now " \
                                         "deleted; false when none was recorded (nothing changed)."),
        news_copy: ref("NewsCopy", nullable: true).merge(
          description: "Where the removed News Item's News Copy lives, so the bot can delete it; null when " \
                       "it had none, or when nothing was removed."
        ),
        _required: %w[removed news_copy]
      ),
      NewsCopy: obj(
        message_id: str(example: "1500000000000000005", description: "The News Copy's Discord message id."),
        thread_id: str(example: "1600000000000000006",
          description: "The id of the News Category's thread the News Copy is posted in."),
        _required: %w[message_id thread_id]
      ),
      NewsItemLink: obj(
        url: str(example: "https://example.test/news/story", description: "The link's address (http or https)."),
        title: str(nullable: true, description: "The preview's title. Null until Discord's preview arrives, " \
                                                "or when the page has none."),
        site_name: str(nullable: true, description: "The preview's site name."),
        description: str(nullable: true, description: "The preview's description."),
        image_url: str(nullable: true,
          description: "The outside site's own image address from the preview. Never expires and is never " \
                       "renewed; if it stops working, show no image."),
        _required: %w[url title site_name description image_url]
      ),
      NewsItemImage: obj(
        url: str(nullable: true, description: "The image's Discord attachment address. Null when unavailable."),
        unavailable: bool.merge(
          description: "True when the Discord address has expired and the bot has been asked to renew it: show " \
                       "a placeholder; the image is back on a later load."
        ),
        _required: %w[url unavailable]
      ),
      NewsItemAuthor: obj(
        user_id: str(description: "The author's Discord user id."),
        name: str(description: "The member's current name (display name, else username) when they have a " \
                               "member record; otherwise the name they had when the message was recorded."),
        member: bool.merge(description: "True when the author has a member record (their profile and avatar " \
                                        "exist). False for authors the club never recorded."),
        _required: %w[user_id name member]
      ),
      # ---- News Import (ticket #359) ---------------------------------------
      # NewsImportItemResource: an unsorted imported News Item, as the
      # download file lists it for a classifier.
      NewsImportItem: obj(
        message_id: str(example: "1300000000000000003", description: "The imported Discord message's snowflake."),
        posted_at: ts.merge(description: "When the message was posted in the News Channel."),
        author_name: str(description: "The member's current name when they have a member record; otherwise " \
                                      "the name recorded with the message."),
        comment: str(nullable: true, description: "The member's own words; null when there are none."),
        link_url: str(nullable: true, description: "The link's address; null for an image-only item."),
        link_title: str(nullable: true, description: "The link preview's title."),
        link_site_name: str(nullable: true, description: "The link preview's site name."),
        link_description: str(nullable: true, description: "The link preview's description."),
        image_count: int.merge(description: "How many image attachments the message has."),
        _required: %w[message_id posted_at author_name comment link_url link_title link_site_name
                      link_description image_count]
      ),
      NewsImportAssignResult: obj(
        assigned: int.merge(description: "Rows that assigned a News Category."),
        removed: int.merge(description: "`skip` rows (including items already removed by an earlier `skip`)."),
        rejected: int.merge(description: "Rows rejected; listed in `rejections`."),
        unsorted: int.merge(description: "Imported News Items still unsorted after this request."),
        rejections: array_of("NewsImportAssignRejection").merge(description: "The rejected rows, in order."),
        moved: array_of("NewsImportMove").merge(
          description: "The items whose News Category this request changed and that have a News Copy, in row " \
                       "order: the bot moves each copy to the new category's thread. A first assignment to an " \
                       "unsorted item is never listed (it has no News Copy)."
        ),
        _required: %w[assigned removed rejected unsorted rejections moved]
      ),
      NewsImportMove: obj(
        message_id: str(example: "1300000000000000003", description: "The News Item's message snowflake."),
        category_key: str(enum: NewsCategory.keys, description: "The News Category it now has."),
        previous_category_key: str(enum: NewsCategory.keys, description: "The News Category it had before."),
        news_copy: ref("NewsCopy").merge(description: "Where its News Copy lives now, in the previous " \
                                                      "category's thread."),
        _required: %w[message_id category_key previous_category_key news_copy]
      ),
      NewsImportAssignRejection: obj(
        index: int.merge(description: "The row's 0-based position in `rows`."),
        message_id: str(description: "The message id as sent (trimmed); empty when missing."),
        value: str(description: "The value as sent."),
        reason: str(example: "unknown message ID",
          description: "One of: `missing message ID`, `message ID appears more than once`, `no value: ...`, " \
                       "`invalid value: ...` (both end with the accepted values), `removed with skip`, " \
                       "`unknown message ID`, `not an imported News Item`."),
        _required: %w[index message_id value reason]
      ),
      NewsImportStatus: obj(
        sorted: int.merge(description: "Imported News Items with a News Category (shown to members)."),
        unsorted: int.merge(description: "Imported News Items with no News Category yet (hidden)."),
        removed: int.merge(description: "Imported News Items staff removed with `skip`."),
        copied: int.merge(description: "News Items, live and imported, that have a News Copy."),
        uncopied: int.merge(description: "News Items, live and imported, that have a News Category but no " \
                                         "News Copy yet: what the history copy has left (see " \
                                         "`GET /api/v1/news_items/uncopied`). Unsorted items are not counted."),
        _required: %w[sorted unsorted removed copied uncopied]
      ),
      SearchSynonym: obj(
        term_id: int, group_id: int, term_text: str, term_norm: str,
        created_at: ts, created_by: str(nullable: true)
      ),
      SearchSynonymDraft: obj(
        draft_id: int, user_id: str, pairs_json: str(nullable: true), created_at: ts, updated_at: ts
      ),
      # SearchSynonymGroupResource: all columns; `terms` (sorted by text) is
      # embedded only when the caller asks for it (`?include=terms`, #333).
      SearchSynonymGroup: obj(
        group_id: int, created_at: ts, created_by: str(nullable: true), terms: array_of("SearchSynonym")
      ),
      # The replace-terms response (#333): the group with its new terms.
      SearchSynonymGroupWithTerms: extends("SearchSynonymGroup", terms: array_of("SearchSynonym"), required: %w[terms]),
      JournalMessageContext: obj(
        channel_id: str, message_id: str, created_at_ms: int, owner_user_id: str, game_id: int
      ),

      # ---- threads ---------------------------------------------------------
      # DiscordThread (all columns) plus the computed `jump_url`. `is_archived`
      # and `skip_linking` are stored as strings. `gamedb_game_id` is
      # server-derived (MIN of the thread's links).
      Thread: obj(
        thread_id: str, forum_channel_id: str, thread_name: str,
        gamedb_game_id: int(nullable: true), is_archived: str, created_at: ts,
        last_seen_at: ts(nullable: true), skip_linking: str, jump_url: str(nullable: true)
      ),
      # threads#show adds the full game-link list under `links`.
      ThreadWithLinks: extends("Thread", links: array_of("ThreadGameLink"), required: %w[links]),
      ThreadGameLink: obj(thread_id: str, gamedb_game_id: int, linked_at: ts),
      # threads#index (ThreadSearchResultResource): the thread link picker's
      # row, the thread's id and name plus its linked games.
      ThreadSearchResult: obj(
        thread_id: str, thread_name: str,
        games: { type: :array, items: obj(game_id: int, title: str) },
        _required: %w[thread_id thread_name games]
      ),

      # ---- presence / activity / member history (bot-written, read-only) ---
      # BotPresenceResource: the four logical columns; the surrogate `id` is
      # internal-only and never exposed.
      # GuildChannelsController#index/#upsert (#313). `channel_type` is
      # Discord's numeric ChannelType; `category_name` is the parent
      # category's name (null when uncategorized, and on upsert responses).
      GuildChannel: obj(
        channel_id: str, name: str, channel_type: int, parent_id: str(nullable: true),
        position: int, category_name: str(nullable: true)
      ),
      BotPresence: obj(
        activity_name: str, set_at: ts,
        set_by_user_id: str(nullable: true), set_by_username: str(nullable: true)
      ),
      # BotPresenceController#create meta: the queued presence_set bot job, so
      # the website can poll GET /api/v1/bot_jobs/{id}.
      BotPresenceCreateMeta: obj(
        presence_job_id: int(nullable: true).merge(
          description: "The presence_set bot job. Null for a service write, which queues none."
        )
      ),
      PresencePrompt: obj(
        prompt_id: str, user_id: str, game_title: str, game_title_norm: str,
        status: str, created_at: ts, resolved_at: ts(nullable: true)
      ),
      # PresencePromptOptsController#show/update — the per-user opt-out document.
      PresencePromptOpts: obj(
        user_id: str,
        all: bool,
        games: {
          type: :array,
          items: obj(
            game_title: str(nullable: true), game_title_norm: str, created_at: ts
          )
        }
      ),
      UserNickHistory: obj(
        event_id: int, user_id: str, old_nick: str(nullable: true), new_nick: str(nullable: true),
        changed_at: ts
      ),
      # UserAvatarHistoryResource (#105): all columns except the binary
      # `avatar_blob`. `changed_at` is DB-stamped on insert.
      UserAvatarHistory: obj(
        event_id: int, user_id: str, avatar_hash: str(nullable: true),
        avatar_url: str(nullable: true), changed_at: ts
      ),
      # UserAvatarHistoryController#counts (AvatarHistoryCountResource, #145): a
      # member's identity plus the grouped `COUNT(*)` of their logged avatar
      # changes. An aggregate row, not a model record.
      AvatarHistoryCount: obj(
        user_id: str, username: str(nullable: true), global_name: str(nullable: true),
        avatar_change_count: int
      ),

      # ---- GOTM / nominations ----------------------------------------------
      # GotmEntryResource: all columns; `game` is embedded only when the caller
      # requests it (`?include=game`), so it is not always present.
      GotmEntry: obj(
        gotm_id: int, round_number: int, month_year: str, game_index: int,
        reddit_url: str(nullable: true), voting_results_message_id: str(nullable: true),
        gamedb_game_id: int(nullable: true), game: ref("GameWithPlatforms", nullable: true)
      ),
      NrGotmEntry: obj(
        nr_gotm_id: int, round_number: int, month_year: str, game_index: int,
        reddit_url: str(nullable: true), voting_results_message_id: str(nullable: true),
        gamedb_game_id: int(nullable: true), game: ref("GameWithPlatforms", nullable: true)
      ),
      # Gotm::RoundHistory (GotmRoundsController): one round of GOTM history.
      # A kind's block is null when that kind has no (matching) entries in the
      # round; NR-GOTM "N/A" placeholder games are left out of `games`, so an
      # NR block can be present with an empty `games` list.
      GotmRoundGame: obj(
        game_index: int, gamedb_game_id: int(nullable: true), reddit_url: str(nullable: true),
        thread_id: str(nullable: true, description: "The game's newest linked Discord thread."),
        game: ref("GameWithPlatforms", nullable: true)
      ),
      GotmRoundBlock: obj(
        month_year: str, voting_results_message_id: str(nullable: true), games: array_of("GotmRoundGame"),
        _required: %w[month_year games]
      ),
      GotmRound: obj(
        round_number: int, gotm: ref("GotmRoundBlock", nullable: true), nr_gotm: ref("GotmRoundBlock", nullable: true),
        _required: %w[round_number gotm nr_gotm]
      ),
      # Public::WinnersController: one winning game of a recent round, for the
      # unauthenticated www landing. Club content only — no member data,
      # Reddit URLs or Discord ids.
      PublicWinner: obj(
        round_number: int, month_year: str(example: "March 2024"),
        kind: str(enum: %w[gotm nr_gotm]), game_id: int, title: str,
        cover_url: str(nullable: true), art_url: str(nullable: true)
      ),
      # NominationResource (gotm + nr-gotm share it). `user`/`game` are
      # bot-sourced and FK-unenforced, so either may be null.
      Nomination: obj(
        nomination_id: int, round_number: int, user_id: str, gamedb_game_id: int(nullable: true),
        reason: str(nullable: true), nominated_at: ts,
        user: ref("UserSummary", nullable: true), game: ref("GameWithPlatforms", nullable: true)
      ),
      # VoteResource (gotm + nr-gotm share it): the IDENTIFIED vote shape —
      # only served to admin/service, the voter themselves, or anyone once the
      # round's voting window has ended. `user`/`game` are FK-unenforced, so
      # either may be null.
      Vote: obj(
        vote_id: int, round_number: int, user_id: str, nomination_id: int,
        gamedb_game_id: int, voted_at: ts, runoff: bool,
        user: ref("UserSummary", nullable: true), game: ref("GameSummary", nullable: true)
      ),
      # VoteTallyResource: one nomination's anonymous vote count. Nominations
      # with zero votes have no row — merge against the nominations list.
      VoteTally: obj(nomination_id: int, gamedb_game_id: int, vote_count: int),
      # The tally's meta: the ballot's per-user vote cap, whether it is the
      # runoff ballot, and whether the counts were withheld (voting still
      # open and the caller not an Admin or the service).
      VoteTallyMeta: obj(cap: int, runoff: bool, counts_hidden: bool),
      # The cast response (VotesController#create_*): what the cast did, the
      # vote it placed (null when it toggled one off), any votes removed to
      # make room (evicted oldest-first) or taken back by the toggle, the
      # user's current cap for the ballot, whether the cast went to the
      # round's runoff, and a human-readable warning to surface to the voter
      # whenever votes were removed.
      VoteCastResult: obj(
        action: str(enum: %w[voted unvoted]),
        vote: ref("Vote", nullable: true),
        removed_votes: array_of("Vote"),
        cap: int,
        runoff: bool,
        warning: str(nullable: true),
        _required: %w[action removed_votes cap runoff]
      ),

      # ---- Achievement Hub reads (api-09) ----------------------------------
      # An Achievement Set (AchievementSetResource): a Provider's list for one
      # title. `external_id` is the RA game id, Steam appid or PSN
      # npCommunicationId; `game_id` is the optional GameDB link.
      AchievementSet: obj(
        id: int, provider: str(enum: UserLinkedAccount::PROVIDERS), external_id: str,
        title: str(nullable: true), platform_label: str(nullable: true), icon_url: str(nullable: true),
        game_id: int(nullable: true), achievements_count: int, points_total: int
      ),
      # An Achievement definition (AchievementResource). `rarity` is the
      # Provider's global unlock percentage (0-100); `rarity_hardcore` and
      # `points` are RA only, `tier` PSN only. `hidden` ones are blurred by www
      # unless the viewer unlocked them.
      Achievement: obj(
        id: int, name: str(nullable: true), description: str(nullable: true),
        icon_url: str(nullable: true), icon_locked_url: str(nullable: true), hidden: bool,
        points: int(nullable: true), tier: str(nullable: true, enum: [ *Achievement::TIERS, nil ]),
        display_order: int(nullable: true), removed_at: ts(nullable: true),
        rarity: num(nullable: true), rarity_hardcore: num(nullable: true)
      ),
      # An Unlock (AchievementUnlockResource) with its Achievement and set.
      # `viewer_unlocked` is whether the signed-in viewer has the same
      # Achievement (always false for the service principal).
      AchievementUnlock: obj(
        id: int, user_id: str, unlocked_at: ts, hardcore: bool,
        highlight: str(nullable: true, enum: [ *UserAchievementUnlock::HIGHLIGHTS, nil ]),
        viewer_unlocked: bool,
        achievement: ref("Achievement"), achievement_set: ref("AchievementSet"),
        _required: %w[id user_id unlocked_at hardcore highlight viewer_unlocked achievement achievement_set]
      ),
      # A member's cached progress on one set (SetProgressResource). Completion,
      # Mastery (RA, every Unlock hardcore) and Platinum (PSN) are timestamps.
      SetProgress: obj(
        id: int, user_id: str, achievement_set_id: int, earned_count: int, hardcore_earned_count: int,
        total_count: int, points_earned: int, completed_at: ts(nullable: true), mastered_at: ts(nullable: true),
        platinum_at: ts(nullable: true), last_unlocked_at: ts(nullable: true), playtime_minutes: int(nullable: true)
      ),
      # A progress-grid card (AchievementSetProgressResource): SetProgress plus
      # the set and its Provider.
      AchievementSetProgress: extends(
        "SetProgress",
        provider: str(enum: UserLinkedAccount::PROVIDERS), achievement_set: ref("AchievementSet"),
        required: %w[provider achievement_set]
      ),
      # Hub totals for one Provider, or overall (`totals`, which has no
      # `provider`). Read from the cached progress rows.
      AchievementTotals: obj(
        unlocks: int, completions: int, masteries: int, platinums: int, points: int,
        _description: "Unlocks, Completions, Masteries, Platinums and RA points earned."
      ),
      AchievementProviderTotals: extends(
        "AchievementTotals", provider: str(enum: UserLinkedAccount::PROVIDERS), required: %w[provider]
      ),
      # A Linked Account as its owner sees it (LinkedAccountResource,
      # users/:user_id/linked_accounts): the Provider identity and sync state.
      LinkedAccount: obj(
        id: int, user_id: str,
        provider: str(enum: UserLinkedAccount::PROVIDERS),
        external_id: str(description: "The Provider's stable id: RA ULID, SteamID64 or PSN accountId."),
        display_name: str(nullable: true, description: "The member's name on the Provider, as resolved when linked."),
        sync_status: str(enum: UserLinkedAccount::SYNC_STATUSES,
          description: "pending until the first sync finishes; private/not_found stop syncing until Retry; " \
                       "error is transient (the next Sync Window tries again)."),
        sync_mode: str(enum: UserLinkedAccount::SYNC_MODES,
          description: "backfill until the first full import finishes, then incremental."),
        sync_error: str(nullable: true, description: "The Provider's message for the last failure."),
        last_synced_at: ts(nullable: true), backfilled_at: ts(nullable: true),
        sync_requested_at: ts(nullable: true).merge(description: "The last Sync now."),
        sync_available_at: ts.merge(description: "When Sync now is next allowed: now, or the end of the 15-minute cooldown."),
        created_at: ts
      ),
      # 422 from the Linked Account writes. `error` is the machine reason.
      LinkedAccountError: obj(
        error: str(enum: %w[provider_already_linked identity_claimed not_found private invalid_provider
          retry_not_allowed retry_required]),
        message: str,
        _required: %w[error message],
        _description: "provider_already_linked: the member already has a Linked Account on this Provider. " \
                      "identity_claimed: another member linked this Provider identity. " \
                      "not_found / private: the Provider can't find or can't see the account. " \
                      "invalid_provider: unknown Provider. retry_not_allowed: Retry only from " \
                      "private/not_found/error. retry_required: Sync now on a private/not_found account."
      ),
      # 429 from Sync now inside the cooldown.
      SyncCooldownError: obj(
        error: str(enum: %w[sync_cooldown]), message: str, sync_available_at: ts,
        _required: %w[error message sync_available_at]
      ),
      # A Linked Account's public face: Provider and display name only.
      LinkedAccountSummary: obj(
        provider: str(enum: UserLinkedAccount::PROVIDERS), display_name: str(nullable: true)
      ),
      # users/:user_id/achievements/summary.
      MemberAchievementSummary: obj(
        user: ref("UserSummary"), totals: ref("AchievementTotals"),
        providers: array_of("AchievementProviderTotals"),
        linked_accounts: array_of("LinkedAccountSummary"),
        latest_unlocks: array_of("AchievementUnlock"),
        rarest_unlocks: array_of("AchievementUnlock"),
        _required: %w[user totals providers linked_accounts latest_unlocks rarest_unlocks],
        _description: "One `providers` row per Linked Account, zeros until its first sync. " \
                      "`latest_unlocks` holds at most 5, newest first. `rarest_unlocks` holds at most 4, " \
                      "by the Achievement's `rarity` ascending, those with no Rarity last."
      ),
      # An Achievement on the set page (SetAchievementResource): the definition
      # plus the subject member's Unlock state (null/false when locked or when
      # no `user_id` was given) and the viewer's.
      SetAchievement: extends(
        "Achievement",
        unlocked_at: ts(nullable: true), hardcore: bool, viewer_unlocked: bool,
        required: %w[unlocked_at hardcore viewer_unlocked]
      ),
      # achievement_sets/:id.
      AchievementSetDetail: extends(
        "AchievementSet",
        game: ref("GameSummary", nullable: true),
        user: ref("UserSummary", nullable: true),
        progress: ref("SetProgress", nullable: true),
        achievements: array_of("SetAchievement"),
        removed_achievements: array_of("SetAchievement"),
        required: %w[game user progress achievements removed_achievements]
      ),
      # A `latest` feed card: one member's Unlocks in one set on one UTC day.
      AchievementFeedGroup: obj(
        kind: str(enum: %w[group]), user: ref("UserSummary"), achievement_set: ref("AchievementSet"),
        day: str(format: "date", example: "2026-10-31"), count: int, latest_unlocked_at: ts,
        unlocks: array_of("AchievementUnlock"),
        _required: %w[kind user achievement_set day count latest_unlocked_at unlocks],
        _description: "`count` is every Unlock of the card; `unlocks` holds at most 8, newest first."
      ),
      # A `highlights` feed card: one Highlight Unlock and its member.
      AchievementFeedHighlight: extends(
        "AchievementUnlock",
        kind: str(enum: %w[highlight]), user: ref("UserSummary"),
        unlocked_at: ts.merge(description: "The Highlight's date: a Mastery's hardcore time, otherwise the Unlock time."),
        required: %w[kind user]
      ),
      # A member who completed a set on the game showcase.
      AchievementSetCompletion: obj(user: ref("UserSummary"), completed_at: ts, _required: %w[user completed_at]),
      # An Achievement on the game showcase (GameSetAchievementResource).
      GameSetAchievement: obj(
        id: int, name: str(nullable: true),
        description: str(nullable: true, description: "Kept for hidden Achievements; www blurs it."),
        icon_url: str(nullable: true), icon_locked_url: str(nullable: true), hidden: bool,
        tier: str(nullable: true, enum: [ *Achievement::TIERS, nil ]), points: int(nullable: true),
        rarity: num(nullable: true),
        holders: { type: :array, items: { type: :string },
                   description: "user_ids of the active members who unlocked it, earliest Unlock first." },
        viewer_unlocked: bool,
        _required: %w[id name description icon_url icon_locked_url hidden tier points rarity holders viewer_unlocked]
      ),
      # games/:id/achievement_sets (GameAchievementSetResource).
      GameAchievementSet: extends(
        "AchievementSet",
        completions: array_of("AchievementSetCompletion"),
        viewer_progress: ref("SetProgress", nullable: true),
        achievements: array_of("GameSetAchievement").merge(
          description: "The set's non-removed Achievements in display order."
        ),
        required: %w[completions viewer_progress achievements]
      ),

      # ---- aggregate game-profile sub-shapes (#115) ------------------------
      GotmWin: obj(round: int, reddit_url: str(nullable: true)),
      GotmNominationSummary: obj(round: int, user_id: str, username: str(nullable: true)),
      CollectionOwner: obj(user_id: str, username: str(nullable: true)),
      # RpgClubHltbCache surfaced under the bot's logical field names.
      Hltb: obj(
        name: str(nullable: true), url: str(nullable: true), image_url: str(nullable: true),
        main: str(nullable: true), main_sides: str(nullable: true), completionist: str(nullable: true),
        single_player: str(nullable: true), co_op: str(nullable: true), vs: str(nullable: true),
        source_query: str(nullable: true), scraped_at: ts(nullable: true),
        searched_at: ts(nullable: true).merge(description: "When HowLongToBeat was last searched for the game; " \
                                                           "null for times entered by hand."),
        next_forced_search_at: ts(nullable: true).merge(description: "When a member may next force a search " \
                                                                     "(lookup `force: true`); null: now. Admins " \
                                                                     "and above may at any time."),
        updated_at: ts(nullable: true)
      ),
      HltbSearchTooSoon: obj(
        error: str(example: "hltb_search_too_soon"), message: str,
        next_forced_search_at: ts.merge(description: "When the next forced search is allowed."),
        _required: %w[error message next_forced_search_at]
      ),
      # POST /games/{id}/hltb/lookup: where the times came from and whether
      # they are now in the HLTB cache.
      HltbLookup: obj(
        data: ref("Hltb"),
        meta: obj(
          source: str(enum: %w[cache hltb],
            description: "cache: the saved times, or an unsaved result kept for about a day; no scrape. " \
                         "hltb: a fresh scrape."),
          saved: bool,
          _description: "saved is false for a result for a game released within six months, or undated."
        ),
        _required: %w[data meta]
      )
    }
  end
end
