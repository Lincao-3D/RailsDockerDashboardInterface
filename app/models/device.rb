class Device < ApplicationRecord
  validates :fcm_token, presence: true, uniqueness: true
  validates :platform, presence: true
end