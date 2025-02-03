Rails.application.config.after_initialize do
  # Only schedule sync job if we're using a proper job backend and not in test environment
  if Rails.env.production? && defined?(EnableBanking::ScheduleSyncJob)
    # Schedule first sync job
    next_midnight = Date.tomorrow.midnight
    EnableBanking::ScheduleSyncJob.set(wait_until: next_midnight).perform_later
  end
end
