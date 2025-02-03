class Settings::HostingsController < SettingsController
  before_action :raise_if_not_self_hosted

  def show
    @synth_usage = Current.family.synth_usage
  end

  def update
    if hosting_params[:upgrades_setting].present?
      mode = hosting_params[:upgrades_setting] == "manual" ? "manual" : "auto"
      target = hosting_params[:upgrades_setting] == "commit" ? "commit" : "release"

      Setting.upgrades_mode = mode
      Setting.upgrades_target = target
    end

    if hosting_params.key?(:render_deploy_hook)
      Setting.render_deploy_hook = hosting_params[:render_deploy_hook]
    end

    if hosting_params.key?(:require_invite_for_signup)
      Setting.require_invite_for_signup = hosting_params[:require_invite_for_signup]
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:synth_api_key)
      Setting.synth_api_key = hosting_params[:synth_api_key]
    end

    # Handle Enable Banking settings
    if hosting_params.key?(:enable_banking_enabled)

      Rails.logger.info("private key: #{Setting.enable_banking_private_key}")

      if hosting_params[:enable_banking_enabled] == "1"
        if Setting.enable_banking_app_id.blank? || Setting.enable_banking_private_key.blank? || Setting.enable_banking_redirect_url.blank?
          flash.now[:alert] = "Enable Banking cannot be enabled without setting App ID, Private Key, and Redirect URL"
          render :show, status: :unprocessable_entity
          return
        end
      end

      Setting.enable_banking_enabled = hosting_params[:enable_banking_enabled]
    end

    if hosting_params.key?(:enable_banking_app_id)

      if hosting_params[:enable_banking_app_id].blank?
        flash.now[:alert] = "Enable Banking App ID cannot be blank, integration turned off"
        render :show, status: :unprocessable_entity
        Setting.enable_banking_enabled = false
        Setting.enable_banking_app_id = nil
        return
      end

      # regex to check if it's a valid UUID
      if hosting_params[:enable_banking_app_id] !~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
        flash.now[:alert] = "Enable Banking App ID must be a valid UUID"
        render :show, status: :unprocessable_entity
        Setting.enable_banking_enabled = false
        return
      end

      Setting.enable_banking_app_id = hosting_params[:enable_banking_app_id]
    end

    if hosting_params.key?(:enable_banking_private_key)

      if hosting_params[:enable_banking_private_key].blank?
        flash.now[:alert] = "Enable Banking Private Key cannot be blank, integration turned off"
        render :show, status: :unprocessable_entity
        Setting.enable_banking_enabled = false
        Setting.enable_banking_private_key = nil
        return
      end

      # regex to check if it's a valid private key (RSA or PEM format)
      if hosting_params[:enable_banking_private_key] !~ /\A-----BEGIN (RSA|EC )?PRIVATE KEY-----[\s\S]*-----END (RSA|EC )?PRIVATE KEY-----\n?/
        flash.now[:alert] = "Enable Banking Private Key must be a valid RSA, EC, or PEM private key"
        render :show, status: :unprocessable_entity
        Setting.enable_banking_enabled = false
        return
      end

      Setting.enable_banking_private_key = hosting_params[:enable_banking_private_key]
    end

    if hosting_params.key?(:enable_banking_redirect_url)

      if hosting_params[:enable_banking_redirect_url].blank?
        flash.now[:alert] = "Enable Banking Redirect URL cannot be blank, integration turned off"
        render :show, status: :unprocessable_entity
        Setting.enable_banking_enabled = false
        Setting.enable_banking_redirect_url = nil
        return
      end

      # regex to check if it's a valid URL
      if hosting_params[:enable_banking_redirect_url] !~ /\Ahttps?:\/\/[^\s\/$.?#].[^\s]*(\?[^\s]*)?\z/
        flash.now[:alert] = "Enable Banking Redirect URL must be a valid URL"
        render :show, status: :unprocessable_entity
        Setting.enable_banking_enabled = false
        return
      end

      Setting.enable_banking_redirect_url = hosting_params[:enable_banking_redirect_url]
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = t(".failure")
    render :show, status: :unprocessable_entity
  end

  private
    def hosting_params
      params.require(:setting).permit(
        :render_deploy_hook, 
        :upgrades_setting, 
        :require_invite_for_signup, 
        :require_email_confirmation, 
        :synth_api_key,
        :enable_banking_enabled,
        :enable_banking_app_id,
        :enable_banking_private_key,
        :enable_banking_redirect_url
      )
    end

    def raise_if_not_self_hosted
      raise "Settings not available on non-self-hosted instance" unless self_hosted?
    end
end
