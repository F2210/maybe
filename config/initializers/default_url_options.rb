# Set default URL options for URL generation
Rails.application.config.after_initialize do
  Rails.application.routes.default_url_options = {
    host: ENV.fetch("HOST", "localhost:3000"),
    protocol: ENV.fetch("DISABLE_SSL", false) ? "http" : "https"
  }
end
