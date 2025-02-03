class AddEncryptedColumnsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :enable_banking_app_id_ciphertext, :text
    add_column :settings, :enable_banking_private_key_ciphertext, :text
    add_column :settings, :enable_banking_redirect_url_ciphertext, :text
  end
end
