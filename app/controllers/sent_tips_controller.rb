# app/controllers/sent_tips_controller.rb
class SentTipsController < ApplicationController
  # This line will skip CSRF token verification for the 'create' action.
  # This is necessary for API requests from mobile apps which do not handle CSRF tokens.
  # IMPORTANT: In a production environment, ensure this endpoint is protected by an
  # API-specific authentication method (e.g., API tokens) if it's meant to be secure.
  skip_before_action :verify_authenticity_token, only: [:create]

  before_action :authenticate_admin_user! # Keep this for Devise authentication

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
      # flash_message already set
    else
      Rails.logger.error "Failed to save SentTip record: #{@sent_tip.errors.full_messages.join(", ")}"
      flash_message = "Failed to save record: #{@sent_tip.errors.full_messages.join(", ")}. #{flash_message}"
    end

    # For API responses, you should typically render JSON, not redirect_to HTML.
    # The Android app expects a JSON response.
    # If the request makes it past authentication and saves, render success JSON.
    # If not (e.g., because authenticate_admin_user! failed), this redirect won't be seen by Android.
    # For now, let's keep the redirect as is, but be aware for future API design.
    respond_to do |format|
      format.html { redirect_to root_path, notice: flash_message }
      format.json do
        if @sent_tip.persisted? # Check if the record was actually saved
          render json: { message: flash_message, tip_id: @sent_tip.id }, status: :ok
        else
          render json: { errors: @sent_tip.errors.full_messages, message: flash_message }, status: :unprocessable_entity
        end
      end
    end
  end # Closes def create

  # New action to clear all sent tips history
  def clear_all_history
    SentTip.destroy_all # This deletes ALL records.

    respond_to do |format|
      format.html { redirect_to root_path, notice: "All sent tips history has been cleared." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("sentTipsTableBody",
                                                  partial: "dashboard/sent_tips_table_body",
                                                  locals: { sent_tips: [] }) # Pass empty array
      end # Closes format.turbo_stream do
      format.json { head :no_content }
    end # Closes respond_to do |format|
  end # Closes def clear_all_history

  private # private keyword should be here, before the methods it applies to

  def sent_tip_params
    params.require(:sent_tip).permit(:title, :message, :image_url, :target_display_info)
  end
end # Closes class SentTipsController