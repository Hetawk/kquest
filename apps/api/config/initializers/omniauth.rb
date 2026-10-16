require "omniauth/rails_csrf_protection"

OmniAuth.config.path_prefix = "/api/v1/auth"
OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning = true
