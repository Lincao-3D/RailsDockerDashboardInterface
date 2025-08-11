# config/initializers/00_firebase_admin.rb

Rails.logger.debug "DEBUG: Initializer: LOADING NOW (v0.3.1 keyword-aware)..."

# Check if we are in assets:precompile or test environment to skip Firebase init gracefully
SKIP_FIREBASE_INIT_IF_KEY_MISSING = ENV['ASSETS_PRECOMPILE_CONTEXT'] == 'true' || Rails.env.test?
Rails.logger.debug "DEBUG: Initializer: SKIP_FIREBASE_INIT_IF_KEY_MISSING evaluated to: #{SKIP_FIREBASE_INIT_IF_KEY_MISSING}"

# Early return if skipping initialization due to precompile or test env
return if SKIP_FIREBASE_INIT_IF_KEY_MISSING

begin
  Rails.logger.debug "DEBUG: Initializer: Requiring 'firebase-admin-sdk' and 'firebase/admin/messaging/client'..."
  require 'firebase-admin-sdk'
  require 'firebase/admin/messaging/client' # Ensures Messaging client is loaded
  Rails.logger.debug "DEBUG: Initializer: Gems required."

  unless defined?(Firebase::Admin::App) && defined?(Firebase::Admin::Credentials) && defined?(Firebase::Admin::Config)
    error_message = "Firebase Admin SDK core components (App, Credentials, Config) not defined. Check gem installation."
    Rails.logger.error error_message
    raise error_message # Fundamental issue, stop boot
  end
  Rails.logger.debug "DEBUG: Initializer: Core Firebase components ARE defined."

  # 1. Prepare Credentials path
  absolute_credentials_path = if Rails.env.production? && ENV['RENDER'] == 'true'
                                # Render secret file path convention
                                render_secret_filename = 'firebase_key.json' # Must match secret file name in Render dashboard
                                File.join('/etc/secrets', render_secret_filename)
                              elsif ENV['FIREBASE_JSON_PATH'].present?
                                env_path = ENV['FIREBASE_JSON_PATH']
                                env_path.start_with?('/') ? env_path : Rails.root.join(env_path).to_s
                              else
                                # Default path in local dev or fallback
                                Rails.root.join('config', 'firebase_key.json').to_s
                              end

  Rails.logger.info "Firebase Initializer: Using Credentials Path: #{absolute_credentials_path}"

  if File.exist?(absolute_credentials_path)
    firebase_credentials = Firebase::Admin::Credentials.from_file(absolute_credentials_path)
    Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::Credentials object created from file."

    # 2. Prepare optional Firebase config
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

    # 3. Initialize Firebase App instance
    Rails.logger.debug "DEBUG: Initializer: Attempting Firebase::Admin::App.new(credentials: ..., config: ...)"
    firebase_app_instance = Firebase::Admin::App.new(
      credentials: firebase_credentials,
      config: firebase_config_object
    )
    Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::App.new() called successfully."

    # Make Firebase app instance globally accessible
    module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
    FirebaseAdminConfig.app = firebase_app_instance

    if FirebaseAdminConfig.app
      project_id_val = FirebaseAdminConfig.app.instance_variable_get(:@project_id) rescue "Error accessing @project_id"
      Rails.logger.info "DEBUG: Initializer: FirebaseAdminConfig.app assigned. Effective Project ID: #{project_id_val}"
    else
      Rails.logger.error "DEBUG: Initializer: FirebaseAdminConfig.app is NIL after assignment despite key file existing. Unexpected."
    end

  elsif SKIP_FIREBASE_INIT_IF_KEY_MISSING
    # We can skip initialization gracefully during precompile/test if file is missing
    Rails.logger.warn "Firebase Initializer: Credentials file NOT FOUND at #{absolute_credentials_path}."
    Rails.logger.warn "Firebase Initializer: Skipping full Firebase SDK initialization due to build/test context."

    module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
    FirebaseAdminConfig.app = nil
    Rails.logger.info "DEBUG: Initializer: FirebaseAdminConfig.app set to nil due to missing key in build/test context."

  else
    # Credentials file missing in a critical environment - halt startup
    error_message = "Firebase credentials file NOT FOUND at #{absolute_credentials_path}. SDK cannot initialize. This is a fatal error."
    Rails.logger.error error_message
    if Rails.env.production? && ENV['RENDER'] == 'true'
      Rails.logger.error "Firebase Initializer: On RENDER, this means the secret file '#{File.basename(absolute_credentials_path)}' was not found or misconfigured."
    end
    raise error_message
  end

rescue StandardError => e
  Rails.logger.error "DEBUG: Initializer: ERROR during Firebase SDK initialization: #{e.class.name} - #{e.message}"
  Rails.logger.error "DEBUG: Initializer: Backtrace:\n #{e.backtrace.join("\n ")}"

  module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
  FirebaseAdminConfig.app = nil

  raise # Re-raise to halt boot on critical failure
end

Rails.logger.debug "DEBUG: Initializer: HAS FINISHED EXECUTING."
