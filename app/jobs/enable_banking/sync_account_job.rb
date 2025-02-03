class EnableBanking::SyncAccountJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(account)
    service = EnableBankingService.new

    # Get transactions since last sync
    last_sync = account.last_synced_at || 30.days.ago
    transactions = service.get_account_transactions(
      account.external_id,
      date_from: last_sync
    )

    # Get latest balance
    balances = service.get_account_balances(account.external_id)
    if balances.present?
      latest_balance = balances.find { |b| b["status"] == "BOOK" }
      if latest_balance
        account.update!(
          balance: latest_balance["balance_amount"]["amount"].to_d,
          currency: latest_balance["balance_amount"]["currency"]
        )
      end
    end

    # Import new transactions
    transactions.each do |txn|
      account.transactions.find_or_create_by!(external_id: txn["entry_reference"]) do |t|
        t.amount = txn["transaction_amount"]["amount"].to_d
        t.currency = txn["transaction_amount"]["currency"]
        t.description = txn["remittance_information"]&.join(" ")
        t.date = txn["booking_date"]
        t.status = txn["status"]
      end
    end

    # Update last synced timestamp
    account.touch(:last_synced_at)
  end
end
