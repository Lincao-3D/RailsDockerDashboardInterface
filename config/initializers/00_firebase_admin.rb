# config/initializers/00_firebase_admin.rb
Rails.logger.debug "DEBUG: Initializer: LOADING NOW (v0.3.1 keyword-aware)..."

# Check if we are in an assets:precompile rake task context or other build/test context
# ENV['ASSETS_PRECOMPILE_CONTEXT'] will be set to 'true' in Dockerfile during assets:precompile
# This allows the app to boot for asset compilation without requiring runtime secrets.
SKIP_FIREBASE_INIT_IF_KEY_MISSING = ENV['ASSETS_PRECOMPILE_CONTEXT'] == 'true' || Rails.env.test?

Rails.logger.debug "DEBUG: Initializer: SKIP_FIREBASE_INIT_IF_KEY_MISSING evaluated to: #{SKIP_FIREBASE_INIT_IF_KEY_MISSING}"

begin
  Rails.logger.debug "DEBUG: Initializer: Requiring 'firebase-admin-sdk' and 'firebase/admin/messaging/client'..."
  require 'firebase-admin-sdk'
  require 'firebase/admin/messaging/client' # Ensures Messaging::Client is loaded
  Rails.logger.debug "DEBUG: Initializer: Gems required."

  unless defined?(Firebase::Admin::App) && defined?(Firebase::Admin::Credentials) && defined?(Firebase::Admin::Config)
    error_message = "Firebase Admin SDK core components (App, Credentials, Config) not defined. Check gem installation."
    Rails.logger.error error_message
    raise error_message # This is a fundamental issue, always raise.
  end
  Rails.logger.debug "DEBUG: Initializer: Core Firebase components ARE defined."

  # 1. Prepare Credentials
  # Determine credentials path
  absolute_credentials_path = if Rails.env.production? && ENV['RENDER'] == 'true'
                                # --- RENDER SPECIFIC PATH ---
                                render_secret_filename = 'firebase_key.json' # IMPORTANT: Match this to Render UI
                                File.join('/etc/secrets', render_secret_filename)
                                # --- END RENDER SPECIFIC PATH ---
                              elsif ENV['FIREBASE_JSON_PATH'].present?
                                # Use ENV var if provided (and not on Render, or Render path takes precedence)
                                env_path = ENV['FIREBASE_JSON_PATH']
                                env_path.start_with?('/') ? env_path : Rails.root.join(env_path).to_s
                              else
                                # Default for local development/other environments
                                Rails.root.join('config', 'firebase_key.json').to_s
                              end

  Rails.logger.info "Firebase Initializer: Using Credentials Path: #{absolute_credentials_path}"

  if File.exist?(absolute_credentials_path)
    firebase_credentials = Firebase::Admin::Credentials.from_file(absolute_credentials_path)
    Rails.logger.debug "DEBUG: Initializer: Firebase::Admin::Credentials object created from file."

    # 2. Prepare Config (optional, as the gem can derive from ENV or credentials)
    firebase_config_options = {}
    project_id_from_env = ENV['FCM_PROJECT_ID'] # Your existing ENV var
    if project_id_from_env.present?
      firebase_config_options[:project_id] = project_id_from_env
      Rails.logger.debug "DEBUG: Initializer: Using Project ID from ENV['FCM_PROJECT_ID']: #{project_id_from_env}"
    else
      Rails.logger.debug "DEBUG: Initializer: FCM_PROJECT_ID not set in ENV. Relying on credentials file or other ENV for Project ID."
    end

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
    module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
    FirebaseAdminConfig.app = firebase_app_instance

    if FirebaseAdminConfig.app
      project_id_val = FirebaseAdminConfig.app.instance_variable_get(:@project_id) rescue "Error accessing @project_id"
      Rails.logger.info "DEBUG: Initializer: FirebaseAdminConfig.app assigned. Effective Project ID: #{project_id_val}"
    else
      # This case should ideally not be hit if App.new didn't raise and file existed
      Rails.logger.error "DEBUG: Initializer: FirebaseAdminConfig.app is NIL after assignment despite key file existing! This is unexpected if App.new didn't raise."
    end

  elsif SKIP_FIREBASE_INIT_IF_KEY_MISSING
    # File does not exist, but we are in a context (like assets:precompile or test) where we can skip full initialization.
    Rails.logger.warn "Firebase Initializer: Credentials file NOT FOUND at #{absolute_credentials_path}."
    Rails.logger.warn "Firebase Initializer: Gracefully skipping full Firebase SDK initialization due to build/test context (SKIP_FIREBASE_INIT_IF_KEY_MISSING is true)."
    # Ensure FirebaseAdminConfig.app is defined as nil so the application can still boot for tasks like assets:precompile.
    module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
    FirebaseAdminConfig.app = nil
    Rails.logger.info "DEBUG: Initializer: FirebaseAdminConfig.app set to nil due to build/test context and missing key."
  else
    # File does not exist, and we are NOT in a context where we can skip it (e.g., runtime production, development).
    error_message = "Firebase credentials file NOT FOUND at #{absolute_credentials_path}. SDK cannot initialize. This is a fatal error for the current environment."
    Rails.logger.error error_message
    if Rails.env.production? && ENV['RENDER'] == 'true'
      Rails.logger.error "Firebase Initializer: On RENDER, this means the 'Secret File' named '#{File.basename(absolute_credentials_path)}' was not found or not correctly configured in the Render dashboard."
    end
    raise error_message # Halt boot if credentials are not found in a critical runtime environment
  end

rescue StandardError => e
  Rails.logger.error "DEBUG: Initializer: ERROR during Firebase SDK initialization: #{e.class.name} - #{e.message}"
  Rails.logger.error "DEBUG: Initializer: Backtrace:\n #{e.backtrace.join("\n ")}"
  # Ensure FirebaseAdminConfig.app is nil if initialization fails catastrophically
  module FirebaseAdminConfig; class << self; attr_accessor :app; end; end unless defined?(FirebaseAdminConfig)
  FirebaseAdminConfig.app = nil
  raise # Re-raise to halt application boot if critical
end

Rails.logger.debug "DEBUG: Initializer: HAS FINISHED EXECUTING."
