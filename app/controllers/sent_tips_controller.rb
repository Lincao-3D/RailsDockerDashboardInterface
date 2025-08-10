        class SentTipsController < ApplicationController
          before_action :authenticate_admin_user!

          def create
            @sent_tip = SentTip.new(sent_tip_params)
            @sent_tip.sent_at = Time.current

            begin
              fcm_client = FirebaseClient.new
              fcm_response_raw = fcm_client.send_tip(@sent_tip)

              # The firebase-admin-sdk for Ruby often returns the message ID directly as a string like:
              # "projects/your-project-id/messages/0:12345..."
              # Or it might be a hash. Check the gem's documentation or inspect the actual response.
              if fcm_response_raw.is_a?(String) && fcm_response_raw.include?('/messages/')
                @sent_tip.fcm_message_id = fcm_response_raw
              elsif fcm_response_raw.is_a?(Hash) && fcm_response_raw['name'].present? # Check for common hash structure
                @sent_tip.fcm_message_id = fcm_response_raw['name']
              else
                Rails.logger.warn "FCM send was likely successful but response format was unexpected: #{fcm_response_raw.inspect}"
                @sent_tip.fcm_message_id = fcm_response_raw.to_s # Store raw response
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
              # Prepend save error to flash message
              flash_message = "Failed to save record: #{@sent_tip.errors.full_messages.join(", ")}. #{flash_message}"
            end

            redirect_to root_path, notice: flash_message
          end
		  
		  # New action to clear all sent tips history
		  def clear_all_history
			SentTip.destroy_all # This deletes ALL records.

			respond_to do |format|
			  format.html { redirect_to root_path, notice: "All sent tips history has been cleared." }
			  format.turbo_stream do
				# Replace the table body with an empty state
				# You'll need the _sent_tips_table_body.html.erb partial as discussed before
				render turbo_stream: turbo_stream.replace("sentTipsTableBody",
														  partial: "dashboard/sent_tips_table_body",
														  locals: { sent_tips: [] }) # Pass empty array
			  }
			  format.json { head :no_content }
			end
		  end


          private

          def sent_tip_params
            params.require(:sent_tip).permit(:title, :message, :image_url, :target_display_info)
          end
        end
        