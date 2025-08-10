Rails.application.routes.draw do
  devise_for :admin_users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  # get "up" => "rails/health#show", as: :rails_health_check

  root to: 'dashboard#index'
  resources :sent_tips, only: [:create] do
	collection do
		delete 'clear_history', to: 'sent_tips#clear_all_history', as: 'clear_history' # For dashboard
    end
  end
  post '/dashboard/upload_quick_image', to: 'dashboard#upload_quick_image'

  # Defines the root path route ("/")
  # root "posts#index"
end
