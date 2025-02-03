module EnableBanking
  class EnableBankingController < ApplicationController
    before_action :ensure_enable_banking_configured
    before_action :validate_state, only: :callback

    def connect
      # Show ASPSP selection page
      @country = params[:country] || "FI" # Default to Finland
      @countries = EnableBankingService.new.get_countries
      @aspsps = EnableBankingService.new.get_aspsps(@country)
    end

    def psu_type
      @aspsp_id = params[:aspsp_id]
      @aspsp_name = params[:aspsp_name]
      @aspsp_country = params[:aspsp_country]
      @auth_methods = params[:auth_methods]
      @maximum_consent_validity = params[:maximum_consent_validity]

      render partial: "enable_banking/psu_type_selector"
    end

    def authorize_info
      @aspsp_name = params[:aspsp_name]
      @aspsp_country = params[:aspsp_country]
      @psu_type = params[:psu_type]
      @auth_method = params[:auth_method]
      @maximum_consent_validity = params[:maximum_consent_validity]

      render partial: "enable_banking/authorization_info"
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
        render partial: "enable_banking/connection_status"
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

          # Show account selection screen
          @accounts = session_data["accounts"]
          render partial: "enable_banking/account_selector"
        else
          @success = false
          @error_message = t(".session_error")
          render partial: "enable_banking/connection_status"
        end
      else
        @success = false
        @error_message = params[:error] || t(".error")
        render partial: "enable_banking/connection_status"
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
