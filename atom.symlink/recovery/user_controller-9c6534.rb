class Challenge::UserController < Challenge::BaseController
  include ControllerMixins::Registration
  include ControllerMixins::MobileRedirector

  helper :facebook

  before_action :set_body_class
  after_action :allow_iframe, only: [:authenticate_callback]

  # Since we are about to turn a new user into an authenticated user, we almost certainly do not want to establish a temp user, since this
  # will just immediately be overridden by the very next page request.
  skip_before_action :setup_temp_user, :only => [:authenticate_and_redirect]

  # We don't want to auto-activate challenge profiles for users hitting this controller.
  skip_before_action :activate_pending_user

  # External authentication providers that post back to us will not provide an authenticity token. In some cases, we need to maintain session data
  # across the authentication attempt, so we have to disable the token check for this action.
  protect_from_forgery :except => :authenticate_callback

  allow_when_taking_time_away only: [:logout]

  def authenticate
    render(:file => "#{Rails.root}/public/404.html", :status => 404)
  end

  def authenticate_callback
    params[:auth_mode] ||= session[:auth_mode] || request.env["omniauth.params"].try(:fetch, "auth_mode", nil)

    case params[:auth_mode]
      when 'admin'                    then provider_admin
      when 'challenge_secure'         then provider_challenge_secure
      when 'link'                     then provider_link
      when 'disable_account'          then provider_disable_account_secure
      else                                 provider_login
    end
  end

  def provider_admin
    if user_from_provider
      s = AdminUserSession.create(user_from_provider)
      track_event(tag: "session.create", user: some_other_user)
      return_url = session.delete(:r)
      redirect_to return_url || admin_welcome_url
    else
      flash[:error] = "Error logging in. Please don't try again."
      redirect_to admin_login_url
    end
  end

  def provider_disable_account_secure
    handle_secure_provider(challenge_manage_path(action: "disable_account"))
  end

  def provider_challenge_secure
    handle_secure_provider
  end

  def provider_link
    email = (omniauth['info']['email'] rescue nil)
    uid = omniauth['uid']
    duplicate_user = User.where(facebook_uid: uid).where('NOT id = ?', current_user.id).exists?

    message, status = if duplicate_user
      [
        'Another user is already linked to this Facebook account.',
        :unprocessable_entity
      ]
    else
      link_to_facebook(provider, uid, current_user) unless current_user.is_facebook_user?
      [
        'Your account is linked to Facebook',
        :ok
      ]
    end

    respond_to do |format|
      format.js do
        render json: { message: message }, status: status
      end
    end
  end

  def provider_login
    login_info = OpenStruct.new(
      provider: provider,
      omniauth_uid: omniauth["uid"],
      current_user: current_user,
      user_from_provider: user_from_provider
    )

    authenticate_user(LoginRuleTable.new.find_registration_type(login_info))
  end

  def user_for_registration_data(registration_data)
    User.new(
      country: registration_data.try(:country),
      date_of_birth: registration_data.date_of_birth,
      email: registration_data.email,
      wbid_key: registration_data.uid,
      first_name: registration_data.first_name,
      gender: registration_data.gender,
      last_name: registration_data.last_name,
      time_zone_id: registration_data.time_zone_id,
      zip: registration_data.zip
    )
  end

  def invalid_login
    flash[:error] = "You aren't signed into #{provider_name(params[:provider])}. Please try again."

    # Check for a specific destination request and session it if there is one.
    if params[:r]
      session[:r] = params[:r]
    end

    redirect_to(params[:e] || challenge_authenticate_path(provider: "wbid", auth_mode: params[:auth_mode]))
  end

  # For explicit logout requests (/challenge/logout)
  def logout
    # Logout can be called in scenarios where we are forcing a logout without user interaction,
    # such as when we've detected a stale facebook connect cookie. In those cases we don't need to
    # tell the user we logged them out. Logout can also be initiated in situations where we want to
    # give the user more information on why re-authentication is necessary (as, for example, when
    # we no longer have a valid offline access token).

    return_url = session.delete(:logout_return_to) || params[:r] || challenge_today_path

    reset_session

    if params[:err]
      flash[:error] = params[:err]
    else
      flash[:notice] = "Successfully signed out."
    end

    # Register logout event
    current_user.register_event(UserEvent::LOGOUT) if current_user

    logout_fb_user

    # Sign out from WBID
    return_path = return_url.starts_with?("http://") ? return_url : URI.join(root_url, return_url).to_s
    wbid_signout_url = "#{Rails.application.secrets.wellbeingid_app_url}/dailychallenge/session/sign_out?return_to=#{URI.encode(return_path)}"

    respond_with_redirect_to wbid_signout_url
  end

  # Authenticated redirects
  # Look for a valid PerishableToken in params[:token], authenticate to that user, and redirect to params[:r]
  def authenticate_and_redirect
    @perishable_token = PerishableToken.find_by_uuid(params[:token])
    @raw_payload      = params[:p]
    @hash             = params[:h]

    @payload     = PerishableToken.decrypt_payload(@raw_payload)
    @destination = @payload["d"] if @payload

    unless @destination && @payload && PerishableToken.verify_hash(@hash, @raw_payload)
      flash[:error] = "Whoops! Something was wrong with that link."
      return redirect_to(challenge_today_path)
    end

    RealtimeMetrics.increment("PerishableToken/attempted_use")

    if @perishable_token && @perishable_token.usable?
      already_logged_in_user = current_user
      target_user = @perishable_token.user

      if already_logged_in_user == target_user
        RealtimeMetrics.increment("PerishableToken/used_when_same_user_was_logged_in")
      elsif already_logged_in_user
        RealtimeMetrics.increment("PerishableToken/used_when_different_user_was_logged_in")
      else
        RealtimeMetrics.increment("PerishableToken/used_when_no_user_currently_logged_in")
      end

      # Establish temporary session for this user
      UserSession.create(target_user)

      # Establish a secure session if the encrypted payload says to
      if @payload["ess"]
        SecureSession.create(target_user)
      end

      # flag as used
      @perishable_token.use!

      maybe_track_click?(@payload, @destination, target_user)

      # Fire off delayed job to delete any bounces or spam reports for this user
      EmailEventDeletion.delete_async!(target_user, EmailEventDeletion::VIA_AUTHENTICATED_LINK)

      # redirect to page
      return redirect_to(@destination)

    elsif current_user
      # well, the token expired or has already been used
      maybe_track_click?(@payload, @destination, current_user)

      # Fire off delayed job to delete any bounces or spam reports for this user
      EmailEventDeletion.delete_async!(current_user, EmailEventDeletion::VIA_AUTHENTICATED_LINK)

      RealtimeMetrics.increment("PerishableToken/unusable_but_user_was_already_logged_in")

      return redirect_to(@destination)
    else
      # Either the token was invalid or no user logged in.
      # In either case, redirect the person to a login page and make sure they end up
      # at the right destination after logging in.

      maybe_track_click?(@payload, @destination, @temp_user)

      session[:r] = @destination
      return redirect_to(login_redirect_path)
    end
  end

  private

  def provider_name(provider)
    case provider.to_sym
    when :facebook then "Facebook"
    when :wbid then "MeYou Health Account"
    else ""
    end
  end

  def track
    track_id = request.env["omniauth.params"].try(:fetch, "track_id", nil) || params[:track_id]
    Track.find_by(id: track_id) || Track.default_track
  end

  def ensure_sponsorship_awarded(user)
    if sponsor
      sponsor.add_profile_to_user(user).save
    end
  end

  def sponsor
    if omniauth["extra"]
      Sponsor.active.find_by(url_code: omniauth["extra"]["sponsor_url_code"])
    end
  end

  def allow_iframe
    response.headers.except! 'X-Frame-Options'
  end

  def omniauth
    request.env['omniauth.auth']
  end

  def provider
    if omniauth.present?
      omniauth['provider']
    else
      ''
    end.inquiry
  end

  def link_to_facebook(provider, uid, user)
    params = {
        provider: provider,
        uid: uid,
        email: user.email,
        user_id: user.id
    }

    # Check to see if we need to update the facebook token for this user
    maybe_update_facebook_info!

    authentication = Authentication.where(params).first_or_create
    user.register_event(UserEvent::ADDED_AUTHENTICATION, authentication)
  end

  def handle_secure_provider(explicit_redirect = nil)
    if user_from_provider.present?
      SecureSession.create(user_from_provider)
      return_path = session.delete(:r)
      redirect_to explicit_redirect || return_path || challenge_manage_path(:action => "profile")
    else
      flash[:error] = "Error logging in. Please try again."
      redirect_to challenge_today_path(auth_mode: "challenge_secure")
    end
  end

  def set_body_class
    @body_class = 'challenge'
  end

  def user_from_provider
    @user_from_provider ||= if provider.wbid?
      User.active.find_by(wbid_key: omniauth["uid"])
    elsif provider.facebook?
      facebook_business_token = omniauth["extra"]["raw_info"]["token_for_business"]
      WbidClient.get_facebook_user(facebook_business_token)
    end
  end

  def maybe_track_click?(payload, destination, user)
    if user && payload["t"] && payload["et"] && payload["ct"]
      EmailClick.create!({
        :clicker => user,
        :email_type => payload["et"],
        :click_type => payload["ct"],
        :destination => destination.first(255), # stored as 'string', not 'text', so can't be any bigger than this
        :related_object_type => payload["rt"],
        :related_object_id => payload["rid"],
      })
    end
  end

  def new_session_for(user, existing_user_session = nil)
    @user_session = existing_user_session || UserSession.create(user)

    if @user_session
      handle_login
    else
      flash[:error] = "Error logging you into your account. Please try again."
      return redirect_to(challenge_today_path)
    end
  end

  def setup_wbid_user
    save_authentication_data # create session['auth_data'] from omniauth rack env stuff
    UserRegistrar.new(
      sponsor: Sponsor.active.find_by(url_code: session['auth_data'].sponsor_url_code),
      user: user_for_registration_data(session['auth_data']),
      user_event_source: UserEvent::Source::WBID,
      track: track
    ).register!
  end
end
