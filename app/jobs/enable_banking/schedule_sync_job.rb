class EnableBanking::ScheduleSyncJob < ApplicationJob
  queue_as :default

  def perform
    # Find all Enable Banking accounts
    Account.where(provider: "enable_banking").find_each do |account|
      # Schedule individual sync job with some delay to avoid rate limits
      EnableBanking::SyncAccountJob.set(wait: rand(1..30).minutes).perform_later(account)
    end

    # Schedule next run for tomorrow at midnight
    self.class.set(wait_until: Date.tomorrow.midnight).perform_later
  end
end
