class AddLastSyncedAtToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :last_synced_at, :datetime
    add_index :accounts, :last_synced_at
  end
end
