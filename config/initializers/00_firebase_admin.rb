# /config/initializers/00_firebase_admin.rb
Rails.logger.debug "DEBUG: Initializer: LOADING NOW (v0.3.1 keyword-aware)..."

begin
  Rails.logger.debug "DEBUG: Initializer: Requiring 'firebase-admin-sdk' and 'firebase/admin/messaging/client'..."
  require 'firebase-admin-sdk'
  require 'firebase/admin/messaging/client' # Ensures Messaging::Client is loaded
  Rails.logger.debug "DEBUG: Initializer: Gems required."

  unless defined?(Firebase::Admin::App) && defined?(Firebase::Admin::Credentials) && defined?(Firebase::Admin::Config)
    error_message = "Firebase Admin SDK core components (App, Credentials, Config) not defined. Check gem installation."
    Rails.logger.error error_message
    raise error_message
  end
  Rails.logger.debug "DEBUG: Initializer: Core Firebase components ARE defined."

  # 1. Prepare Credentials
  # Determine credentials path (ENV var or default)
  env_credentials_path = ENV['FIREBASE_JSON_PATH']
  default_relative_credentials_path = 'config/firebase_key.json'
  absolute_credentials_path = if env_credentials_path.present?
                                env_credentials_path.start_with?('/') ? env_credentials_path : Rails.root.join(env_credentials_path).to_s
                              else
                                Rails.root.join(default_relative_credentials_path).to_s
                              end

  Rails.logger.info "Firebase Initializer: Using Credentials Path: #{absolute_credentials_path}"
  unless File.exist?(absolute_credentials_path)
    error_message = "Firebase credentials file NOT FOUND at #{absolute_credentials_path}. SDK cannot initialize."
    Rails.logger.error error_message
    raise error_message
  end
  
  firebase_credentials = Firebase::Admin::Credentials.from_file(absolute_credentials_path)
  Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::Credentials object created from file."

  # 2. Prepare Config (optional, as the gem can derive from ENV or credentials)
  # The gem's App#initialize does: @config = config || Config.from_env
  # And then: @project_id = @config.project_id || @credentials.project_id
  # So, if your credentials file has the project_id, explicit config might not be strictly needed for project_id.
  # However, it's safer to be explicit if you have it.
  
  firebase_config_options = {}
  project_id_from_env = ENV['FCM_PROJECT_ID'] # Your existing ENV var
  if project_id_from_env.present?
    firebase_config_options[:project_id] = project_id_from_env
    Rails.logger.debug "DEBUG: Initializer: Using Project ID from ENV['FCM_PROJECT_ID']: #{project_id_from_env}"
  else
    Rails.logger.debug "DEBUG: Initializer: FCM_PROJECT_ID not set in ENV. Relying on credentials file or other ENV for Project ID."
  end
  
  # service_account_id is another option for Config, add if you use it
  # if ENV['FIREBASE_SERVICE_ACCOUNT_ID'].present?
  #   firebase_config_options[:service_account_id] = ENV['FIREBASE_SERVICE_ACCOUNT_ID']
  # end

  # Create a Config object if you have options, otherwise pass nil and let App#initialize use Config.from_env
  firebase_config_object = firebase_config_options.empty? ? nil : Firebase::Admin::Config.new(**firebase_config_options)
  if firebase_config_object
     Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::Config object created with options: #{firebase_config_options.inspect}"
  else
     Rails.logger.debug "DEBUG: Initializer: No explicit config options provided; App will use Config.from_env or derive from credentials."
  end

  # 3. Initialize Firebase::Admin::App with keyword arguments
  Rails.logger.debug "DEBUG: Initializer: Attempting Firebase::Admin::App.new(credentials: ..., config: ...)"
  firebase_app_instance = Firebase::Admin::App.new(
    credentials: firebase_credentials,
    config: firebase_config_object # Pass the Config object, or nil if no specific config opts
  )
  Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::App.new() called successfully."

  # Expose it globally
  module FirebaseAdminConfig
    class << self
      attr_accessor :app
    end
  end
  FirebaseAdminConfig.app = firebase_app_instance

  if FirebaseAdminConfig.app
    # Access @project_id via instance_variable_get as there's no attr_reader in v0.3.1 gem source shown
    project_id_val = FirebaseAdminConfig.app.instance_variable_get(:@project_id) rescue "Error accessing @project_id"
    Rails.logger.info "DEBUG: Initializer: FirebaseAdminConfig.app assigned. Effective Project ID: #{project_id_val}"
  else
    Rails.logger.error "DEBUG: Initializer: FirebaseAdminConfig.app is NIL after assignment! This is unexpected if App.new didn't raise."
  end

rescue StandardError => e
  Rails.logger.error "DEBUG: Initializer: ERROR during Firebase SDK initialization: #{e.class.name} - #{e.message}"
  Rails.logger.error "DEBUG: Initializer: Backtrace:\n #{e.backtrace.join("\n ")}"
  # Ensure FirebaseAdminConfig.app is nil if initialization fails
  if defined?(FirebaseAdminConfig)
    FirebaseAdminConfig.app = nil
  end
  raise # Re-raise to halt application boot if critical
end

Rails.logger.debug "DEBUG: Initializer: HAS FINISHED EXECUTING."

