# /config/initializers/faraday.rb
require 'faraday'
require 'faraday/net_http' # This should now work after adding the gem

Faraday.default_adapter = :net_http

Rails.logger.info "Faraday default adapter set to :net_http after requiring faraday/net_http (using faraday-net_http gem)"