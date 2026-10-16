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
      get "play/:share_code", to: "play#show", as: :play
      post "play/:share_code/sessions", to: "play_sessions#create", as: :play_sessions
      post "play/:share_code/sessions/:session_id/answers", to: "play_answers#create", as: :play_answers
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
