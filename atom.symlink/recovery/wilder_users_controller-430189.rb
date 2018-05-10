class WilderUsersController < ApplicationController
  before_filter :authenticate_user!
  before_filter :load_wilder_user

  DeviceProvider.oauth.map(&:id).each do |provider|
    define_method("create_#{provider}") do
      has_existing_tracker! if current_user.has_device?

      @wilder_user.delete_profile
      create_oauth(provider)
    end
  end

  def create_oauth_callback
    if WilderClient.valid_signature?(request, params[:wilder_signature])
      if params[:profile]
        remote_profile = OpenStruct.new(params[:profile])
        provider_name = DeviceProvider.find(remote_profile.provider_name).device_name

        begin
          @wilder_user.update_profile!(remote_profile)
          if session[:onboarding]
            track_event(tag: "registered.device", metadata: {
              provider_name: remote_profile.provider_name,
              provider_id: remote_profile.provider_id,
              auth_status: remote_profile.try(:oauth_status)
            })
            current_user.register_event(UserEvent::INITIAL_DEVICE_REGISTRATION)

            redirect_to mobile_onboarding_device_wearable_path, notice: t(".flash.initial_device_added", provider_name: provider_name)
          else
            track_event(tag: "registered.device", metadata: {
              provider_name: remote_profile.provider_name,
              provider_id: remote_profile.provider_id,
              auth_status: remote_profile.try(:oauth_status)
            })
            current_user.register_event(UserEvent::SUBSEQUENT_DEVICE_REGISTRATION)

            send_switch_tracker_mail if has_existing_tracker?
            redirect_to manage_device_path, notice: t(".flash.device_switched_successfully", provider_name: provider_name)
          end
        rescue => ex
          NewRelic::Agent.notice_error(ex)
          current_user.register_event(UserEvent::DEVICE_REGISTRATION_ERROR)
          redirect_to new_onboarding_device_wearable_path, alert: t(".flash.device_add_error", provider_name: provider_name)
        end
      else
        oauth_callback_error_handler
      end
    else
      head :bad_request
    end
  end

  private

  def oauth_callback_error_handler
    NewRelic::Agent.notice_error("Wilder reported an OAuth error.", user_id: current_user.id, error: params[:error].to_json)
    if params[:error][:kind] == WilderClient::Errors::CONFLICT
      if session[:onboarding]
        redirect_to new_onboarding_device_wearable_path, alert: t(".flash.device_already_exists", device: params[:error][:provider].downcase.capitalize)
      else
        redirect_to manage_existing_device_path(device: params[:error][:provider])
      end
    else
      redirect_to new_onboarding_device_wearable_path, alert: t(".flash.oauth_error")
    end
  end

  def load_wilder_user
    @wilder_user = WilderUser.for(current_user)
  end

  def create_oauth(provider_name)
    nonce, hmac = WilderClient.nonce_and_hmac
    options = {
      nonce: nonce,
      hmac: hmac,
      r: url_for(controller: "wilder_users", action: "create_oauth_callback", onboarding: "true"),
    }
    session[:onboarding] = onboarding?
    location = WilderClient.create_oauth_user_url(provider_name, @wilder_user.wilder_user_id, options)

    respond_to do |format|
      format.html { redirect_to location }
      format.json { render json: {location: location} }
    end
  end

  def has_existing_tracker!
    session[:has_existing_tracker] = true
  end

  def has_existing_tracker?
    session[:has_existing_tracker] == true
  end

  def send_switch_tracker_mail
    SwitchTrackerMailer.switched_device(current_user.id).deliver_later
  end
end
