require "jwt"
require "faraday"
require "countries"

class EnableBankingService
  BASE_URL = "https://api.enablebanking.com"

  def initialize
    @app_id = Setting.enable_banking_app_id
    @private_key = OpenSSL::PKey::RSA.new(Setting.enable_banking_private_key)
    @environment = Setting.enable_banking_environment
  end

  def get_aspsps(country)
    response = connection.get("aspsps", { country: country })

    if response.success?
      response.body["aspsps"]
    else
      Rails.logger.error "Enable Banking API error: #{response.status} - #{response.body}"
      []
    end
  rescue Faraday::Error => e
    Rails.logger.error "Enable Banking API connection error: #{e.message}"
    []
  end

  def authorize(_, aspsp_name, aspsp_country, psu_type, auth_method, maximum_consent_validity)
    # Generate a unique state for this authorization request
    state = SecureRandom.uuid

    # Calculate valid_until based on maximum_consent_validity
    valid_until = if maximum_consent_validity.present?
      # Don't exceed the maximum allowed period
      [ Time.current + maximum_consent_validity.to_i.days, Time.current + 90.days ].min
    else
      # Default to 90 days if no maximum is specified
      Time.current + 90.days
    end

    # Build callback URL with proper host and protocol
    protocol = ENV.fetch("DISABLE_SSL", "false") == "true" ? "http" : "https"
    host = ENV.fetch("HOST", "localhost:3000")
    callback_url = "#{protocol}://#{host}/enable_banking/callback"

    response = connection.post("auth", {
      aspsp: {
        name: aspsp_name,
        country: aspsp_country
      },
      redirect_url: callback_url,
      access: {
        valid_until: valid_until.iso8601
      },
      psu_type: psu_type,
      # auth_method: auth_method,
      state: state
    })

    if response.success?
      # Return both the response and state so controller can store it
      { response: response.body, state: state }
    else
      Rails.logger.error "Enable Banking API error: #{response.status} - #{response.body}"
      nil
    end
  end

  def get_countries
    response = self.get_application
    countries = response.dig("countries") || []

    # Let's inspect the structure of the countries object
    countries = countries.map { |code| [ ISO3166::Country[code].common_name, code ] }
  end

  def get_application
    response = connection.get("application")

    if response.success?
      # Extract countries from the application response
      response.body || []
    else
      Rails.logger.error "Enable Banking API error: #{response.status} - #{response.body}"
      []
    end
  rescue Faraday::Error => e
    Rails.logger.error "Enable Banking API connection error: #{e.message}"
    []
  end

  def create_session(code)
    response = connection.post("sessions", {
      code: code
    })

    if response.success?
      response.body
    else
      Rails.logger.error "Enable Banking API error: #{response.status} - #{response.body}"
      nil
    end
  end

  def get_account_balances(account_uid)
    response = connection.get("accounts/#{account_uid}/balances")

    if response.success?
      response.body["balances"]
    else
      Rails.logger.error "Enable Banking API error: #{response.status} - #{response.body}"
      []
    end
  end

  def get_account_transactions(account_uid, date_from = nil, date_to = nil)
    params = {}
    params[:date_from] = date_from.iso8601 if date_from
    params[:date_to] = date_to.iso8601 if date_to
    params[:strategy] = "longest" # Get the longest possible period of transactions

    response = connection.get("accounts/#{account_uid}/transactions", params)

    if response.success?
      response.body["transactions"]
    else
      Rails.logger.error "Enable Banking API error: #{response.status} - #{response.body}"
      []
    end
  end

  private

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.response :logger, Rails.logger, { headers: true, bodies: true }

        # Add JWT auth header to all requests
        faraday.request :authorization, "Bearer", generate_jwt

        faraday.adapter Faraday.default_adapter
      end
    end

    def generate_jwt
      payload = {
        iss: "enablebanking.com",
        aud: "api.enablebanking.com",
        iat: Time.current.to_i,
        exp: Time.current.to_i + 3600
      }

      headers = {
        kid: @app_id
      }

      JWT.encode(payload, @private_key, "RS256", headers)
    end
end
