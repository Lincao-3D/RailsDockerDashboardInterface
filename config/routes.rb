Rails.application.routes.draw do
  devise_for :admin_users

  # Root route for dashboard index
  root to: 'dashboard#index'

  # SentTips routes: only create, plus a collection route to clear history
  resources :sent_tips, only: [:create] do
    collection do
      delete 'clear_history', to: 'sent_tips#clear_all_history', as: 'clear_history'
    end
  end

  # Post route for dashboard quick image upload
  post '/dashboard/upload_quick_image', to: 'dashboard#upload_quick_image'

  # API namespace version 1 routes
  namespace :api do
    namespace :v1 do
      resources :devices, only: [:create]
    end
  end
end
