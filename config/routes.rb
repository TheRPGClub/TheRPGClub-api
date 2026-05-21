Rails.application.routes.draw do
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
        end
      end

      resources :platforms, only: %i[index show]
      resources :regions, only: %i[index show]

      resources :users, param: :user_id, only: %i[index show] do
        member do
          get "avatar"
          get "profile-image"
          get "collections", to: "collections#index"
          post "collections", to: "collections#create"
          get "completions", to: "completions#index"
          post "completions", to: "completions#create"
          get "favorites", to: "favorites#index"
          post "favorites", to: "favorites#create"
          get "backlog", to: "backlog#index"
          post "backlog", to: "backlog#create"
          get "socials", to: "user_socials#index"
          post "socials", to: "user_socials#create"
        end
      end

      resources :collections, only: %i[show update destroy]
      resources :completions, only: %i[show update destroy]
      resources :favorites, only: %i[show update destroy]
      resources :backlog, only: %i[show update destroy]
      resources :social_platforms, only: %i[index create]
      resources :user_socials, only: %i[show update destroy]
      resources :gotm_entries, only: %i[index show]
      resources :nr_gotm_entries, only: %i[index show]
      resources :suggestions, only: %i[index show create destroy]
      resources :todos, only: %i[index show create update destroy] do
        collection { get "summary" }
      end
      resources :rss_feeds, only: %i[index show create update destroy]
      resources :public_reminders, only: %i[index show create update destroy]
      resources :starboard, param: :message_id, only: %i[index show create update destroy]
      resources :voting_info, only: %i[index show create update destroy]
    end
  end
end
