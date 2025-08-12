# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

    # db/seeds.rb
    # For initial admin user creation in production.
    # Ensure these ENV variables are set in your production environment (e.g., Render).
    # For local development, you might set them in .env or rely on defaults.

    # It's good practice to make sure these are set in production,
    # otherwise, the seed might fail or use insecure defaults.
    # You could add a check:
    if Rails.env.production? && (ENV['INITIAL_ADMIN_EMAIL'].blank? || ENV['INITIAL_ADMIN_PASSWORD'].blank?)
      raise "Missing INITIAL_ADMIN_EMAIL or INITIAL_ADMIN_PASSWORD for production seed!"
    end

    admin_email = ENV.fetch('INITIAL_ADMIN_EMAIL', 'admin@example.com') # Default for local/dev if not set
    admin_password = ENV.fetch('INITIAL_ADMIN_PASSWORD', 'yourSuperSecureP@$$wOrd') # Default for local/dev

    if AdminUser.find_by(email: admin_email).nil?
      AdminUser.create!(
        email: admin_email,
        password: admin_password,
        password_confirmation: admin_password
        # Add any other required attributes for AdminUser here
      )
      puts "CREATED ADMIN USER: #{admin_email}"
    else
      puts "Admin user #{admin_email} already exists."
    end