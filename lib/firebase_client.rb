# /app/lib/firebase_client.rb
class FirebaseClient
  # Changed to :messaging_service for clarity and to match typical naming
  attr_reader :messaging_service 

  def initialize
    Rails.logger.info "FirebaseClient INIT: Starting initialization..."

    unless defined?(FirebaseAdminConfig) && FirebaseAdminConfig.app
      error_message = "Core Firebase App (FirebaseAdminConfig.app) not initialized. Check initializer."
      Rails.logger.error "FirebaseClient: #{error_message}"
      raise error_message
    end

    core_app_instance = FirebaseAdminConfig.app
    Rails.logger.info "FirebaseClient INIT: Core FirebaseApp (FirebaseAdminConfig.app) was initialized."

    begin
      # In v0.3.1, Firebase::Admin::App#messaging directly returns a new Messaging::Client instance
      # The Client's own initialize(app) takes the app instance.
      @messaging_service = core_app_instance.messaging 

      if @messaging_service && @messaging_service.is_a?(Firebase::Admin::Messaging::Client)
        Rails.logger.info "FirebaseClient INIT: Messaging service instantiated via app.messaging. Class: #{@messaging_service.class.name}"
      else
        # This case should ideally not be hit if core_app_instance.messaging behaves as per gem source
        error_message = "app.messaging did not return a valid Firebase::Admin::Messaging::Client instance. Got: #{@messaging_service.inspect}"
        Rails.logger.error "FirebaseClient: #{error_message}"
        raise error_message
      end
    rescue StandardError => e
      Rails.logger.error "FirebaseClient INIT: ERROR obtaining messaging service via app.messaging - #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n  ")}"
      raise
    end
  rescue StandardError => e # Catch errors from the top-level ensure block
    Rails.logger.error "FirebaseClient INIT: CAUGHT UNEXPECTED ERROR in initialize! #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}"
    raise
  end

  def send_tip(sent_tip_model)
    Rails.logger.info "FirebaseClient SEND_TIP: Method called for tip: #{sent_tip_model.title}"

    unless @messaging_service
      error_message = "Messaging service not available. Was FirebaseClient initialized correctly?"
      Rails.logger.error "FirebaseClient: #{error_message}"
      raise error_message
    end

    # --- BEGIN DEBUGGING (can be removed once stable) ---
    Rails.logger.debug "FirebaseClient SEND_TIP: Verifying @messaging_service methods..."
    Rails.logger.debug "  - @messaging_service class: #{@messaging_service.class.name}"
    
    available_send_methods = @messaging_service.public_methods(false).grep(/send/i)
    Rails.logger.debug "  - Own public methods matching /send/i: #{available_send_methods.inspect}" # EXPECT [:send_one, :send_all, :send_multicast]

    # Check the specific method named :send_one that we intend to use
    if @messaging_service.respond_to?(:send_one)
      send_one_method_obj = @messaging_service.method(:send_one)
      Rails.logger.debug "  - Method ':send_one' Owner: #{send_one_method_obj.owner}" # EXPECT Firebase::Admin::Messaging::Client
      Rails.logger.debug "  - Method ':send_one' Parameters: #{send_one_method_obj.parameters.inspect}" # EXPECT [[:req, :message], [:key, :dry_run]]
      Rails.logger.debug "  - Method ':send_one' Source Location: #{send_one_method_obj.source_location.inspect}"
    else
      Rails.logger.warn "  - @messaging_service does NOT respond_to? :send_one. This is unexpected!"
    end
    # --- END DEBUGGING ---

    data_payload = {
      tipTitle: sent_tip_model.title.to_s,
      tipMessage: sent_tip_model.message.to_s,
      tipImageURL: sent_tip_model.image_url.to_s,
      targetDisplayTime: sent_tip_model.target_display_info.to_s
    }

    notification_constructor_args = {
      title: sent_tip_model.title.to_s,
      body: sent_tip_model.message.to_s
    }
    notification_constructor_args[:image] = sent_tip_model.image_url.to_s if sent_tip_model.image_url.present?

    begin
      unless defined?(Firebase::Admin::Messaging::Message) && defined?(Firebase::Admin::Messaging::Notification)
        error_msg = "Firebase::Admin::Messaging::Message or ::Notification class not defined. SDK not loaded correctly?"
        Rails.logger.error "FirebaseClient SEND_TIP: #{error_msg}"
        raise error_msg # This would indicate a serious load issue
      end

      notification_object = Firebase::Admin::Messaging::Notification.new(**notification_constructor_args)
      
      # The gem's `send_one` method expects a `Firebase::Admin::Messaging::Message` object
      # as its first argument.
      firebase_message_object = Firebase::Admin::Messaging::Message.new(
        topic: 'developer_tips', # Your existing topic
        data: data_payload,
        notification: notification_object
        # Other Message attributes (android:, apns:, fcm_options:) can be added here if needed
      )
      Rails.logger.debug "FirebaseClient SEND_TIP: Constructed Firebase::Admin::Messaging::Message object: #{firebase_message_object.inspect}"

      # --- THE CORRECTED CALL ---
      Rails.logger.info "FirebaseClient SEND_TIP: Attempting call with @messaging_service.send_one(firebase_message_object)..."
      response = @messaging_service.send_one(firebase_message_object) # `dry_run: false` is the default

      # If you want to explicitly set dry_run for testing:
      # response = @messaging_service.send_one(firebase_message_object, dry_run: true)


      Rails.logger.info "FirebaseClient SEND_TIP: FCM call `send_one` successful. Response: #{response.inspect}" # response here is usually a message ID string
      return response

    rescue ArgumentError => ae
      # This could be from Message.new, Notification.new, or send_one if arguments are still wrong
      error_message = "ArgumentError during Message/Notification construction or client.send_one: #{ae.message}"
      Rails.logger.error "FirebaseClient SEND_TIP: #{error_message}\nBacktrace:\n#{ae.backtrace.join("\n  ")}"
      raise ae # Re-raise
    # No longer expecting TypeError from Kernel#send if send_one is called correctly
    rescue Google::Apis::Error => gae # Catch errors from the Google API client, as seen in gem source
      # The gem's send_one method rescues Google::Apis::Error and then calls parse_fcm_error
      # So the error you catch here might already be a custom Firebase::Admin::Error subclass
      error_message = "Google API Error during FCM send_one: #{gae.class.name} - #{gae.message}"
      Rails.logger.error "FirebaseClient SEND_TIP: #{error_message}\nStatus Code: #{gae.status_code if gae.respond_to?(:status_code)}\nBody: #{gae.body if gae.respond_to?(:body)}\nBacktrace:\n#{gae.backtrace.join("\n  ")}"
      # You might want to re-raise a more generic error or handle specific FCM error types
      raise gae # Re-raise
    rescue Firebase::Admin::Messaging::Error => fme # Catch specific FCM errors if the gem re-raises them as such
      error_message = "Firebase Messaging Error during FCM send_one: #{fme.class.name} - #{fme.message}"
      Rails.logger.error "FirebaseClient SEND_TIP: #{error_message}\nBacktrace:\n#{fme.backtrace.join("\n  ")}"
      raise fme # Re-raise
    rescue StandardError => e # Catch any other unexpected errors
      error_message = "Unexpected error during FCM send_one: #{e.class.name} - #{e.message}"
      Rails.logger.error "FirebaseClient SEND_TIP: #{error_message}\nBacktrace:\n#{e.backtrace.join("\n  ")}"
      raise e # Re-raise
    end
  end
end
