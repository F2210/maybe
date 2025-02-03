module EnableBanking
  class BankingController < ApplicationController
    before_action :ensure_enable_banking_configured
    before_action :validate_state, only: :callback

    def connect
      # Show ASPSP selection page
      @country = params[:country] || "FI" # Default to Finland
      @countries = EnableBankingService.new.get_countries
      @aspsps = EnableBankingService.new.get_aspsps(@country)
      render "enable_banking/banking/connect"
    end

    def psu_type
      @aspsp_id = params[:aspsp_id]
      @aspsp_name = params[:aspsp_name]
      @aspsp_country = params[:aspsp_country]
      @auth_methods = params[:auth_methods]
      @maximum_consent_validity = params[:maximum_consent_validity]

      render partial: "enable_banking/banking/psu_type_selector"
    end

    def authorize_info
      @aspsp_name = params[:aspsp_name]
      @aspsp_country = params[:aspsp_country]
      @psu_type = params[:psu_type]
      @auth_method = params[:auth_method]
      @maximum_consent_validity = params[:maximum_consent_validity]

      render partial: "enable_banking/banking/authorization_info"
    end

    def authorize
      result = EnableBankingService.new.authorize(
        params[:aspsp_id],
        params[:aspsp_name],
        params[:aspsp_country],
        params[:psu_type],
        params[:auth_method],
        params[:maximum_consent_validity]
      )

      if result
        # Store the state in session for callback validation
        session[:enable_banking_state] = result[:state]
        session[:enable_banking_aspsp_name] = params[:aspsp_name]

        # Redirect to the bank's authorization page
        redirect_to result[:response]["url"], allow_other_host: true
      else
        @error_message = t(".error")
        @success = false
        render partial: "enable_banking/banking/connection_status"
      end
    end

    def callback
      if params[:code].present?
        # Create session with Enable Banking
        service = EnableBankingService.new
        session_data = service.create_session(params[:code])

        if session_data
          # Store session ID for future API calls
          session[:enable_banking_session_id] = session_data["session_id"]

          # Store accounts in Redis temporarily with a 5-minute expiration
          accounts_key = "enable_banking:accounts:#{SecureRandom.hex(10)}"
          Rails.logger.info "Writing accounts to Redis with key: #{accounts_key}"
          Rails.logger.info "Accounts data: #{session_data["accounts"].inspect}"

          cache_write_success = Rails.cache.write(accounts_key, session_data["accounts"], expires_in: 5.minutes)
          Rails.logger.info "Cache write success: #{cache_write_success}"

          session[:enable_banking_accounts_key] = accounts_key
          Rails.logger.info "Stored accounts key in session: #{session[:enable_banking_accounts_key]}"

          respond_to do |format|
            format.html do
              # Redirect to show_account_selector action
              redirect_to enable_banking_show_account_selector_path
            end
            format.turbo_stream do
              @accounts = session_data["accounts"]
              render partial: "enable_banking/banking/account_selector"
            end
          end
        else
          @success = false
          @error_message = t(".session_error")

          respond_to do |format|
            format.html { redirect_to new_account_path, alert: t(".session_error") }
            format.turbo_stream { render partial: "enable_banking/banking/connection_status" }
          end
        end
      else
        @success = false
        @error_message = params[:error] || t(".error")

        respond_to do |format|
          format.html { redirect_to new_account_path, alert: @error_message }
          format.turbo_stream { render partial: "enable_banking/banking/connection_status" }
        end
      end
    end

    def show_account_selector
      accounts_key = session[:enable_banking_accounts_key]
      Rails.logger.info "Retrieved accounts key from session: #{accounts_key}"

      @accounts = Rails.cache.read(accounts_key)
      Rails.logger.info "Retrieved accounts from Redis: #{@accounts.inspect}"

      # Clear the data from Redis and session after retrieving
      Rails.cache.delete(accounts_key)
      session.delete(:enable_banking_accounts_key)

      if @accounts.nil?
        Rails.logger.error "Accounts data not found in Redis for key: #{accounts_key}"
        redirect_to new_account_path, alert: t(".session_expired")
        return
      end

      respond_to do |format|
        format.html
        format.turbo_stream { render partial: "enable_banking/banking/account_selector" }
      end
    end

    def import_accounts
      return redirect_to new_account_path, alert: t(".no_accounts_selected") if params[:account_ids].blank?

      service = EnableBankingService.new
      success_count = 0
      error_count = 0

      params[:account_ids].each do |account_id|
        # Get account balances and transactions
        balances = service.get_account_balances(account_id)
        transactions = service.get_account_transactions(account_id)

        # Create or update the account
        account = current_user.accounts.find_or_initialize_by(
          provider: "enable_banking",
          external_id: account_id
        )

        if balances.present?
          latest_balance = balances.find { |b| b["status"] == "BOOK" }
          if latest_balance
            account.balance = latest_balance["balance_amount"]["amount"].to_d
            account.currency = latest_balance["balance_amount"]["currency"]
          end
        end

        # Set other account details
        account.name = "#{session[:enable_banking_aspsp_name]} Account"
        account.account_type = "bank"
        account.last_synced_at = Time.current

        if account.save
          success_count += 1

          # Import transactions
          transactions.each do |txn|
            account.transactions.create!(
              amount: txn["transaction_amount"]["amount"].to_d,
              currency: txn["transaction_amount"]["currency"],
              description: txn["remittance_information"]&.join(" "),
              date: txn["booking_date"],
              external_id: txn["entry_reference"],
              status: txn["status"]
            )
          end
        else
          error_count += 1
        end
      end

      # Schedule daily sync if this is the first Enable Banking account
      if success_count > 0 && current_user.accounts.where(provider: "enable_banking").count == success_count
        EnableBanking::ScheduleSyncJob.set(wait_until: Date.tomorrow.midnight).perform_later
      end

      if success_count > 0
        redirect_to accounts_path, notice: t(".success", count: success_count)
      else
        redirect_to new_account_path, alert: t(".error", count: error_count)
      end
    end

    private

      def ensure_enable_banking_configured
        unless Setting.enable_banking_enabled &&
               Setting.enable_banking_app_id.present? &&
               Setting.enable_banking_private_key.present?
          redirect_to new_account_path, alert: t(".not_configured")
        end
      end

      def validate_state
        unless params[:state].present? && params[:state] == session[:enable_banking_state]
          redirect_to new_account_path, alert: t(".invalid_state")
        end
      end
  end
end
