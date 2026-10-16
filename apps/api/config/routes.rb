Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      resources :activities, only: :create do
        resources :publications, only: :create, controller: "publications"
      end
      get "play/:share_code", to: "play#show", as: :play
      post "play/:share_code/attempts", to: "attempts#create", as: :play_attempts
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
