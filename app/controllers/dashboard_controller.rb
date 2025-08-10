class DashboardController < ApplicationController
  before_action :authenticate_admin_user!
  include Rails.application.routes.url_helpers
 # Added above line
  def index
    @sent_tip = SentTip.new
    @sent_tips = SentTip.order(sent_at: :desc).limit(50)
  end

  def upload_quick_image
    uploaded_file = params.dig(:quick_image_upload, :image)

    if uploaded_file.present?
      # Assuming you have ActiveStorage set up for handling uploads:
      blob = ActiveStorage::Blob.create_and_upload!(
        io: uploaded_file.tempfile,
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type
      )

      image_url = url_for(blob)
      image_id = blob.signed_id # Using signed_id is good

      render json: { image_url: image_url, image_id: image_id, message: "File uploaded successfully" }
    else
      render json: { error: 'No image file uploaded' }, status: :unprocessable_entity
    end
  rescue ActiveStorage::IntegrityError => e
    Rails.logger.error "ActiveStorage Integrity Error: #{e.message}"
    render json: { error: "Failed to process image due to integrity issue: #{e.message}" }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Error uploading quick image: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") # Good for debugging
    render json: { error: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error
  end
end