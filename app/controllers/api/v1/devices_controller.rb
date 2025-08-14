module Api
  module V1
    class DevicesController < ApplicationController
      # For API endpoints, typically skip CSRF token verification.
      # If you have a different API authentication mechanism, use that.
      skip_before_action :verify_authenticity_token

      def create
        # Use strong parameters to permit only the expected attributes
        device_params = params.require(:device).permit(:fcm_token, :platform)

        # Find by token, or initialize a new one if not found
        @device = Device.find_or_initialize_by(fcm_token: device_params[:fcm_token])

        # Update attributes
        @device.platform = device_params[:platform]
        @device.last_seen_at = Time.current

        if @device.save
          render json: { message: 'Device token processed successfully.', device_id: @device.id }, status: :ok # :created if always new
        else
          render json: { errors: @device.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActionController::ParameterMissing => e
        render json: { error: "Required parameter missing: #{e.param}" }, status: :bad_request
      rescue StandardError => e # Catch other potential errors
        Rails.logger.error "Error in DevicesController#create: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "An unexpected error occurred." }, status: :internal_server_error
      end
    end
  end
end
