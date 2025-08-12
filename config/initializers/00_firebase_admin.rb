# config/initializers/00_firebase_admin.rb

Rails.logger.debug "DEBUG: Initializer: LOADING NOW (Firebase Admin SDK)..."

# Determine if Firebase initialization should be skipped (e.g., during assets:precompile or in test env)
SHOULD_SKIP_FIREBASE_INIT = ENV['ASSETS_PRECOMPILE_CONTEXT'] == 'true' || Rails.env.test?
Rails.logger.debug "DEBUG: Initializer: SHOULD_SKIP_FIREBASE_INIT evaluated to: #{SHOULD_SKIP_FIREBASE_INIT}"

if SHOULD_SKIP_FIREBASE_INIT
  Rails.logger.warn "Firebase Initializer: Skipping Firebase SDK initialization due to ASSETS_PRECOMPILE_CONTEXT or test environment."
  # Ensure FirebaseAdminConfig.app is defined and nil so app can boot without errors if it references this
  module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
  FirebaseAdminConfig.app = nil
  return # EXIT EARLY
end

# If we've reached here, Firebase initialization is expected to proceed.
begin
  Rails.logger.debug "DEBUG: Initializer: Requiring 'firebase-admin-sdk' and 'firebase/admin/messaging/client'..."
  require 'firebase-admin-sdk'
  require 'firebase/admin/messaging/client'
  Rails.logger.debug "DEBUG: Initializer: Firebase gems required."

  unless defined?(Firebase::Admin::App) && defined?(Firebase::Admin::Credentials) && defined?(Firebase::Admin::Config)
    error_message = "Firebase Admin SDK core components (App, Credentials, Config) not defined. Check gem installation."
    Rails.logger.error error_message
    raise error_message # Fundamental issue, stop boot
  end
  Rails.logger.debug "DEBUG: Initializer: Core Firebase components ARE defined."

  firebase_credentials = nil
  credential_source_info = "" # For logging
	# debug logs
    Rails.logger.info "Firebase Initializer: Checking ENV['FIREBASE_CREDENTIALS_JSON']. Length: #{ENV['FIREBASE_CREDENTIALS_JSON']&.length}. Present?: #{ENV['FIREBASE_CREDENTIALS_JSON'].present?}."
    Rails.logger.debug "Firebase Initializer: First 50 chars of ENV['FIREBASE_CREDENTIALS_JSON']: #{ENV['FIREBASE_CREDENTIALS_JSON']&.first(50)}"
  # 1. Attempt to load credentials from ENV variable first
  if ENV['FIREBASE_CREDENTIALS_JSON'].present?
    begin
      firebase_credentials = Firebase::Admin::Credentials.from_json(ENV['FIREBASE_CREDENTIALS_JSON'])
      credential_source_info = "ENV['FIREBASE_CREDENTIALS_JSON']"
      Rails.logger.info "Firebase Initializer: Successfully loaded credentials from #{credential_source_info}."
    rescue JSON::ParserError => e
      error_message = "Firebase Initializer: Failed to parse JSON from FIREBASE_CREDENTIALS_JSON. Error: #{e.message}"
      Rails.logger.error error_message
      raise error_message # Malformed JSON is a critical configuration error
    rescue StandardError => e
      error_message = "Firebase Initializer: Error creating credentials from FIREBASE_CREDENTIALS_JSON. Error: #{e.class.name} - #{e.message}"
      Rails.logger.error error_message
      raise error_message
    end
  end

  # 2. If not loaded from ENV, attempt to load from file path
  unless firebase_credentials
    absolute_credentials_path = if Rails.env.production? && ENV['RENDER'] == 'true'
                                  render_secret_filename = 'firebase_key.json' # Must match secret file name in Render dashboard
                                  File.join('/etc/secrets', render_secret_filename)
                                elsif ENV['FIREBASE_JSON_PATH'].present?
                                  env_path = ENV['FIREBASE_JSON_PATH']
                                  env_path.start_with?('/') ? env_path : Rails.root.join(env_path).to_s
                                else
                                  Rails.root.join('config', 'firebase_key.json').to_s # Default for local dev
                                end
    
    Rails.logger.info "Firebase Initializer: #{credential_source_info.presence || "ENV['FIREBASE_CREDENTIALS_JSON'] not used or failed"}. Attempting file path: #{absolute_credentials_path}"
    credential_source_info = "file at #{absolute_credentials_path}" # Update for subsequent logging

    if File.exist?(absolute_credentials_path)
      begin
        firebase_credentials = Firebase::Admin::Credentials.from_file(absolute_credentials_path)
        Rails.logger.info "Firebase Initializer: Successfully loaded credentials from #{credential_source_info}."
      rescue Errno::EACCES => e # Specific catch for file permission issues
        error_message = "Firebase Initializer: Permission denied when trying to read credentials from #{credential_source_info}. Error: #{e.message}"
        Rails.logger.error error_message
        if Rails.env.production? && ENV['RENDER'] == 'true'
            Rails.logger.error "Firebase Initializer: On RENDER, ensure the service (running as UID #{Process.uid}) has read permissions for the Secret File: #{absolute_credentials_path}."
        end
        raise error_message # Re-raise permission error
      rescue StandardError => e # Catch other errors like malformed JSON in file
        error_message = "Firebase Initializer: Error creating credentials from #{credential_source_info}. Error: #{e.class.name} - #{e.message}"
        Rails.logger.error error_message
        raise error_message
      end
    else
      Rails.logger.warn "Firebase Initializer: Credentials file NOT FOUND at #{absolute_credentials_path}."
      # Credentials still nil at this point if file doesn't exist
    end
  end

  # 3. If credentials are still not loaded, it's a fatal error (as we are past the SHOULD_SKIP_FIREBASE_INIT check)
  unless firebase_credentials
    error_message_detail = if ENV['FIREBASE_CREDENTIALS_JSON'].present?
                             "ENV['FIREBASE_CREDENTIALS_JSON'] was present but failed to yield valid credentials."
                           elsif defined?(absolute_credentials_path)
                             "ENV['FIREBASE_CREDENTIALS_JSON'] was not set/empty, AND file at '#{absolute_credentials_path}' was not found or failed to load."
                           else
                             "No valid source (ENV var or file path) for Firebase credentials was successfully processed."
                           end
    final_error_message = "Firebase Initializer: CRITICAL - Firebase credentials could not be loaded. #{error_message_detail}"
    Rails.logger.error final_error_message
    raise final_error_message # Halt boot
  end

  # If we have `firebase_credentials`, proceed with Firebase App initialization:
  Rails.logger.debug "DEBUG: Initializer: Firebase credentials obtained from #{credential_source_info}. Proceeding with Firebase App initialization."

  firebase_config_options = {}
  project_id_from_env = ENV['FCM_PROJECT_ID']
  if project_id_from_env.present?
    firebase_config_options[:project_id] = project_id_from_env
    Rails.logger.debug "DEBUG: Initializer: Using Project ID from ENV['FCM_PROJECT_ID']: #{project_id_from_env}"
  else
    Rails.logger.debug "DEBUG: Initializer: FCM_PROJECT_ID not set in ENV. Relying on credentials or defaults."
  end

  firebase_config_object = firebase_config_options.empty? ? nil : Firebase::Admin::Config.new(**firebase_config_options)
  if firebase_config_object
    Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::Config object created with options: #{firebase_config_options.inspect}"
  else
    Rails.logger.debug "DEBUG: Initializer: No explicit config options provided; default config will be used."
  end

  Rails.logger.debug "DEBUG: Initializer: Attempting Firebase::Admin::App.new(credentials: ..., config: ...)"
  firebase_app_instance = Firebase::Admin::App.new(
    credentials: firebase_credentials,
    config: firebase_config_object
  )
  Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::App.new() called successfully."

  module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
  FirebaseAdminConfig.app = firebase_app_instance

  if FirebaseAdminConfig.app
    project_id_val = FirebaseAdminConfig.app.instance_variable_get(:@project_id) rescue "Error accessing @project_id"
    Rails.logger.info "DEBUG: Initializer: FirebaseAdminConfig.app assigned. Effective Project ID: #{project_id_val}"
  else
    # This case should ideally not be reached if App.new succeeded without error
    Rails.logger.error "DEBUG: Initializer: FirebaseAdminConfig.app is NIL after assignment. This is unexpected."
  end

rescue StandardError => e # Catch-all for any other unexpected error during the process
  Rails.logger.error "DEBUG: Initializer: UNHANDLED ERROR during Firebase SDK initialization: #{e.class.name} - #{e.message}"
  Rails.logger.error "DEBUG: Initializer: Backtrace:\n #{e.backtrace.join("\n ")}"
  module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
  FirebaseAdminConfig.app = nil
  raise # Re-raise to halt boot
end

Rails.logger.debug "DEBUG: Initializer: HAS FINISHED EXECUTING (unless returned early or raised)."
