class InvitesController < ApplicationController

  before_action :require_no_user

  def show
    invite = Invite.find(params[:id])

    if invite.accepted?
      redirect_to root_path
    else
      redirect_to "#{Rails.application.secrets.wbid[:url]}/user/signup?return_to=#{callback_invite_url(invite)}"
    end
  end

  def callback
    debugger
    invite = Invite.find(params[:id])

    if invite.accepted?
      redirect_to root_path
    elsif authenticator.valid? && invite.accept!(authenticator.wbid_user_key)
      redirect_to "/onboarding/welcome"
    else
      NewRelic::Agent.notice_error("Unable to accept Invite", custom_params: { invite_id: invite.id, wbid_user_key: authenticator.wbid_user_key })

      head :unprocessable_entity
    end
  end
end
