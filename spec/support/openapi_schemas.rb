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
#   1. DB columns       — db/structure.sql (column presence + null-ness)
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
  module_function

  def str(nullable: false, **opts) = { type: :string }.merge(nullable ? { nullable: true } : {}).merge(opts)
  def int(nullable: false) = { type: :integer }.merge(nullable ? { nullable: true } : {})
  def num(nullable: false) = { type: :number }.merge(nullable ? { nullable: true } : {})
  def bool(nullable: false) = { type: :boolean }.merge(nullable ? { nullable: true } : {})
  def ts(nullable: false) = { type: :string, format: "date-time" }.merge(nullable ? { nullable: true } : {})
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
      Franchise: obj(franchise_id: int, name: str, igdb_franchise_id: int(nullable: true)),
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
      # GamedbGameImage (all columns) plus the derived public `url`.
      GameImage: obj(
        image_id: int, game_id: int, kind: str, object_key: str,
        uploaded_by_user_id: str(nullable: true), is_primary: bool, position: int,
        created_at: ts, updated_at: ts, url: str
      ),
      # GamedbRelease (all columns) plus the flattened platform/region labels.
      Release: obj(
        release_id: int, game_id: int, platform_id: int, region_id: int,
        format: str(nullable: true), release_date: ts(nullable: true), notes: str(nullable: true),
        platform_code: str, platform_name: str, region_code: str, region_name: str
      ),
      # A GamedbGameCompany flattened to its company's columns plus the join `role`.
      GameCompany: obj(
        company_id: int, name: str, igdb_company_id: int(nullable: true), role: str
      ),
      # GamedbReleaseAnnouncement (all columns). The delivery columns
      # (`sent_at`, `skipped_at`, `skip_reason`) are read-only — set by the bot's
      # send loop / the #skip action, stripped from create/update writes.
      ReleaseAnnouncement: obj(
        release_id: int, announce_at: ts, sent_at: ts(nullable: true),
        skipped_at: ts(nullable: true), skip_reason: str(nullable: true),
        created_at: ts, updated_at: ts
      ),

      # ---- user shapes -----------------------------------------------------
      # The reusable embedded/members-list user shape (UserSummaryResource /
      # UserFields): a consumer-audited subset of rpg_club_users.
      UserSummary: obj(
        user_id: str, username: str(nullable: true), global_name: str(nullable: true),
        is_bot: bool, role_admin: bool, role_moderator: bool, role_regular: bool,
        server_left_at: ts(nullable: true)
      ),
      # The computed membership summary (RpgClubUser#membership).
      Membership: obj(
        admin: bool, moderator: bool, regular: bool, member: bool, newcomer: bool, active: bool
      ),
      # UserSocial (all columns; note the FK alias `platform_id`, NOT
      # `social_platform_id`) plus the embedded social platform.
      UserSocial: obj(
        id: int, user_id: str, platform_id: int, display_text: str(nullable: true),
        url: str(nullable: true), created_at: ts, updated_at: ts,
        social_platform: ref("SocialPlatform")
      ),
      # Per-user counts on the profile payload (UsersController#show).
      UserCounts: obj(
        now_playing: int, favorites: int, reviews: int, completions: int,
        backlog: int, collections: int, journal: int
      ),
      # The full users#show profile payload (UserResource): UserSummary plus
      # `membership`, the embedded socials, the four preview lists, the journal
      # grid and the counts summary.
      User: extends(
        "UserSummary",
        membership: ref("Membership"),
        socials: array_of("UserSocial"),
        now_playing: array_of("NowPlayingEntry"),
        favorites: array_of("FavoriteEntry"),
        reviews: array_of("ReviewEntry"),
        completions: array_of("CompletionEntry"),
        journal: array_of("JournaledGame"),
        counts: ref("UserCounts")
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
      # collections#index (CollectionEntryResource): trimmed columns + the joined
      # platform name/abbreviation (CollectionFields, #101), no embeds.
      CollectionEntry: obj(
        entry_id: int, user_id: str, gamedb_game_id: int, platform_id: int(nullable: true),
        ownership_type: str, note: str(nullable: true),
        platform_name: str(nullable: true), platform_abbreviation: str(nullable: true)
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
      # reviews#index / show / create / update render `as_json` — all columns,
      # including the write-only `is_shared` and `updated_at` the curated shape trims.
      Review: obj(
        review_id: int, user_id: str, gamedb_game_id: int, rating: int,
        body: json, is_shared: bool, created_at: ts, updated_at: ts
      ),
      # ReviewUserEntryResource (ReviewFields + user), for the game-scoped reviews list.
      ReviewUserEntry: obj(
        review_id: int, user_id: str, gamedb_game_id: int, rating: int,
        body: json, created_at: ts, user: ref("UserSummary")
      ),
      # ReviewEntryResource (ReviewFields + game), embedded in the user profile preview.
      ReviewEntry: obj(
        review_id: int, user_id: str, gamedb_game_id: int, rating: int,
        body: json, created_at: ts, game: ref("GameSummary")
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
      Todo: obj(
        todo_id: int, title: str, details: str(nullable: true), created_by: str(nullable: true),
        created_at: ts, updated_at: ts, completed_at: ts(nullable: true),
        completed_by: str(nullable: true), is_completed: bool, category: str,
        todo_category: str, todo_size: str(nullable: true)
      ),
      Suggestion: obj(
        suggestion_id: int, title: str, details: str(nullable: true), created_by: str(nullable: true),
        created_at: ts, updated_at: ts, labels: str(nullable: true), created_by_name: str(nullable: true)
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
      VotingInfo: obj(
        round_number: int, nomination_list_id: int(nullable: true), next_vote_at: ts,
        five_day_reminder_sent: bool, one_day_reminder_sent: bool
      ),
      # UserReminder (all columns). Delivery columns (`sent_at`, `failure_count`,
      # `failed_at`) are bot-managed read-only — stripped from writes.
      Reminder: obj(
        reminder_id: int, user_id: str, remind_at: ts, content: str,
        sent_at: ts(nullable: true), is_noisy: bool, failure_count: int,
        failed_at: ts(nullable: true), created_at: ts, updated_at: ts
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
      # it is rendered only in the response to a successful claim and to the
      # restricted single-key GET.
      GameKey: obj(
        key_id: int, game_title: str, platform: str, gamedb_game_id: int(nullable: true),
        donor_user_id: str, claimed_by_user_id: str(nullable: true), claimed_at: ts(nullable: true),
        donor_notify_on_claim: bool, created_at: ts, updated_at: ts,
        key_value: str(nullable: true).merge(description: "The key secret. Present only in the response to a successful claim and to GET /api/v1/game_keys/{id}."),
        game: ref("GameSummary", nullable: true)
      ),
      # GiveawaySettingsController. The donor's notify-on-claim preference,
      # derived from rpg_club_users.donor_notify_on_claim.
      GiveawaySettings: obj(user_id: str, notify_on_claim: bool),
      SearchSynonym: obj(
        term_id: int, group_id: int, term_text: str, term_norm: str,
        created_at: ts, created_by: str(nullable: true)
      ),
      SearchSynonymDraft: obj(
        draft_id: int, user_id: str, pairs_json: str(nullable: true), created_at: ts, updated_at: ts
      ),
      SearchSynonymGroup: obj(group_id: int, created_at: ts, created_by: str(nullable: true)),
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

      # ---- presence / activity / member history (bot-written, read-only) ---
      # BotPresenceResource: the four logical columns; the surrogate `id` is
      # internal-only and never exposed.
      BotPresence: obj(
        activity_name: str, set_at: ts,
        set_by_user_id: str(nullable: true), set_by_username: str(nullable: true)
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
      UserActivityIcon: obj(
        id: int, user_id: str, username: str(nullable: true), activity_name: str,
        activity_name_norm: str, icon_type: str, source_ref: str, icon_url: str,
        first_seen_at: ts, last_seen_at: ts, seen_count: int
      ),
      UserChannelCount: obj(
        user_id: str, channel_id: str, message_count: int, last_scanned_at: ts(nullable: true),
        created_at: ts, updated_at: ts
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

      # ---- GOTM / nominations ----------------------------------------------
      # GotmEntryResource: all columns; `game` is embedded only when the caller
      # requests it (`?include=game`), so it is not always present.
      GotmEntry: obj(
        gotm_id: int, round_number: int, month_year: str, game_index: int,
        reddit_url: str(nullable: true), voting_results_message_id: str(nullable: true),
        gamedb_game_id: int(nullable: true), game: ref("GameSummary", nullable: true)
      ),
      NrGotmEntry: obj(
        nr_gotm_id: int, round_number: int, month_year: str, game_index: int,
        reddit_url: str(nullable: true), voting_results_message_id: str(nullable: true),
        gamedb_game_id: int(nullable: true), game: ref("GameSummary", nullable: true)
      ),
      # NominationResource (gotm + nr-gotm share it). `user`/`game` are
      # bot-sourced and FK-unenforced, so either may be null.
      Nomination: obj(
        nomination_id: int, round_number: int, user_id: str, gamedb_game_id: int(nullable: true),
        reason: str(nullable: true), nominated_at: ts,
        user: ref("UserSummary", nullable: true), game: ref("GameSummary", nullable: true)
      ),

      # ---- aggregate game-profile sub-shapes (#115) ------------------------
      GotmWin: obj(round: int),
      GotmNominationSummary: obj(round: int, user_id: str, username: str(nullable: true)),
      CollectionOwner: obj(user_id: str, username: str(nullable: true)),
      # RpgClubHltbCache surfaced under the bot's logical field names.
      Hltb: obj(
        name: str(nullable: true), url: str(nullable: true), image_url: str(nullable: true),
        main: str(nullable: true), main_sides: str(nullable: true), completionist: str(nullable: true),
        single_player: str(nullable: true), co_op: str(nullable: true), vs: str(nullable: true),
        source_query: str(nullable: true), scraped_at: ts(nullable: true), updated_at: ts(nullable: true)
      )
    }
  end
end
