class SessionsController < Devise::SessionsController

  def create
    track_event(tag: "created.session", user: current_user)
    super
  end

  def destroy
    user = current_user

    super do
      redirect_to wbid_sign_out_url(user), status: :see_other

      return
    end
  end

  private

  def after_sign_out_path_for(resource)
    stored_location_for(resource) || super
  end

  def wbid_sign_out_url(user)
    return_path = URI.join(root_url, after_sign_out_path_for(user)).to_s

    "#{WbidClient.configuration.host}/walkadoo/session/sign_out?return_to=#{URI.encode(return_path)}"
  end
end
