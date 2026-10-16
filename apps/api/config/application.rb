require_relative "boot"

rails_environment = ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development"))
if rails_environment == "development"
  require "dotenv"
  Dotenv.load(File.expand_path("../../../.env", __dir__))
elsif rails_environment == "test"
  ENV["DATABASE_URL"] = ENV["TEST_DATABASE_URL"] if ENV["TEST_DATABASE_URL"]
  ENV.delete("DATABASE_URL") unless ENV["TEST_DATABASE_URL"]
end

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Api
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths << Rails.root.join("app/domains")
    config.eager_load_paths << Rails.root.join("app/domains")
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_kquest_api_session",
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?,
      expire_after: 10.minutes
    config.middleware.use OmniAuth::Builder do
      provider(
        :google_oauth2,
        ENV["GOOGLE_CLIENT_ID"],
        ENV["GOOGLE_CLIENT_SECRET"],
        scope: "email,profile",
        prompt: "select_account",
        access_type: "online",
        redirect_uri: ENV["GOOGLE_REDIRECT_URI"]
      )
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end
end
