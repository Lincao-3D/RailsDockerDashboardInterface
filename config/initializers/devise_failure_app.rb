class JsonApiFailureApp < Devise::FailureApp
# config/initializers/devise_failure_app.rb

  def respond
    if request_format == :json || request.content_type == 'application/json'
      json_error_response
    else
      super # Fallback to Devise's default behavior (redirect for HTML, etc.)
    end
  end

  def json_error_response
    self.status = 401 # Unauthorized
    self.content_type = 'application/json'self.response_body = { error: i18n_message }.to_json
  end

  # This is needed if you are using Rails 7 with Turbo and want to handle Turbo Stream failures.
  # Otherwise, Devise::FailureApp's http_auth_body is called, which returns a string.
  # We want to ensure JSON is returned for JSON requests.
  def http_auth_body
    return json_error_response if request_format == :json || request.content_type == 'application/json'
    super
  end
end
