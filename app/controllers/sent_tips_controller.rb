class SentTipsController < ApplicationController
  # Protect from CSRF attacks, except when content type is JSON (like API requests)
  protect_from_forgery with: :exception, unless: -> { request.format.json? }

  # Require admin user authentication for all actions except :create
  before_action :authenticate_admin_user!, except: [:create]

  # Handle missing parameters with JSON error response
  rescue_from ActionController::ParameterMissing do |exception|
    render json: { error: "Required parameter missing: #{exception.param}" }, status: :bad_request
  end

  def create
    @sent_tip = SentTip.new(sent_tip_params)
    @sent_tip.sent_at = Time.current

    begin
      fcm_client = FirebaseClient.new
      fcm_response_raw = fcm_client.send_tip(@sent_tip)
      if fcm_response_raw.is_a?(String) && fcm_response_raw.include?('/messages/')
        @sent_tip.fcm_message_id = fcm_response_raw
      elsif fcm_response_raw.is_a?(Hash) && fcm_response_raw['name'].present?
        @sent_tip.fcm_message_id = fcm_response_raw['name']
      else
        Rails.logger.warn "FCM send was likely successful but response format was unexpected: #{fcm_response_raw.inspect}"
        @sent_tip.fcm_message_id = fcm_response_raw.to_s
      end
      @sent_tip.status = 'sent'
      flash_message = "Tip sent successfully."
    rescue => e
      Rails.logger.error "Error during FCM send process: #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}"
      @sent_tip.status = 'failed'
      @sent_tip.error_message = "#{e.class.name}: #{e.message}"
      flash_message = "Tip failed to send: #{@sent_tip.error_message}"
    end

    if @sent_tip.save
      # flash_message already set above
    else
      Rails.logger.error "Failed to save SentTip record: #{@sent_tip.errors.full_messages.join(", ")}"
      save_error_message = "Failed to save record: #{@sent_tip.errors.full_messages.join(", ")}."
      flash_message = flash_message ? "#{flash_message} #{save_error_message}" : save_error_message
    end

    respond_to do |format|
      format.html { redirect_to root_path, notice: flash_message }
      format.json do
        if @sent_tip.persisted? && @sent_tip.status == 'sent'
          render json: { message: flash_message, tip_id: @sent_tip.id, fcm_message_id: @sent_tip.fcm_message_id }, status: :created
        else
          errors_for_json = @sent_tip.errors.full_messages
          errors_for_json << @sent_tip.error_message if @sent_tip.error_message.present? && !errors_for_json.include?(@sent_tip.error_message)
          render json: { message: flash_message, errors: errors_for_json.uniq.presence || ["Failed to process tip."] }, status: :unprocessable_entity
        end
      end
    end
  end

  def clear_all_history
    SentTip.destroy_all
    respond_to do |format|
      format.html { redirect_to root_path, notice: "All sent tips history has been cleared." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("sentTipsTableBody",
                                                  partial: "dashboard/sent_tips_table_body",
                                                  locals: { sent_tips: [] })
      end
      format.json { head :no_content }
    end
  end

  private

  def sent_tip_params
    params.require(:sent_tip).permit(:title, :message, :image_url, :target_display_info)
  end
end
