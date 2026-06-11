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

      resources :games, only: %i[index show] do
        resources :images, only: %i[index create update destroy], controller: "game_images"

        member do
          post "refresh-images", to: "games#refresh_images"
          get "relations", to: "games#relations"
          get "releases", to: "games#releases"
          get "now_playing", to: "now_playing#index"
          get "completions", to: "completions#game_index"
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
          get "journal", to: "journal#index"
          post "journal", to: "journal#create"
          get "reminders", to: "reminders#index"
          post "reminders", to: "reminders#create"
          get "presence_prompts", to: "presence_prompts#index"
          get "presence_prompt_opts", to: "presence_prompt_opts#show"
          put "presence_prompt_opts", to: "presence_prompt_opts#update"
          get "game_keys", to: "game_keys#user_index"
          get "activity_icons", to: "user_activity_icons#index"
          get "channel_counts", to: "user_channel_counts#index"
        end
      end

      resources :collections, only: %i[show update destroy]
      resources :completions, only: %i[show update destroy]
      resources :favorites, only: %i[show update destroy]
      resources :reviews, only: %i[show update destroy]
      resources :backlog, only: %i[show update destroy]
      resources :social_platforms, only: %i[index create]
      resources :user_socials, only: %i[show update destroy]
      resources :journal_entries, only: %i[show update destroy], controller: "journal"
      resources :reminders, only: %i[show update destroy]
      resources :game_keys, only: %i[index create] do
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
      resources :gotm_entries, only: %i[index show]
      resources :nr_gotm_entries, only: %i[index show]
      get "gotm_entries/:round/nominations", to: "nominations#gotm", as: :gotm_entry_nominations
      get "nr_gotm_entries/:round/nominations", to: "nominations#nr_gotm", as: :nr_gotm_entry_nominations
      resources :suggestions, only: %i[index show create destroy]
      resources :todos, only: %i[index show create update destroy] do
        collection { get "summary" }
      end
      resources :rss_feeds, only: %i[index show create update destroy]
      resources :public_reminders, only: %i[index show create update destroy]
      resources :starboard, param: :message_id, only: %i[index show create update destroy]
      resources :journal_message_contexts, param: :message_id, only: %i[index show create update destroy]
      resources :voting_info, only: %i[index show create update destroy]
      resources :search_synonyms, only: %i[index show create update destroy]
      resources :search_synonym_groups, only: %i[index show create update destroy]
      resources :search_synonym_drafts, only: %i[index show create update destroy]
    end
  end
end
