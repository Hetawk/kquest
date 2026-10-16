Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "auth/csrf", to: "csrf#show"
      get "me", to: "me#show"
      delete "auth/session", to: "auth/sessions#destroy"
      match "auth/google_oauth2/callback", to: "auth/google_callbacks#create", via: %i[get post]
      get "auth/failure", to: "auth/google_callbacks#failure"
      post "assets/upload", to: "assets#create"
      resources :activities, only: :create do
        resources :publications, only: :create, controller: "publications"
      end
      post "activities/:activity_id/game_rooms", to: "game_rooms#create"
      get "game_rooms/:room_code", to: "game_rooms#show", as: :game_room
      post "game_rooms/:room_code/participants", to: "game_rooms#join"
      patch "game_rooms/:room_code/participants/:session_id", to: "game_rooms#update"
      post "game_rooms/:room_code/start", to: "game_rooms#start"
      post "game_rooms/:room_code/advance", to: "game_rooms#advance"
      post "game_rooms/:room_code/participants/:session_id/answers", to: "game_rooms#answer"
      get "play/:share_code", to: "play#show", as: :play
      get "play/:share_code/leaderboard", to: "play_leaderboards#show"
      post "play/:share_code/sessions", to: "play_sessions#create", as: :play_sessions
      patch "play/:share_code/sessions/:session_id", to: "play_sessions#update"
      post "play/:share_code/sessions/:session_id/answers", to: "play_answers#create", as: :play_answers
      get "join/:code", to: "join_codes#show"
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
