class UserSession < Authlogic::Session::Base
  # Don't try to log someone into the site if you happen to see
  # HTTP basic auth headers.  This allows us to protect a non-public
  # (staging, integration) site behind HTTP auth without it interfering
  # with normal site login via Facebook
  allow_http_basic_auth false

  # Separate out session namespace
  session_key "user_credentials"

  # For form helpers
  def to_key
    new_record? ? nil : [ self.send(self.class.primary_key) ]
  end

  def after_create
  end

  private

  # Disable cookie persistence
  def persist_by_cookie
  end
  def save_cookie
  end
end
