class CreateSentTips < ActiveRecord::Migration[7.1]
  def change
    create_table :sent_tips do |t|
      t.string :title
      t.text :message
      t.string :image_url
      t.string :target_display_info
      t.datetime :sent_at
      t.string :fcm_message_id
      t.string :status
      t.text :error_message

      t.timestamps
    end
  end
end
