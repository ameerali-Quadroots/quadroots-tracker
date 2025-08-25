Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  devise_for :users

  resources :time_clocks, only: [] do
    collection do
      post 'clock_in'
      post 'clock_out'
    end

    resources :breaks, only: [] do
      collection do
        post 'break_in'
      end
      member do
        post 'break_out'
      end
    end
  end

  root 'dashboard#index'

  post '/clock_in', to: 'time_clocks#clock_in', as: 'clock_in'
  post '/clock_out', to: 'time_clocks#clock_out', as: 'clock_out'
end
