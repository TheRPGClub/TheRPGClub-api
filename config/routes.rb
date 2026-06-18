Rails.application.routes.draw do
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
  root "api/v1/health#show"
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :auth do
    get "discord", to: "discord#start"
    get "discord/callback", to: "discord#callback"
    delete "logout", to: "sessions#destroy"
  end

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "session", to: "sessions#show"
      get "dashboard", to: "dashboards#show"

      # IGDB discovery proxy (#122); declared before `resources :games` for
      # locality with the create-from-IGDB endpoint it feeds.
      get "igdb/search", to: "igdb#search"

      resources :games, only: %i[index show create] do
        resources :images, only: %i[index create update destroy], controller: "game_images"

        member do
          post "refresh-images", to: "games#refresh_images"
          get "relations", to: "games#relations"
          get "profile", to: "games#profile"
          get "releases", to: "games#releases"
          get "now_playing", to: "now_playing#index"
          get "completions", to: "completions#game_index"
          get "collections", to: "collections#game_index"
          get "reviews", to: "reviews#game_index"
          get "journal", to: "journal#game_index"
          get "release_announcements", to: "release_announcements#game_index"
          get "threads", to: "threads#game_index"
        end
      end

      resources :platforms, only: %i[index show]
      resources :regions, only: %i[index show]
      resources :genres, only: %i[index show]
      resources :themes, only: %i[index show]
      resources :perspectives, only: %i[index show]
      resources :modes, only: %i[index show]
      resources :franchises, only: %i[index show]
      resources :companies, only: %i[index show]
      resources :engines, only: %i[index show]

      resources :users, param: :user_id, only: %i[index show] do
        member do
          get "avatar"
          get "profile-image"
          get "nick_history", to: "user_nick_history#index"
          get "collections/platform_summary", to: "collections#platform_summary"
          get "collections", to: "collections#index"
          post "collections", to: "collections#create"
          get "completions", to: "completions#index"
          post "completions", to: "completions#create"
          get "favorites", to: "favorites#index"
          post "favorites", to: "favorites#create"
          get "reviews", to: "reviews#index"
          post "reviews", to: "reviews#create"
          get "backlog", to: "backlog#index"
          post "backlog", to: "backlog#create"
          get "now_playing", to: "now_playing#user_index"
          get "socials", to: "user_socials#index"
          post "socials", to: "user_socials#create"
          get "journal/status", to: "journal#status"
          get "journal", to: "journal#index"
          post "journal", to: "journal#create"
          get "reminders", to: "reminders#index"
          post "reminders", to: "reminders#create"
          get "presence_prompts", to: "presence_prompts#index"
          get "presence_prompt_opts", to: "presence_prompt_opts#show"
          put "presence_prompt_opts", to: "presence_prompt_opts#update"
          get "giveaway_settings", to: "giveaway_settings#show"
          patch "giveaway_settings", to: "giveaway_settings#update"
          get "game_keys", to: "game_keys#user_index"
          get "activity_icons", to: "user_activity_icons#index"
          get "channel_counts", to: "user_channel_counts#index"
        end
      end

      resources :collections, only: %i[show update destroy]
      resources :completions, only: %i[show update destroy] do
        collection { get "leaderboard" }
      end
      resources :favorites, only: %i[show update destroy]
      resources :reviews, only: %i[show update destroy]
      resources :backlog, only: %i[show update destroy]
      resources :social_platforms, only: %i[index create]
      resources :user_socials, only: %i[show update destroy]
      # Journal search + contributors (bot parity, #103). Declared before the
      # `resources` block so the fixed `contributors` sub-path and the bare
      # `journal_entries` search index are never captured by the `:id` show
      # route. `search` is the cross-user/global entry search (`q`, `game_id`,
      # `user_id` filters); `contributors` lists users with at least one entry.
      get "journal_entries/contributors", to: "journal#contributors"
      get "journal_entries",              to: "journal#search"
      resources :journal_entries, only: %i[show update destroy], controller: "journal"
      resources :reminders, only: %i[show update destroy]
      resources :game_keys, only: %i[index create show destroy] do
        member do
          post "claim", to: "game_keys#claim"
        end
      end
      resources :release_announcements, only: %i[show create update destroy] do
        member { post "skip" }
      end
      resources :threads, only: %i[show create update] do
        member do
          post "links", to: "thread_game_links#create"
          delete "links", to: "thread_game_links#destroy_all"
          delete "links/:game_id", to: "thread_game_links#destroy"
        end
      end
      resources :gotm_entries, only: %i[index show create update destroy]
      resources :nr_gotm_entries, only: %i[index show create update destroy]
      # GOTM / NR-GOTM nominations: the round list (open read) plus single-user
      # read, upsert and round-scoped deletes for the bot's `/nominate`
      # migration (bot parity, #97). These hang off the round, not a nomination
      # id, so they live here rather than under a `resources` block. The
      # collection POST/DELETE share a path with the GET list — only the verb
      # differs.
      get    "gotm_entries/:round/nominations",          to: "nominations#gotm",        as: :gotm_entry_nominations
      get    "gotm_entries/:round/nominations/:user_id", to: "nominations#show_gotm",   as: :gotm_entry_nomination
      post   "gotm_entries/:round/nominations",          to: "nominations#create_gotm"
      delete "gotm_entries/:round/nominations/:user_id", to: "nominations#destroy_gotm"
      delete "gotm_entries/:round/nominations",          to: "nominations#destroy_all_gotm"
      get    "nr_gotm_entries/:round/nominations",          to: "nominations#nr_gotm",          as: :nr_gotm_entry_nominations
      get    "nr_gotm_entries/:round/nominations/:user_id", to: "nominations#show_nr_gotm",     as: :nr_gotm_entry_nomination
      post   "nr_gotm_entries/:round/nominations",          to: "nominations#create_nr_gotm"
      delete "nr_gotm_entries/:round/nominations/:user_id", to: "nominations#destroy_nr_gotm"
      delete "nr_gotm_entries/:round/nominations",          to: "nominations#destroy_all_nr_gotm"
      # Suggestion review sessions (bot parity, #91). Declared before
      # `resources :suggestions` so `/suggestions/review_sessions...` is never
      # captured by the suggestion `:id` member routes; the two bulk-delete
      # routes precede the resource so `expired` and the collection DELETE
      # aren't captured as member `:id` lookups.
      scope path: "suggestions" do
        delete "review_sessions/expired", to: "suggestion_review_sessions#destroy_expired"
        delete "review_sessions", to: "suggestion_review_sessions#destroy_all"
        resources :review_sessions, only: %i[index show create update destroy],
          controller: "suggestion_review_sessions"
      end
      resources :suggestions, only: %i[index show create destroy]
      resources :todos, only: %i[index show create update destroy] do
        collection { get "summary" }
      end
      resources :rss_feeds, only: %i[index show create update destroy] do
        resources :items, only: %i[index create], controller: "rss_feed_items"
      end
      resources :public_reminders, only: %i[index show create update destroy] do
        collection { get "due" }
      end
      resources :starboard, param: :message_id, only: %i[index show create update destroy]
      resources :journal_message_contexts, param: :message_id, only: %i[index show create update destroy]
      resources :voting_info, only: %i[index show create update destroy] do
        collection { get "current" }
      end
      # Bot presence history (service-only, #94). The Discord bot records each
      # `/setpresence` change and reads back the latest/recent activity as it
      # migrates `BotPresenceHistory` off direct SQL (RPGClub_GameDB#795). Plain
      # routes (no `:id` member): the list and create share a path; `latest` is
      # a fixed sub-path. Every action requires the bot bearer token.
      get  "bot_presence/latest", to: "bot_presence#latest"
      get  "bot_presence",        to: "bot_presence#index"
      post "bot_presence",        to: "bot_presence#create"
      resources :search_synonyms, only: %i[index show create update destroy]
      resources :search_synonym_groups, only: %i[index show create update destroy]
      resources :search_synonym_drafts, only: %i[index show create update destroy]
    end
  end
end
