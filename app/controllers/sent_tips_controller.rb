# app/controllers/sent_tips_controller.rb
class SentTipsController < ApplicationController
  # Skip CSRF token verification for the 'create' action (for API requests)
  skip_before_action :verify_authenticity_token, only: [:create]

  # Apply Devise authentication to all actions in this controller EXCEPT :create.
  # This ensures other actions (if any) remain protected by Devise,
  # while :create (used by your Android app) will not require Devise web session authentication.
  # For production, the :create action should still be secured, typically with an API token.
  before_action :authenticate_admin_user!, except: [:create] # MODIFY THIS SECTION

  def create
    @sent_tip = SentTip.new(sent_tip_params)
    @sent_tip.sent_at = Time.current

    begin
      fcm_client = FirebaseClient.new # Ensure FirebaseClient is correctly initialized
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
    rescue => e # Consider more specific error catching if FirebaseClient has custom errors
      Rails.logger.error "Error during FCM send process: #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}"
      @sent_tip.status = 'failed'
      @sent_tip.error_message = "#{e.class.name}: #{e.message}"
      flash_message = "Tip failed to send: #{@sent_tip.error_message}"
    end

    if @sent_tip.save
      # flash_message is already set
    else
      Rails.logger.error "Failed to save SentTip record: #{@sent_tip.errors.full_messages.join(", ")}"
      # Append save error to any existing flash message from FCM
      save_error_message = "Failed to save record: #{@sent_tip.errors.full_messages.join(", ")}."
      flash_message = flash_message ? "#{flash_message} #{save_error_message}" : save_error_message
    end

    respond_to do |format|
      format.html { redirect_to root_path, notice: flash_message }
      format.json do
        if @sent_tip.persisted? && @sent_tip.status == 'sent'
          render json: { message: flash_message, tip_id: @sent_tip.id, fcm_message_id: @sent_tip.fcm_message_id }, status: :created # Use :created
        else
          errors_for_json = @sent_tip.errors.full_messages
          errors_for_json << @sent_tip.error_message if @sent_tip.error_message.present? && !errors_for_json.include?(@sent_tip.error_message)
          render json: { message: flash_message, errors: errors_for_json.uniq.presence || ["Failed to process tip."] }, status: :unprocessable_entity
        end
      end
    end
  end

  # New action to clear all sent tips history
  def clear_all_history
    SentTip.destroy_all # This deletes ALL records.

    respond_to do |format|
      format.html { redirect_to root_path, notice: "All sent tips history has been cleared." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("sentTipsTableBody",
                                                  partial: "dashboard/sent_tips_table_body",
                                                  locals: { sent_tips: [] }) # Pass empty array
      end
      format.json { head :no_content }
    end
  end

  private

  def sent_tip_params
    params.require(:sent_tip).permit(:title, :message, :image_url, :target_display_info)
  end
end
