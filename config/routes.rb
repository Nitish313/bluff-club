Rails.application.routes.draw do
  root "pages#home"
  get "r/:code", to: "pages#home", as: :room_link
  post "rooms", to: "rooms#create"
  post "players", to: "players#create"
  get "up", to: "rails/health#show", as: :rails_health_check
end
