class CreateDevices < ActiveRecord::Migration[7.0] # Or your Rails version
  def change
    create_table :devices do |t|
      t.string :fcm_token, null: false
      t.string :platform, null: false # e.g., "android", "ios"
      t.datetime :last_seen_at

      t.timestamps
    end
    # Add a unique index to fcm_token to prevent duplicates and for faster lookups
    add_index :devices, :fcm_token, unique: true
  end
end