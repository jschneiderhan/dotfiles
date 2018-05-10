class User < ActiveRecord::Base
  include CurrentChallengeDate
  include FacebookAccessTokenExchange::UserMixin

  ###################################################################
  # CONSTANTS
  # define status constants, active?, inactive?, deleted?, banned?, etc.
  flexible_enum :status do
    active  1, :inverse => :inactive
    deleted 2
    banned  3
  end

  BIO_CHARACTER_LIMIT = 500
  NUM_DEFAULT_PROFILE_PICTURES = 10
  DEFAULT_CHALLENGE_DELIVERY_TIME = 7 # TODO: remove this once me merge rocket
  MAX_LEVEL_ENCOURAGEMENTS_PER_DAY = 10
  NORMAL_ENCOURAGEMENTS_PER_DAY = 1

  ###################################################################
  # User-assignable attributes
  attr_from_params :email, :country, :time_zone_id, :mobile_string, :gender, :first_name, :last_name, :zip, :password, :password_confirmation, :date_of_birth

  attr_accessor :password_confirmation, :local_validations

  ###################################################################
  # Mixins

  acts_as_split_timestamp :facebook_session_key_expires

  # Needs to be specified before the authlogic config
  validates :email, presence: true
  validates :wbid_key, presence: true
  validates :wbid_key, uniqueness: { scope: :status }, if: :active?
  validates_acceptance_of :terms, :on => :create, :message => "You have to agree to the terms of use and privacy policy."

  acts_as_authentic do |c|
    # Authlogic has changed its default encryption system from SHA512 to SCrypt, but we can still use SHA512
    # https://github.com/binarylogic/authlogic/issues/400
    c.crypto_provider = Authlogic::CryptoProviders::Sha512

    c.require_password_confirmation = false
    c.ignore_blank_passwords        = true
    c.validate_password_field       = false
    c.validates_uniqueness_of_email_field_options :case_sensitive => false
    c.validates_format_of_email_field_options = {:with => Authlogic::Regex.email, :message => I18n.t('error_messages.email_invalid', :default => "should look like an email address, e.g., user@example.com")}

    # By default, authlogic tries to intelligently re-establish sessions for users when you change
    # their persistence token (for example, by changing their password).
    # This causes problems in the test environment when model-level changes trigger the attempt
    # to modify controller responses.
    # In general, this seems like an insane thing for Authlogic to do, so we'll disable it here
    # and it will be incumbent upon us to re-create sessions when we need to.
    c.maintain_sessions             = false
  end

  ###################################################################
  # Carrierwave integration
  mount_uploader :picture, UserPictureUploader

  ###################################################################
  # Associations
  has_many :authentications, :dependent => :destroy
  has_many :role_assignments, :dependent => :destroy
  has_many :roles, :through => :role_assignments
  has_many :challenges, :foreign_key => :author_id
  has_many :challenge_assignments
  has_many :challenges, :through => :challenge_assignments
  has_many :challenge_feedbacks
  has_many :challenge_user_weekly_summaries
  has_many :user_events, :dependent => :destroy
  has_many :challenge_admin_comments
  has_many :subscriptions, :dependent => :destroy
  has_many :subscription_holds
  has_many :assessment_sessions
  has_many :sent_friend_invites,     :class_name => "FriendInvite", :foreign_key => :inviter_id
  has_many :received_friend_invites, :class_name => "FriendInvite", :as => :invitee
  has_many :received_user_friend_invites, :class_name => "FriendInvite", :as => :original_invitee
  has_many :friend_ignores, :class_name => "FriendIgnore", :foreign_key => :ignorer_id
  has_many :friend_connections, :dependent => :destroy
  has_many :friends, :class_name => "User", :through => :friend_connections, :source => :other_user do
    def with_eligibility_for_track_gift(track)
      days           = 2
      now            = Time.now.utc.to_s(:db)
      challenge_date = "DATE('#{now}' + INTERVAL time_zones.utc_offset SECOND - INTERVAL #{DEFAULT_CHALLENGE_DELIVERY_TIME} HOUR)"
      recent         = "#{challenge_date} - INTERVAL #{days.to_i} DAY"

      joins("JOIN #{ChallengeProfile.table_name} cp ON cp.user_id = users.id").
      joins("JOIN time_zones ON time_zones.id = users.time_zone_id").
      # friends without overlapping access to the track in question
      joins("LEFT JOIN track_accesses AS a1" +
            "  ON a1.user_id = users.id" +
            "  AND a1.track_id = #{track.id}" +
            "  AND a1.start_date >= #{challenge_date}").
      # ... and who haven't recently unlocked a track
      joins("LEFT JOIN track_accesses AS a2" +
            "  ON a2.user_id = users.id" +
            "  AND a2.start_date >= #{recent}").
        select("users.*, (a1.id IS NULL AND a2.id IS NULL AND cp.status = #{ChallengeProfile::ACTIVE}) AS eligible_for_gift").
        group("users.id")
    end
  end
  has_many :cobranding_relationships, :as => :cobranded
  has_many :challenge_cobrands, :through => :cobranding_relationships
  has_many :likes
  has_many :stream_items, :dependent => :destroy
  has_many :challenge_stamp_events, :dependent => :destroy
  has_many :user_challenge_stamps, :dependent => :destroy
  has_many :challenge_stamps, :through => :user_challenge_stamps
  has_many :challenge_hows, :dependent => :destroy
  has_many :challenge_how_replies, :dependent => :destroy
  has_many :point_events, :dependent => :destroy
  has_many :pact_messages, -> { order(entered_at: :asc) }
  has_many :user_messages, :dependent => :destroy
  has_many :sent_messages,     :class_name => "Message", :foreign_key => "sender_id"
  has_many :received_messages, :class_name => "Message", :foreign_key => "recipient_id"
  has_many :user_pacts
  has_many :pacts, :through => :user_pacts
  has_many :other_user_in_pact, :class_name => "UserPact", :foreign_key => :other_user_id
  has_many :sent_pact_invites,     :class_name => "PactInvite", :foreign_key => :inviter_id
  has_many :received_pact_invites, :class_name => "PactInvite", :foreign_key => :invitee_id
  has_many :user_pact_days
  has_many :sent_encouragements,     :class_name => "Encouragement", :foreign_key => :user_sending_id
  has_many :received_encouragements, :class_name => "Encouragement", :foreign_key => :user_receiving_id
  has_many :sent_sms,       :class_name => "IncomingSmsLog"
  has_many :received_sms,   :class_name => "OutgoingSmsLog", :as => :owner
  has_many :sms_verifications
  has_many :tip_assignments
  has_many :contributing_temp_user_events, :class_name => "TempUserEvent", :foreign_key => :contributing_user_id
  has_many :daily_flow_card_impressions
  has_many :daily_flow_app_impressions
  has_many :friend_invite_recommendations
  has_many :notifications
  has_many :track_accesses
  has_many :track_intents
  has_many :transactions
  has_many :tokens
  has_many :keys
  has_many :wbi_domain_scores
  has_many :wbt_question_impressions
  has_many :assessment_responses
  has_many :assessment_response_archives
  has_many :assessment_session_archives
  has_many :user_devices
  has_many :user_r_values
  has_many :orders
  has_many :user_change_logs
  has_many :anniversary_events
  has_many :email_address_confirmations
  has_many :promo_code_redemptions
  has_many :sponsor_profiles
  has_many :sponsors, :through => :sponsor_profiles
  has_many :task_assignments
  has_many :sponsor_assessment_responses, :through => :assessment_sessions
  has_many :sponsor_unsubscribe_user_responses
  has_many :wbt_long_form_sessions
  has_many :email_bounces
  has_many :email_blocks
  has_many :email_drops
  has_many :email_opens
  has_many :email_spam_reports
  has_many :email_logs, :as => :recipient
  has_many :content_reports, :foreign_key => :reporter_id
  has_many :reported_content, :class_name => "ContentReport", :foreign_key => :reported_id
  has_many :blocker_user_blocks, :class_name => 'UserBlock', :foreign_key => 'blockee_id'
  has_many :blockee_user_blocks, :class_name => 'UserBlock', :foreign_key => 'blocker_id'
  has_many :blockees, -> { where("user_blocks.status = #{UserBlock::ACTIVE}")}, through: :blockee_user_blocks
  has_many :blockers, -> { where("user_blocks.status = #{UserBlock::ACTIVE}")}, through: :blocker_user_blocks
  has_many :user_hides, :foreign_key => 'hider_id'
  has_many :hidden_users, :through => :user_hides, :source => :hidden
  has_many :time_aways, :dependent => :destroy
  has_many :feature_groups, :dependent => :destroy
  has_many :feature_feedbacks, :through => :feature_groups, :dependent => :destroy
  has_many :hipaa_consents
  has_many :sponsor_consents
  has_many :user_tours, as: :user
  has_many :facebook_business_identities, through: :authentications
  has_many :program_intents
  has_many :program_enrollments
  has_many :program_cohorts, through: :program_enrollments

  has_one :challenge_profile
  has_one :privacy_preference, :through => :challenge_profile
  has_one :latest_challenge_assignment, -> { includes(:challenge).order("challenges.sent_on DESC") }, :class_name => "ChallengeAssignment" #, :include => :challenge
  has_one :challenge_author
  has_one :temp_user, -> { order(id: :asc) } # always pick oldest one
  has_one :pending_challenge_user
  has_one :assessment_score
  has_one :challenge_unsubscribe_feedback
  has_one :active_device, -> { order("user_devices.registered_on DESC, user_devices.registered_time DESC, user_devices.id DESC") }, class_name: "UserDevice"
  has_one :user_converting_event
  has_one :token_feedback
  has_one :age_verification
  has_one :orchard_user
  has_one :latest_location, -> { where(status: UserLocation::CURRENT) }, class_name: "UserLocation"

  belongs_to :time_zone

  ###################################################################
  # Callbacks
  before_validation :set_default_values, :set_country
  before_create :set_timezone, :capitalize_names
  before_save :set_full_name, :set_archive_email, :ensure_consistent_country_name
  after_create :explicitly_accept_current_terms!
  after_create :initialize_connection_cache
  after_create :enroll_in_streamlined_privacy
  after_create :enroll_in_one_small_action_ab_test
  after_destroy :remove_stamp_messages

  validates :first_name, :presence => true
  validates :last_name,  :presence => true
  validate  :valid_gender

  validate :valid_zip_code, if: :active?

  ###################################################################
  # Named Scopes

  # Unengaged users are users that have never responded to a challenge
  scope :unengaged, -> { joins(:challenge_profile).where(challenge_profiles: { last_challenge_done_time: nil }) }

  # Include only users whose active sponsor profile was created on or before the specified date
  scope :sponsored_before, ->(cutoff_date) { where("sponsor_profiles.entered_on <= ?", cutoff_date) }

  scope :without_email_type_since, ->(email_type, cutoff_date) { where("(SELECT COUNT(*) FROM email_logs WHERE email_logs.recipient_type = 'User' AND email_logs.recipient_id = users.id AND email_logs.email_type = ? AND email_logs.created_at >= ?) = 0", email_type, cutoff_date) }

  # User.with_role('Challenge Admin')
  #  -or-
  # User.with_role('Challenge Admin', 'Beta Usefr') (gives back either)
  scope :with_role, ->(*roles) {
    joins(:role_assignments => :role).
    where(:roles => {:name => Array.wrap(roles)}).
    order(:first_name, :last_name)
  }

  scope :without_assignment_for, ->(options) {
    active.joins(:challenge_profile).joins(:time_zone)
    .joins("LEFT JOIN #{ChallengeAssignment.table_name} ON #{table_name}.id = #{ChallengeAssignment.table_name}.user_id and #{ChallengeAssignment.table_name}.challenge_date = '#{options[:sent_on]}'").where %Q~
      #{ChallengeProfile.table_name}.first_challenge_date <= '#{options[:sent_on]}'
      AND #{TimeZone.table_name}.utc_offset BETWEEN #{options[:start_offset]} AND #{options[:end_offset]}
      AND #{ChallengeAssignment.table_name}.id is NULL
    ~
  }

  scope :needing_reminder_for, ->(options) {
    active.joins(:challenge_assignments).joins(:challenges).joins(:challenge_profile).joins(:time_zone).where %Q~
      #{Challenge.table_name}.sent_on = '#{options[:sent_on]}'
      AND #{ChallengeAssignment.table_name}.status = #{ChallengeAssignment::NO_RESPONSE}
      AND #{ChallengeAssignment.table_name}.reminded_on IS NULL
      AND #{TimeZone.table_name}.utc_offset BETWEEN #{options[:start_offset]} AND #{options[:end_offset]}
    ~
  }

  scope :needing_challenge_sms_for, ->(now) {
    active.joins(:challenge_assignments).joins(:challenges).joins(:challenge_profile).joins(:time_zone).joins(:subscriptions).where %Q~
      #{ChallengeProfile.table_name}.start_date <= #{Challenge.table_name}.sent_on
      AND #{Challenge.table_name}.sent_on = DATE('#{now}' + INTERVAL #{TimeZone.table_name}.utc_offset SECOND)
      AND #{ChallengeAssignment.table_name}.status = #{ChallengeAssignment::NO_RESPONSE}
      AND #{Subscription.table_name}.message_type = #{MessageTypes::CHALLENGE}
      AND #{Subscription.table_name}.channel_type = #{ChannelTypes::SMS}
      AND NOT EXISTS (
        SELECT 1
        FROM #{OutgoingSmsLog.table_name}
        WHERE
          related_object_id = #{ChallengeAssignment.table_name}.id
          AND related_object_type = 'ChallengeAssignment'
          AND message_type = #{OutgoingSmsLog::CHALLENGE_DELIVERY}
      )
      AND DATE_ADD(#{Challenge.table_name}.sent_on, INTERVAL #{Subscription.table_name}.delivery_time SECOND) <= DATE_ADD('#{now}', INTERVAL #{TimeZone.table_name}.utc_offset SECOND)
      AND DATE_ADD(#{Challenge.table_name}.sent_on, INTERVAL #{Subscription.table_name}.delivery_time SECOND) >= DATE_ADD(DATE_ADD(#{ChallengeAssignment.table_name}.sent_on, INTERVAL #{ChallengeAssignment.table_name}.sent_time HOUR_SECOND), INTERVAL #{TimeZone.table_name}.utc_offset SECOND)
    ~
  }

  scope :needing_reminder_sms_for, ->(now) {
    active.joins(:challenge_assignments).joins(:challenges).joins(:challenge_profile).joins(:time_zone).joins(:subscriptions).where %Q~
      #{ChallengeProfile.table_name}.start_date <= #{Challenge.table_name}.sent_on
      AND #{Challenge.table_name}.sent_on = DATE('#{now}' + INTERVAL #{TimeZone.table_name}.utc_offset SECOND)
      AND #{ChallengeAssignment.table_name}.status = #{ChallengeAssignment::NO_RESPONSE}
      AND #{Subscription.table_name}.message_type = #{MessageTypes::CHALLENGE_REMINDER}
      AND #{Subscription.table_name}.channel_type = #{ChannelTypes::SMS}
      AND NOT EXISTS (
        SELECT 1
        FROM #{OutgoingSmsLog.table_name}
        WHERE
          related_object_id = #{ChallengeAssignment.table_name}.id
          AND related_object_type = 'ChallengeAssignment'
          AND message_type = #{OutgoingSmsLog::REMINDER_DELIVERY}
      )
      AND DATE_ADD(#{Challenge.table_name}.sent_on, INTERVAL #{Subscription.table_name}.delivery_time SECOND) <= DATE_ADD('#{now}', INTERVAL #{TimeZone.table_name}.utc_offset SECOND)
      AND DATE_ADD(#{Challenge.table_name}.sent_on, INTERVAL #{Subscription.table_name}.delivery_time SECOND) >= DATE_ADD(DATE_ADD(#{ChallengeAssignment.table_name}.sent_on, INTERVAL #{ChallengeAssignment.table_name}.sent_time HOUR_SECOND), INTERVAL #{TimeZone.table_name}.utc_offset SECOND)
    ~
  }

  scope :intending_to_switch_track_today, ->(options) {
    without_assignment_for(options).joins(:track_intents).where %Q~
      #{TrackIntent.table_name}.status = #{TrackIntent::PENDING_SWITCH}
      AND #{TrackIntent.table_name}.intent_date = '#{options[:sent_on]}'
    ~
  }

  scope :needing_switched_to_default_track, ->(options) {
    # Return users who:
    # 1.  Don't have a current challenge assignment for the specified date
    # 2.  Are not already on the default track
    # 3.  Do not have a track access record for their current track, for the specified date

    without_assignment_for(options).joins("INNER JOIN #{Track.table_name} ON #{Track.table_name}.id = #{ChallengeProfile.table_name}.track_id").where %Q~
      #{Track.table_name}.track_type != #{Track::DEFAULT}
      AND NOT EXISTS (
        SELECT 1
        FROM #{TrackAccess.table_name}
        WHERE user_id = #{table_name}.id
          AND track_id = #{ChallengeProfile.table_name}.track_id
          AND '#{options[:sent_on]}' BETWEEN start_date and end_date
      )
    ~
  }

  scope :with_touch_past_start_at_least, ->(time) {
    joins(:challenge_profile).where(["last_touch_time > (start_time + INTERVAL ? SECOND)", time.seconds.to_i])
  }

  scope :in_track, -> (track) { includes(:challenge_profile).where(challenge_profiles: { track_id: track.id }) }

  scope :joined_site_on, -> (date) { includes(:challenge_profile).where(challenge_profiles: { start_date: date }) }

  ###################################################################
  # Validations
  validates_presence_of :email
  validates_uniqueness_of :key
  validates_uniqueness_of :embrace_id, :allow_blank => true

  ###################################################################
  # Delegates
  delegate :title,             :to => :current_track,      :prefix => true
  delegate :title,             :to => :current_challenge,  :prefix => true
  delegate :away_text,         :to => :active_away_record, :prefix => false,   :allow_nil => true
  delegate :total_completions, :to => :challenge_profile,  :prefix => false,   :allow_nil => true
  delegate :visited_tutorial?, :to => :challenge_profile,  :prefix => false,   :allow_nil => true
  delegate :last_touch_time,   :to => :challenge_profile,  :prefix => false,   :allow_nil => true

  delegate :accessible_sponsors,
           :can_see_sponsor?,
           :current_sponsors,
           :has_sponsor?,
           :latest_sponsor,
           :sponsored?, :to => :sponsored_user

  delegate :eligible_to_view_video?, :to => :challenge_video_participant

  accepts_nested_attributes_for :authentications

  ###################################################################
  # Public Methods

  def segment
  current_sponsors.first&.segment_uuid

  def well_being_guide?
    Rails.application.secrets.well_being_guide_emails.include?(email)
  end

  def point_event_messages
    PointEventMessage.peek(self)
  end

  def setup_challenge_profile_in_track!(track:, event_source: UserEvent::Source::WEB)
    track.join_now!(self) unless track.default?
    setup_challenge_profile!(event_source: event_source, track: track)
  end

  def setup_challenge_profile!(event_source: UserEvent::Source::WEB, track: Track.default_track)
    transaction do
      # Put the user in the correct roles
      self.roles << Role.find_by_name("Challenge User")

      # Create the Joined Site Stream Event
      StreamItem.create!(:user => self, :item_type => StreamItem::JOINED_SITE, :event_at => Time.now())

      # Create the challenge profile
      profile = ChallengeProfile.create!(user: self, start_date: Time.zone.now, track: track, track_ends_on: track_accesses.last.try(:end_date))

      # Create a stub privacy preference record
      PrivacyPreference.create!(:challenge_profile => profile)

      # Transfer any invites that match user's email or FB
      assign_pending_friend_invites

      # Auto-accept any pending friend requests
      accept_pending_friend_invites!

      # Create a location record for the user
      if self.temp_user
        UserLocation.set_location(self, self.temp_user.latest_ip)
      end

      # Perform any identity provider-specific setup tasks
      if is_facebook_user?
        setup_challenge_profile_for_facebook!(event_source)
      else
        setup_challenge_profile_for_myh_auth!(event_source)
      end
    end
  end

  def setup_challenge_profile_for_facebook!(event_source)
    # Auto-verify age
    self.age_verified!(AgeVerification::FACEBOOK, self.facebook_uid)

    # Add Registration User Event
    self.register_sourced_event(UserEvent::REGISTRATION_FACEBOOK, event_source)

    # Add Profile Picture User Event
    self.register_sourced_event(UserEvent::SELECT_PROFILE_PICTURE, event_source)
  end

  def setup_challenge_profile_for_myh_auth!(event_source)
    # Age verification
    self.age_verified!(AgeVerification::BIRTHDATE, self.date_of_birth)

    # Add Registration User Event
    self.register_sourced_event(UserEvent::REGISTRATION_EMAIL, event_source)
  end

  def assign_pending_friend_invites
    Invitations.accept_all_email_invites(self)

    if is_facebook_user?
      FriendInvite.where(invitee_type: 'Facebook', invitee_id: self.facebook_uid).each do |invite|
        invite.invitee = self
        invite.save!
      end
    end
  end

  def accept_pending_friend_invites!
    received_friend_invites.pending.each(&:accept!)
  end

  def disable_challenge_account!
    # Auto return from any active time aways
    self.time_aways.active.each(&:user_disabled!)

    # Remove your profile page and set deactivated at
    if self.challenge_profile.present?
      self.challenge_profile.status = ChallengeProfile::DELETED
      self.challenge_profile.deactivated_at = Time.now
      self.challenge_profile.save!
    end

    # Scrub private user data
    new_email = self.email
    new_email.gsub!(/[@\.]/, '_')
    new_email += "@example.com"
    new_email = rand(99999).to_s + "_" + new_email
    self.email = new_email
    self.facebook_uid = nil
    self.status = DELETED
    self.save!

    # Asynchronously remove other, related, account information without making the user wait
    UserRemoveRelatedAccountInformationJob.perform_async(self.id)
  end

  # This is an expensive method so we run it asynchronously. Some objects have multiple other destroy dependencies while others need to be soft-deleted.
  def remove_related_account_information!
    # Remove all posts (mark as private)
    self.challenge_hows.each(&:soft_delete!)

    # Remove all personal connections
    self.friend_connections.each(&:destroy)

    # Remove any pending invites you sent out
    self.sent_friend_invites.each(&:soft_delete!)

    # Remove subscriptions
    self.subscriptions.each(&:destroy)

    # Fail any uncompleted challenges
    self.challenge_assignments.active.each(&:failed!)

    # Cancel any program enrollments
    self.program_enrollments.active.each(&:cancel!)

    # Soft-delete any pending pact invites
    self.sent_pact_invites.pending.update_all(status: PactInvite::DELETED)
    self.received_pact_invites.pending.update_all(status: PactInvite::DELETED)

    self.track_intents.pending.update_all(status: TrackIntent::CANCELED)
    self.keys.active.update_all(status: Key::FORFEITED)
    self.tokens.active.update_all(status: Token::FORFEITED)

    # Soft-delete authentications
    self.authentications.each(&:remove!)

    # Fail any pacts, without sending email
    self.current_pact.failed!(false) if self.current_pact

    # Let any sponsor profiles know of the event
    self.sponsor_profiles.each(&:user_account_disabled!)

    # Register Event
    register_event(UserEvent::UNSUBSCRIBED_CHALLENGES)

    # Remove all stream item notifications for this user
    StreamItemNotification.for(self).flush!

    # Remove leaderboard data
    Leaderboard.destroy(self.id)
    CachedUserConnection.destroy(self.id)

    WbidAccountNotificationJob.perform_async(wbid_key, "deactivation", Time.now.iso8601) if wbid_key
  end

  def ban!
    disable_challenge_account!
    self.reload
    self.facebook_uid = self.archive_facebook_uid
    self.email        = self.archive_email
    self.status       = BANNED
    self.save!
  end

  def is_facebook_user?
    # faster check goes first
    self.facebook_uid || authentications.for_provider('facebook').exists?
  end

  def third_party_authentications
    authentications.third_party_providers.pluck(:provider).uniq
  end

  def role_symbols
    roles.map do |role|
      role.token.to_sym
    end
  end

  def display_name
    "#{first_name} #{last_name.first(1).upcase}."
  end

  def friends_with?(other_user)
    self.friend_connections.exists?(other_user: other_user)
  end

  def mutual_friends_with(other_user)
    User.joins(:friend_connections).where("(friend_connections.user_id IN (?) AND friend_connections.other_user_id = ?)",other_user.friend_connections.pluck(:other_user_id), id)
  end

  def pending_invite?(other_user)
    self.sent_friend_invites.pending.exists?(invitee_type: 'User', invitee: other_user)
  end

  def pending_facebook_invites
    self.sent_friend_invites.pending.facebook
  end

  def can_message?(other_user)
    allowed_to?(:messages, other_user) &&
    self.id != other_user.id &&
    !blocking_or_blocked_by?(other_user) &&
    !other_user.away? ||
    well_being_guide?
  end

  def can_connect_with?(other_user)
    self != other_user &&
    !friends_with?(other_user) &&
    !pending_invite?(other_user) &&
    other_user.challenge_profile.privacy_preference.profile_invites == PrivacyPreference::PUBLIC
  end

  def can_destroy_comment?(comment)
    self == comment.user || (comment.related_object.class == StreamItem && comment.related_object.user == self)
  end

  def can_encourage?(target_user, challenge_date)
    friends_with?(target_user) && # excludes self
      can_encourage_for_date?(challenge_date) &&
      target_user.current_challenge_date == challenge_date &&
      (challenge = target_user.challenge_for(challenge_date)) &&
      !!target_user.assignment_for(challenge) &&
      !target_user.completed?(challenge) &&
      !target_user.passed?(challenge) &&
      !already_encouraged?(target_user, challenge_date)
  end

  def can_encourage_for_date?(challenge_date)
    return true unless daily_encouragement_limit

    ((current_challenge_date == challenge_date) &&
     (sent_encouragements_for(challenge_date).count < daily_encouragement_limit))
  end

  def already_encouraged?(user, challenge_date)
    sent_encouragements_for(challenge_date).where(:user_receiving_id => user.id).exists?
  end

  def daily_encouragement_limit
    return nil if well_being_guide?

    (max_level? ? MAX_LEVEL_ENCOURAGEMENTS_PER_DAY : NORMAL_ENCOURAGEMENTS_PER_DAY)
  end

  def daily_encouragements_remaining(challenge_date = current_challenge_date)
    return nil unless daily_encouragement_limit

    daily_encouragement_limit - sent_encouragements_for(challenge_date).count
  end

  def sent_encouragements_for(challenge_date)
    sent_encouragements.joins(:challenge).where("challenges.sent_on = ?", challenge_date)
  end

  def received_encouragements_for(challenge_date)
    received_encouragements.joins(:challenge).where("challenges.sent_on = ?", challenge_date)
  end

  def time_zone_name
    self.time_zone.name || "US/Eastern" rescue "US/Eastern"
  end

  # Get what a user's current challenge is based on their timezone
  def current_challenge
    self.current_track.challenge_for(self.current_challenge_date, self)
  end

  def challenge_for(challenge_date)
    sql = %Q~
      SELECT challenges.*
      FROM challenges
      JOIN challenge_assignments ON challenge_assignments.challenge_id = challenges.id
      WHERE challenge_assignments.user_id =  #{self.id}
        AND challenges.sent_on            = '#{challenge_date.to_s(:db)}'
    ~
    Challenge.find_by_sql(sql).first
  end

  def challenge_assignment_for(challenge_date)
      sql = %Q~
      SELECT challenge_assignments.*
      FROM challenges
      JOIN challenge_assignments ON challenge_assignments.challenge_id = challenges.id
      WHERE challenge_assignments.user_id =  #{self.id}
        AND challenges.sent_on            = '#{challenge_date.to_s(:db)}'
    ~
    ChallengeAssignment.find_by_sql(sql).first
  end

  def current_challenge_assignment
    challenge_assignments.find_by_challenge_id(current_challenge.id)
  end

  def current_track
    self.challenge_profile.current_track
  end

  def current_track_days_in(track = self.current_track)
    current_track_access(track).try(:days_in)
  end

  def current_track_id
    self.challenge_profile.track_id
  end

  def current_track_access(track = self.current_track)
    self.track_accesses.current_for(self.current_challenge_date).where(:track_id => track.id).first
  end

  def current_track_name
    current_track.title
  end

  def has_access_to_track?(track, date = self.current_challenge_date)
    if track == Track.default_track
      true
    else
      self.track_accesses.current_for(date).exists?(:track_id => track.id)
    end
  end

  def has_future_access_to_track?(track, date = self.current_challenge_date)
    if track == Track.default_track
      true
    else
      self.track_accesses.where(["start_date > ?", self.current_challenge_date]).exists?(:track_id => track.id)
    end
  end

  def remaining_days_of_track_access(track)
    access = self.track_accesses.current_for(self.current_challenge_date).where(:track_id => track.id).first
    access.end_date - self.current_challenge_date
  end

  def in_premium_track?
    [Track::OVERVIEW, Track::TARGETED].include?(self.current_track.track_type)
  end

  def can_purchase_track?
    # NOTE: once we roll out payment options, this should always return true.
    (key_count >= Exchange::KEYS_FOR_TRACK_ACCESS) || (token_count >= (Exchange::TOKENS_FOR_KEY * Exchange::KEYS_FOR_TRACK_ACCESS))
  end

  def can_unlock_track?(track)
    can_purchase_track? && ((!has_access_to_track?(track) && !has_future_access_to_track?(track)) || (on_last_day_of_track?(track)))
  end

  def on_last_day_of_track?(track)
    return false unless track.maximum_days_of_access.present?
    has_access_to_track?(track) && remaining_days_of_track_access(track) == 0
  end

  def completing_track_today?
    new_track_tomorrow? && tomorrows_track.default? && pending_track_switch.nil?
  end

  def friends_eligible_for_track_gift(track)
    friends.with_eligibility_for_track_gift(track).where("a1.id IS NULL AND a2.id IS NULL")
  end

  def can_gift_track?(track = nil)
    can_gift_in_general = ((keys.where(:giftable => true).count >= Exchange::KEYS_FOR_TRACK_ACCESS) ||
                           (token_count >= (Exchange::TOKENS_FOR_KEY * Exchange::KEYS_FOR_TRACK_ACCESS)))

    if track.nil?
      can_gift_in_general
    else
      # the user must have friends who are eligible to be gifted this track
      (can_gift_in_general && friends_eligible_for_track_gift(track).exists?)
    end
  end

  # FIXME: Unused code
  def tokens_needed_to_purchase
    Exchange::TOKENS_FOR_KEY - token_count
  end

  def pending_track_switch
    self.track_intents.pending.first
  end

  def ending_premium_track?
    return false unless in_premium_track?

    track_access = self.track_accesses.current_for(current_challenge_date).find_by(track: current_track)

    track_access && track_access.end_date == current_challenge_date
  end

  # detects if we're going to switch to a new track tomorrow
  def new_track_tomorrow?
    tomorrows_track != current_track
  end

  def tomorrows_track
    if pending_track_switch && pending_track_switch.intent_date == current_challenge_date + 1
      pending_track_switch.track
    elsif ending_premium_track?
      Track.default_track
    else
      current_track
    end
  end

  def switch_track!(track)
    if track == Track.default_track
      self.challenge_profile.track_ends_on = nil
    else
      access = self.current_track_access(track)
      if access
        self.challenge_profile.track_ends_on = access.end_date
      else
        # This shouldn't happen, but if it does, switch the user to the default track instead
        NewRelic::Agent.notice_error(
          Exception.new("The user does not have access to requested track - switching to default track instead."),
          user_id: self.id, track_id: track.id
        )
        self.challenge_profile.track_ends_on = nil
        track = Track.default_track
      end
    end
    self.challenge_profile.track = track
    self.challenge_profile.save!
  end

  def update_track_ends_on_from_intent!(track_intent)
    if track_intent.track == challenge_profile.track && !on_last_day_of_track?(challenge_profile.track)
      # This track intent is for our current track and we're not on the last day of our track.
      # This might happen if I activated another track and then changed my mind and activated this track
      # again.  This intent will be deleted momentarily, but before that happens we need to update track_ends_on.

      if challenge_profile.track == Track.default_track
        # If I'm on the default track and I have an intent to switch to the default track, clear my track_ends_on
        update_track_ends_on!(nil)
      else
        # If I'm not on the default track and I have an intent to switch to the track I'm currently on, reset my
        # track_ends_on to the end date of my current track access
        update_track_ends_on!(self.current_track_access(challenge_profile.track).end_date)
      end
    else
      # Change the end date of the current track to the intent date minus 1 day
      update_track_ends_on!(track_intent.intent_date - 1)
    end
  end

  def update_track_ends_on!(ends_on)
    self.challenge_profile.track_ends_on = ends_on
    self.challenge_profile.save!
  end

  def current_program
    current_program_enrollment&.program
  end

  def current_program_enrollment
    return @current_program_enrollment if instance_variable_defined?(:@current_program_enrollment)

    @current_program_enrollment = self.program_enrollments.active.last
    @current_program_enrollment ||= begin
      last_completed_enrollment = self.program_enrollments.complete.last
      if last_completed_enrollment && last_completed_enrollment.program_cohort.end_date == self.current_challenge_date
        last_completed_enrollment
      end
    end
  end

  def current_program_cohort
    current_program_enrollment&.program_cohort
  end

  # Premium track challenge content is locked down
  def can_see_content_for?(challenge)
    if challenge.track.default?
      return true
    elsif self.has_access_to_track?(challenge.track)
      return true
    elsif self.assigned?(challenge)
      return true
    else
      return false
    end
  end

  def allowed_to_complete?(object)
    challenge = case object
      when ChallengeAssignment then object.challenge
      when Challenge then object
    end

    if !self.completed?(challenge) && !self.passed?(challenge) && (self.current_challenge_date - challenge.sent_on) <= 7 && self.assignment_for(challenge)
      true
    else
      false
    end
  end
  alias :can_complete? :allowed_to_complete?

  def current_level
    ChallengeLevel.determine_by_id(challenge_profile.challenge_level_id)
  end
  def current_level_json
    current_level.json
  end
  def current_points
    challenge_profile.point_total
  end

  def token_count
    tokens.count
  end

  def tokens_spent
    Token.count_by_sql("SELECT count(*) FROM #{Token.table_name} WHERE user_id = #{self.id} AND status = #{Token::EXCHANGED}")
  end

  def key_count
    keys.count
  end

  def current_level_name
    current_level.name
  end

  def max_level?
    current_level.max_level?
  end

  def next_level
    ChallengeLevel.determine_next_by_id(challenge_profile.challenge_level_id)
  end

  def points_to_next_level
    if !max_level?
      ChallengeLevel.determine_next_by_id(challenge_profile.challenge_level_id).points_required - challenge_profile.point_total
    else
      return nil
    end
  end

  def points_earned_between(start_time, end_time)
    start_date = start_time.to_date
    end_date   = end_time.to_date

    # Note: using the entered_on range so that we can use the index on user_id, entered_on and not asplode the database.
    point_events.where(entered_on: start_date..end_date).where(entered_time: start_time..end_time).sum(:points)
  end

  def completed?(challenge)
    challenge_assignments.completed.exists?(:challenge_id => challenge.id)
  end

  def passed?(challenge)
    challenge_assignments.passed.exists?(:challenge_id => challenge.id)
  end

  def last_completed_challenge
    ca = challenge_assignments.completed.order(:sent_on).last
    return(ca ? ca.challenge : nil)
  end

  def told_us_how?(challenge)
    challenge_hows.exists?(:challenge_id => challenge.id)
  end

  def assignment_for(challenge)
    challenge_assignments.where(challenge_id: challenge.id).first
  end

  def assigned?(challenge)
    challenge_assignments.where(challenge_id: challenge.id).exists?
  end

  def recent_stamp_earns(options)
    options.reverse_merge!({:count => 4})
    self.user_challenge_stamps.includes(:challenge_stamp).order("earned_at DESC, id DESC").limit(options[:count]).to_a
  end

  def recent_stamps(options = {})
    options.reverse_merge!({:count => 4})
    recent_stamp_earns(options).map(&:challenge_stamp)
  end

  def likes?(related_object)
    self.likes.exists?(:related_object_type => related_object.class.to_s, :related_object_id => related_object.id)
  end

  def smiles_for_challenge(challenge)
    Like.count_by_sql(%Q~
      SELECT COUNT(*)
      FROM #{Like.table_name} l
        JOIN #{ChallengeHow.table_name} ch ON l.related_object_type = 'ChallengeHow' AND ch.id = l.related_object_id
      WHERE ch.challenge_id = #{challenge.id}
        AND ch.status = #{ChallengeHow::ACTIVE}
        AND l.user_id = #{self.id}
    ~)
  end

  def smiles_on_hows_between(start_date, end_date)
    challenge_hows.joins(:challenge, :likes).where(challenges: {sent_on: start_date..end_date}).count
  end

  def friend_completions_between(start_date, end_date)
    friends.joins(:challenge_assignments => :challenge).where(challenges: {sent_on: start_date..end_date}, challenge_assignments: {status: ChallengeAssignment::COMPLETE}).count
  end

  def replies_for_challenge(challenge)
    ChallengeHowReply.count_by_sql(%Q~
      SELECT COUNT(*)
      FROM #{ChallengeHowReply.table_name} r
        JOIN #{ChallengeHow.table_name} ch ON r.challenge_how_id = ch.id
      WHERE ch.challenge_id = #{challenge.id}
        AND ch.status = #{ChallengeHow::ACTIVE}
        AND r.status = #{ChallengeHowReply::ACTIVE}
        AND r.user_id = #{self.id}
    ~)
  end

  def friends_who_completed_challenge(challenge,hows=false)
    if hows
      sql = "SELECT users.*, hows.how_text as how_text, hows.id AS how_id, IF(hows.how_text>'','1','0') as includes_how FROM
      (SELECT other_user_id FROM (SELECT other_user_id FROM friend_connections WHERE user_id=#{self.id}) AS friends
      JOIN challenge_assignments ON challenge_assignments.user_id = friends.other_user_id
      AND challenge_assignments.challenge_id = #{challenge.id} AND status = #{ChallengeAssignment::COMPLETE}) AS friends_completed
      JOIN users ON friends_completed.other_user_id = users.id LEFT JOIN challenge_hows hows ON users.id=hows.user_id AND challenge_id=#{challenge.id} and hows.status != #{ChallengeHow::DELETED} ORDER BY includes_how desc"
    else
    sql = "SELECT users.* FROM
          (SELECT other_user_id FROM (SELECT other_user_id FROM friend_connections WHERE user_id=#{self.id}) AS friends
          JOIN challenge_assignments ON challenge_assignments.user_id = friends.other_user_id
          AND challenge_assignments.challenge_id = #{challenge.id} AND status = #{ChallengeAssignment::COMPLETE}) AS friends_completed
          JOIN users ON friends_completed.other_user_id = users.id"
    end
    User.find_by_sql(sql)
  end

  def friends_who_completed_on_challenge_date(date, options = {})
    options.reverse_merge!({:limit => 12})
    sql = %Q~
      SELECT users.*
      FROM (
        SELECT other_user_id FROM (
          SELECT other_user_id FROM friend_connections WHERE user_id=#{self.id}
        ) AS friends
        JOIN challenge_assignments ON challenge_assignments.user_id = friends.other_user_id
          AND status = #{ChallengeAssignment::COMPLETE}
        JOIN challenges ON challenge_assignments.challenge_id = challenges.id
          AND challenges.sent_on = '#{date.to_s(:db)}'
      ) AS friends_completed
      JOIN users ON friends_completed.other_user_id = users.id
      LIMIT #{options[:limit]}
    ~
    User.find_by_sql(sql)
  end

  def friends_who_completed_challenge_plus_hows(challenge)
    sql = "SELECT users.* FROM
    (SELECT other_user_id FROM (SELECT other_user_id FROM friend_connections WHERE user_id=#{self.id}) AS friends
    JOIN challenge_assignments ON challenge_assignments.user_id = friends.other_user_id
    AND challenge_assignments.challenge_id = #{challenge.id} AND status = #{ChallengeAssignment::COMPLETE}) AS friends_completed
    JOIN users ON friends_completed.other_user_id = users.id"
    User.find_by_sql(sql)
  end

  def friends_who_are_streaking(minimum_streak)
    sql = "SELECT users.* FROM
    (SELECT other_user_id FROM (SELECT other_user_id FROM friend_connections WHERE user_id=#{self.id}) AS friends
    JOIN challenge_profiles ON challenge_profiles.user_id = friends.other_user_id and current_streak >= #{minimum_streak}) AS friends_streaking
    JOIN users ON friends_streaking.other_user_id = users.id"
    User.find_by_sql(sql)
  end

  def inbox_threads(offset = 0, limit = 20)
    MessageThread.find_by_sql(%Q~
      SELECT *
      FROM (
        SELECT mt.*, LEFT(m.body, 80) AS message_summary, um.read, m.sent_time, m.sender_id, m.recipient_id,
               1 AS counter, IF(m.sender_id = #{self.id}, 1, 0) AS sent_counter
        FROM #{MessageThread.table_name} AS mt
          JOIN #{Message.table_name}     AS m  ON m.message_thread_id = mt.id
          JOIN #{UserMessage.table_name} AS um ON um.message_id       = m.id
        WHERE um.user_id = #{self.id}
          AND um.deleted = 0
        ORDER BY IF(um.read = 0, 0, 1), IF(um.read = 0, m.sent_time, '9999-99-99'), IF(um.read = 0, m.id, 99999999), m.sent_time DESC, m.id DESC
      ) AS threads
      GROUP BY threads.id
      HAVING SUM(counter) <> SUM(sent_counter)
      ORDER BY threads.sent_time DESC, threads.id DESC
      LIMIT #{limit} OFFSET #{offset}
    ~)
  end

  def sent_threads(offset = 0, limit = 20)
    MessageThread.find_by_sql(%Q~
      SELECT *
      FROM (
        SELECT mt.*, LEFT(m.body, 80) AS message_summary, um.read, m.sent_time, m.sender_id, m.recipient_id,
               1 AS counter, IF(m.recipient_id = #{self.id}, 1, 0) AS received_counter
        FROM #{MessageThread.table_name} AS mt
          JOIN #{Message.table_name}     AS m  ON m.message_thread_id = mt.id
          JOIN #{UserMessage.table_name} AS um ON um.message_id       = m.id
        WHERE um.user_id = #{self.id}
          AND um.deleted = 0
        ORDER BY IF(um.read = 0, 0, 1), IF(um.read = 0, m.sent_time, '9999-99-99'), IF(um.read = 0, m.id, 99999999), m.sent_time DESC, m.id DESC
      ) AS threads
      GROUP BY threads.id
      HAVING SUM(counter) <> SUM(received_counter)
      ORDER BY threads.sent_time DESC, threads.id DESC
      LIMIT #{limit} OFFSET #{offset}
    ~)
  end

  def unread_thread_count
    MessageThread.count_by_sql(%Q~
      SELECT COUNT(DISTINCT mt.id) AS count
      FROM #{MessageThread.table_name} AS mt
        JOIN #{Message.table_name}     AS m  ON m.message_thread_id = mt.id AND m.recipient_id = #{self.id}
        JOIN #{UserMessage.table_name} AS um ON um.message_id       = m.id
      WHERE um.user_id = #{self.id}
        AND um.deleted = 0
        AND um.read = 0
    ~)
  end

  def inbox_thread_count
    MessageThread.count_by_sql(%Q~
      SELECT COUNT(DISTINCT mt.id) AS count
      FROM #{MessageThread.table_name} AS mt
        JOIN #{Message.table_name}     AS m  ON m.message_thread_id = mt.id AND m.recipient_id = #{self.id}
        JOIN #{UserMessage.table_name} AS um ON um.message_id       = m.id
      WHERE um.user_id = #{self.id}
        AND um.deleted = 0
    ~)
  end

  def sent_thread_count
    MessageThread.count_by_sql(%Q~
      SELECT COUNT(DISTINCT mt.id) AS count
      FROM #{MessageThread.table_name} AS mt
        JOIN #{Message.table_name}     AS m  ON m.message_thread_id = mt.id AND m.sender_id = #{self.id}
        JOIN #{UserMessage.table_name} AS um ON um.message_id       = m.id
      WHERE um.user_id = #{self.id}
        AND um.deleted = 0
    ~)
  end

  def request_count
    new_facebook_friends.count + pending_invite_count + pact_invite_count
  end

  def facebook_friends
    return [] unless self.facebook_uid && self.facebook_session_key
    return @_fb_friends if @_fb_friends

    # if an exception occurs while getting the data from FB, we don't want to cache the empty result
    @_fb_friends = begin
      Rails.cache.fetch("fb_friends:#{self.id}", :expires_in => 24.hours) do
        client = FacebookClient.new(facebook_session_key)
        response = client.request(:get, "#{facebook_uid}/friends", params: { fields: "id,name,first_name,last_name", limit: 1000 })

        response.parsed["data"].collect(&OpenStruct.method(:new))
      end
    rescue OAuth2::Error
      []
    end
  end

  def facebook_friends_not_connected
    return [] unless facebook_friends.present?
    User.where(facebook_uid: facebook_friends.map(&:id)).where.not(id: friend_ids)
  end

  def facebook_friends_with_challenge_friends(options = {})
    options.reverse_merge!({
      :limit          => 10,
      :filter_fb_uids => []
    })

    sql = (%Q~
      SELECT COUNT( * ) AS num_connections, fof.facebook_profile_id AS facebook_uid
      FROM facebook_connections   AS fof
        LEFT JOIN users           AS current_users   ON current_users.archive_facebook_uid = fof.facebook_profile_id
        JOIN facebook_connections AS friends         ON friends.connected_id = fof.facebook_profile_id
        JOIN users                AS connected_users ON connected_users.facebook_uid = fof.connected_id
      WHERE current_users.id IS NULL
        AND friends.facebook_profile_id = #{self.facebook_uid}
        AND fof.connected_id <> friends.facebook_profile_id
    ~)

    sql += " AND fof.facebook_profile_id NOT IN (#{options[:filter_fb_uids].join(',')})" if options[:filter_fb_uids].length > 0
    sql += " GROUP BY fof.facebook_profile_id ORDER BY COUNT( * ) DESC"
    sql += " LIMIT #{options[:limit]}" if options[:limit]

    self.class.connection.select_all(sql).map!(&:symbolize_keys!)
  end

  def new_facebook_friends
    return [] unless self.facebook_uid && self.facebook_session_key
    # Check for the value in the cache
    fb_friends_here = Rails.cache.read("new_fb_friends_#{self.id}")

    if fb_friends_here
      return User.where(id: fb_friends_here)
    else
      UserFetchNewFacebookFriendsJob.perform_async(self.id)

      return []
    end
  end

  def fetch_new_facebook_friends
    return unless self.facebook_uid && self.facebook_session_key

    fb_friend_ids = facebook_friends.map(&:id)
    fb_friends_here = self.class.find_challenge_users_with_facebook_ids(fb_friend_ids)

    unless fb_friends_here.blank?
      # Remove existing friends
      fb_friends_here -= friends

      # Remove people who have explicitly invited me, since they show separately
      fb_friends_here -= received_friend_invites.pending.eager_load(:inviter).map(&:inviter)

      # Remove people I've invited
      fb_friends_here -= sent_friend_invites.pending.user_to_user.map(&:invitee)

      # Remove people I've ignored
      fb_friends_here -= friend_ignores.map(&:ignored)
    end

    # cache whatever we got back
    Rails.cache.write("new_fb_friends_#{self.id}", fb_friends_here.map(&:id), {:expires_in => 4.hours})
  end

  def ignored_user?(other_user)
    friend_ignores.exists?(ignored: other_user)
  end

  def ignore_user!(other_user)
    self.friend_ignores.create!(:ignored_id => other_user.id)
  end

  def unignore_user!(other_user)
    fi = self.friend_ignores.where(:ignored_id => other_user.id).first
    fi.destroy if fi
  end

  def pending_invite_count
    self.received_friend_invites.pending.count
  end

  # For generality, we return an array (possibly empty) of users,
  # though, currently, it will contain, at most, one user.
  def possible_inviters
    res = []

    # If this user does not have an FB UID but was (possibly) invited by an FB user, we want to find that (possible) inviter.
    if !facebook_uid && temp_user
      event = temp_user.temp_user_events.where(:event_type => TempUserEvent::CONVERSION_EVENT_FOR_VIEW_EVENT.values).first
      if event && event.related_object.is_a?(FriendInvite) && event.related_object.original_invitee_type == 'Facebook'
        res << event.related_object.inviter
      end
    end

    res
  end

  def allowed_to?(privacy_preference_attribute, target_user)
    target_user.privacy_preference.authorized?(privacy_preference_attribute, UserRelationship.calculate_relationship_between(self, target_user))
  end

  def can_see?(item_with_privacy)
    (
      item_with_privacy.privacy == PrivacyPreference::PUBLIC ||
      (item_with_privacy.privacy == PrivacyPreference::CONNECTIONS_ONLY && self.friends_with?(item_with_privacy.user)) ||
      (item_with_privacy.user == self)
    )
  end

  def show_motd?(motd)
    begin
      return false unless motd
      return false if self.challenge_profile.start_date >= Date.yesterday
      return self.challenge_profile.last_seen_motd < motd.id
    end
  end

  def current_pact?
    UserPact.exists?(:user_id => self.id, :status => UserPact::CURRENT)
  end

  def current_pact
    UserPact.find_by_user_id_and_status(self.id, UserPact::CURRENT).pact rescue nil
  end

  def pending_pact_inviter?
    PactInvite.exists?(:inviter_id => self.id, :status => PactInvite::PENDING)
  end

  def pending_sent_pact_invite
    PactInvite.find_by_inviter_id_and_status(self.id, PactInvite::PENDING)
  end

  def pending_pact_invitee?
    PactInvite.exists?(:invitee_id => self.id, :status => PactInvite::PENDING)
  end

  def pending_received_pact_invites
    PactInvite.where(:invitee_id => self.id, :status => PactInvite::PENDING)
  end

  def pact_invite_count
    self.pending_received_pact_invites.count
  end

  def can_invite_to_pact?(other_user)
    (
      friends_with?(other_user) &&
      !current_pact? &&
      !other_user.current_pact? &&
      !pending_pact_inviter? &&
      !other_user.away?
    )
  end

  ###################################################################
  # SMS Methods

  def pending_sms_verification
    SmsVerification.find_pending(self)
  end

  def is_sms_user?
    self.subscriptions.exists?(:channel_type => ChannelTypes::SMS) && self.mobile_number
  end

  def unsubscribe_from_sms!
    self.subscriptions.where(:channel_type => ChannelTypes::SMS).each do |s|
      s.destroy
    end
    self.mobile_number = nil
    self.save!
  end

  def verified_sms!(pending_verification)
    transaction do
      # update the verification status
      pending_verification.status = SmsVerification::VERIFIED
      pending_verification.verified_at = Time.now
      pending_verification.save!

      # is another user already using this mobile number?
      # if so, we steal it.
      if old_user = self.class.find_by_mobile_number(pending_verification.mobile_number)
        old_user.update_attribute(:mobile_number, nil)
        Subscription.where(:user_id => old_user.id, :message_type => MessageTypes::CHALLENGE, :channel_type => ChannelTypes::SMS).destroy_all
        Subscription.where(:user_id => old_user.id, :message_type => MessageTypes::CHALLENGE_REMINDER, :channel_type => ChannelTypes::SMS).destroy_all
      end

      # update the current user record
      self.mobile_number = pending_verification.mobile_number
      self.save!
    end
  end

  def setup_sms_defaults!
    transaction do
      # delete any existing SMS subscriptions
      Subscription.where(:user_id => self.id, :message_type => MessageTypes::CHALLENGE, :channel_type => ChannelTypes::SMS).destroy_all
      Subscription.where(:user_id => self.id, :message_type => MessageTypes::CHALLENGE_REMINDER, :channel_type => ChannelTypes::SMS).destroy_all

      # insert the default subscriptions
      challenge_sub =  Subscription.create!(:user => self,
                                            :message_type => MessageTypes::CHALLENGE, :channel_type => ChannelTypes::SMS,
                                            :delivery_time => 9.hour.to_i)

      reminder_sub = Subscription.create!(:user => self,
                                          :message_type => MessageTypes::CHALLENGE_REMINDER, :channel_type => ChannelTypes::SMS,
                                          :delivery_time => 17.hour.to_i)
      self.subscriptions << challenge_sub
      self.subscriptions << reminder_sub
    end
  end

  def age_verified!(type, verification_data)
    AgeVerification.create!(:user => self, :verification_type => type, :verification => verification_data, :verified_at => Time.now)
  end

  def default_profile_picture_path
    User.default_profile_paths[self.id % 10]
  end

  def randomize_picture!(event_source = UserEvent::Source::WEB)
    new_picture = User.default_profile_picture(rand(1..NUM_DEFAULT_PROFILE_PICTURES))
    update_picture!(new_picture, event_source)
  end

  def update_picture!(picture, event_source = UserEvent::Source::WEB)
    self.register_sourced_event(UserEvent::SELECT_PROFILE_PICTURE, event_source)

    self.picture = picture
    self.picture_updated_at = Time.now
    self.save!(validate: false)

    UserProfileTracker.new(self).track_changes!

    self.picture.versions.each do |size, pic|
      Rails.cache.write("user/photo_url/#{self.key}/#{size}", pic.url)
    end
  end

  def away?
    self.challenge_profile.try(:away?) || false
  end

  def active_away_record
    self.time_aways.active.first
  end

  def can_take_time_away?
    true
  end

  def away_will_break_pact?
    self.current_pact != nil &&
    (!self.current_pact.is_on_last_pact_day(self) ||
      (self.current_pact.is_on_last_pact_day(self) && self.latest_challenge_assignment.status != ChallengeAssignment::COMPLETE)
    )
  end

  def away!
    if away_will_break_pact?
      if current_pact = self.current_pact
        current_pact.failed!(true)
      end
    end
  end

  def challenge_hows_count
    self.challenge_hows.count
  end

  def challenge_how_replies_count
    self.challenge_how_replies.count
  end

  def reply_count_for_challenge_date
    PointEvent.reply_count_for_challenge_date(self)
  end

  def like_count_for_challenge_date
    PointEvent.like_count_for_challenge_date(self)
  end


  ###################################################################
  # Public Class Methods

  class << self
    # TODO: this is only used in test mode, and should be removed
    def well_being_guides
      where(email: Rails.application.secrets.well_being_guide_emails)
    end

    def find_challenge_users_with_facebook_ids(fb_ids)
      return [] if fb_ids.blank?
      self.where(:facebook_uid => fb_ids).to_a
    end

    def challenge_system_participants_starting_before(date)
      self.joins(:challenge_profile).where(%Q~
            #{ChallengeProfile.table_name}.status != #{ChallengeProfile::DELETED}
          AND
            #{ChallengeProfile.table_name}.start_date <= '#{date}'
          AND
            #{table_name}.status != #{DELETED}
          AND
            #{ChallengeProfile.table_name}.point_total > 0
        ~
      )
    end

    def users_with_friends
      User.joins(:friends).group(:user_id)
    end

    def find_by_facebook_uid_and_update_facebook_session_key_if_different(facebook_uid, facebook_session_key)
      # Look up the user by facebook id
      user = User.find_by_facebook_uid(facebook_uid)
      if user
        if user.facebook_session_key == facebook_session_key
          # What we currently have matches what we were passed - we're good
          return user
        else
          # session keys don't match.  Try to verify the new one by making an API call
          user.facebook_session_key = facebook_session_key

          client = FacebookClient.new(facebook_session_key)

          if client.request(:get, "me").status == 200
            # Lookup successful, so save this as the new session_key
            user.save!
            return user
          else
            # Access token could not be validated
            return nil
          end
        end
      else
        # We don't have any user with this Facebook ID
        return nil
      end
    end

    def default_profile_paths
      1.upto(User::NUM_DEFAULT_PROFILE_PICTURES).collect do |num|
        sprintf("challenge/default_profile/%02d.jpg", num)
      end
    end

    def default_profile_picture(number)
      unless number.between?(1, NUM_DEFAULT_PROFILE_PICTURES)
        number = rand(NUM_DEFAULT_PROFILE_PICTURES) + 1
      end

      path = sprintf("%s/app/assets/images/challenge/default_profile/%02d.jpg", ::Rails.root.to_s, number)
      File.new(path)
    end
  end

  def register_event(event_type, related_object = nil, entered_at = Time.now)
    UserEvent.create(:user => self, :event_type => event_type, :related_object => related_object, :entered_at => entered_at)
  end

  def register_sourced_event(event_type, source)
    user_events.create(event_type: event_type, source: source)
  end

  def register_external_event(event_type, external_object_type = nil, external_object_id = nil, related_object_type = nil, related_object_id = nil, entered_at = Time.now)
    UserEvent.create(:user => self, :event_type => event_type, :external_object_type => external_object_type, :external_object_id => external_object_id,  :entered_at => entered_at, :related_object_id => related_object_id, :related_object_type => related_object_type)
  end

  def friends_with_data(challenge_date = self.current_challenge_date, limit = nil, order = "first_name, last_name")
    friends_with_data_and_self(challenge_date, limit + 1, order) - [self]
  end

  def friends_with_data_and_self(challenge_date = self.current_challenge_date, limit = nil, order = "first_name, last_name")
    sql = %Q~
      SELECT u.*,
             ca.id                            AS challenge_assignment_id,
             ca.challenge_id                  AS challenge_id,
             ca.status                        AS challenge_status,
             ca.responded_time                AS responded_time,
             (ca.status = 0 AND e.id IS NULL) AS encourageable,
             (ca.status = 1)                  AS order_complete,
             (ca.status = 3)                  AS order_pass,
             (p.status = 4)                   AS away,
             (u.id = #{self.id})              AS is_me
      FROM (
        (SELECT other_user_id FROM friend_connections WHERE user_id = #{self.id})
           UNION
        (SELECT #{self.id} AS other_user_id)
      ) AS f
      JOIN users AS u ON u.id = f.other_user_id
      JOIN challenge_profiles AS p ON u.id=p.user_id
      LEFT JOIN challenge_assignments AS ca ON ca.user_id = u.id AND ca.challenge_date = '#{challenge_date.to_s(:db)}'
      LEFT JOIN encouragements AS e ON e.user_sending_id = #{id} AND e.challenge_assignment_id = ca.id
      ORDER BY away, order_complete DESC, order_pass DESC, responded_time, is_me DESC, #{order}
    ~
    sql += " LIMIT #{limit}" if limit
    users = User.find_by_sql(sql)
    self.class.preload_associations(users, [:challenge_profile])
    users
  end

  def latest_friend_notifications
    items = StreamItem.where(:id => StreamItemNotification.for(self).latest_stream_item_ids)
    items_with_relobj = items.reject {|x| x.item_type == StreamItem::STREAK_EARNED}
    StreamItem.preload_associations(items_with_relobj, [:user, :related_object])
    items
  end

  def friends_eligible_for_featured_encouragement(challenge_date)
    # Not eligible if either:
    #  You don't have any friends
    #  You have seen this card in the past 4 days.
    if self.friends.count < 1 || self.daily_flow_card_impressions.where(:card_class => 'FeaturedEncouragement').where("seen_time > '#{Date.today - 4.days}'").count > 0
      return []
    end

    sql = %Q~
      SELECT u.*
      FROM #{User.table_name} u
        JOIN #{ChallengeProfile.table_name} cp ON cp.user_id = u.id AND cp.status = #{ChallengeProfile::ACTIVE}

      /* Derived table to check for previous prompts to encourage a particular friend */
      LEFT JOIN (
        SELECT *
        FROM #{DailyFlowCardImpression.table_name} c
        WHERE related_object_type = 'User'
          AND user_id = #{self.id}
          AND card_class = 'FeaturedEncouragement'
          AND seen_time > '#{Date.today - 10.days}'
      ) AS recent_featured_encouragements ON recent_featured_encouragements.related_object_id = u.id

      /* Limit to this user's friends */
      JOIN #{FriendConnection.table_name} fc on fc.user_id=u.id and fc.other_user_id=#{self.id}

        /* Limit to friends who aren't brand new */
        AND cp.start_date < '#{Date.today - 4.days}'

        /* Limit to friends who haven't completed challenges in a while */
        AND (cp.last_challenge_done_time IS NULL OR cp.last_challenge_done_time < '#{Date.today - 4.days}')

        /* Limit friends who have already been prompts to encourage in the past week */
        AND recent_featured_encouragements.id IS NULL
    ~
    users = self.class.find_by_sql(sql)
    return users.reject{|f| !self.can_encourage?(f, challenge_date)}
  end

  def pronoun
    case self.gender
      when Gender::MALE
        'he'
      when Gender::FEMALE
        'she'
      else
        'they'
    end
  end

  def possessive_pronoun
    case self.gender
    when Gender::MALE
      'his'
    when Gender::FEMALE
      'her'
    else
      'their'
    end
  end

  def objective_pronoun
    case self.gender
      when Gender::MALE
        'him'
      when Gender::FEMALE
        'her'
      else
        'them'
    end
  end

  ###################################################################
  # WBT Stuff

  def current_wbt_score
    self.assessment_score.well_being_score rescue nil
  end

  # Returns an array of arrays of dates and scores, e.g.,
  # [['2011-03-01', 65], ['2011-03-02', 67], ...]
  def wbt_scores_by_day(options = {})
    options.reverse_merge!({:count => 7})

    today = Time.now.utc.to_date
    start_date = today - options[:count].days
    end_date = today

    start_date_string = start_date.to_s(:db)

    scores = WbiDomainScore.find_by_sql(%Q~
      SELECT s1.*
      FROM #{WbiDomainScore.table_name} AS s1
      JOIN (
        SELECT scored_on, MAX(id) AS id
        FROM #{WbiDomainScore.table_name} AS s2
        WHERE s2.user_id = #{self.id}
        AND scored_on >= '#{start_date_string}'
        GROUP BY scored_on
      ) AS s3 ON s1.scored_on = s3.scored_on AND s1.id = s3.id
      WHERE user_id = #{self.id}
      AND s1.scored_on >= '#{start_date_string}'
      GROUP BY s1.scored_on
      ORDER BY s1.scored_on
    ~)
    previous_score = self.wbi_domain_scores.where("scored_on < '#{start_date}'").order(:scored_time).last.wbt_score rescue nil

    output = []
    start_date.upto(end_date) do |date|
      score = scores.select {|f| f.scored_on == date}.first
      if score
        output.push([score.scored_on.to_s, score.wbt_score.to_i])
      elsif date == start_date
        output.push([date.to_s, previous_score ? previous_score.to_i : nil])
      else
        output.push([date.to_s, output.last.last])
      end
    end
    output
  end

  def wbt_questions_answered
    AssessmentResponse.by_user_and_question_keys(self, Assessment.question_keys).group(:question_key).to_a.count
  end

  def wbt_resampled?
    WbtQuestionImpression.where(:user_id => self.id, :source => WbtQuestionImpression::RESAMPLE).exists?
  end


  def wbt_resample_keys
    ps = {
      :user_id => self.id,
      :challenge_id => self.current_challenge.id
    }

    # If the user hasn't completed the WBT or has dismissed a question on the current challenge day, we're all done.
    score = AssessmentScore.find_by_user_id(self.id)
    if score.nil? || score.well_being_score.nil? || WbtQuestionImpression.where(ps).where(:status => WbtQuestionImpression::DISMISSED).exists?
      return []
    end

    responded = WbtQuestionImpression.where(ps).where(:status => [WbtQuestionImpression::RESPONDED, WbtQuestionImpression::SKIPPED]).group(:question_key)
    not_responded = WbtQuestionImpression.where(ps).where(:status => WbtQuestionImpression::SEEN).group(:question_key)

    resp_keys = responded.map(&:question_key)
    nresp_keys = not_responded.map(&:question_key)

    ask = nresp_keys - resp_keys
    exclude = ask + resp_keys

    num_to_generate = WbtQuestionImpression::IMPRESSIONS_PER_DAY - exclude.length
    keys = ask + (WbtQuestionSelector.select_questions(ASSESSMENT, self, num_to_generate, exclude).map {|q| q.question_key})

    return keys
  end

  def average_domain_scores_for_self_and_friends
    avg_cols  = ['AVG(well_being_score) AS well_being_score_avg']
    card_cols = ['SUM(well_being_score IS NOT NULL) AS well_being_score_cardinality']

    ASSESSMENT.domains.each do |d|
      attr = d.score_attribute
      avg_cols  << "AVG(#{attr}) AS #{attr}_avg"
      card_cols << "SUM(#{attr} IS NOT NULL) AS #{attr}_cardinality"
    end

    select_clause = (avg_cols + card_cols).join(', ')
    user_ids = self.friends.map(&:id)
    user_ids << self.id

    sql = %Q~
      SELECT #{select_clause} FROM assessment_scores
      WHERE user_id IN (#{user_ids.join(', ')})
    ~

    self.class.connection.select_one(sql)
  end

  # returns an array, e.g., [["2011-05-02, {:cardinality => 3, :average => 67.37}"], ...]
  def average_wbt_score_for_friends_by_day(options = {})
    options.reverse_merge!({:count => 7})

    today = Time.now.utc.to_date
    start_date = today - options[:count].days
    end_date = today

    users = [self] + self.friends.all

    # First, collect the cache keys and hit the cache:
    keys = []
    key_map = {}
    start_date.upto(end_date) do |d|
      key_map[d] = {}
      users.each do |u|
        k = WbiDomainScore.wbt_score_cache_key(u.id, d)
        keys << k
        key_map[d][u] = k
      end
    end

    cache_results = Rails.cache.read_multi(*keys)

    # Next, assemble the results, re-querying where necessary
    by_day = {}
    key_map.each do |d, umap|
      scores       = []
      query_users  = []

      umap.each do |u, key|
        r = cache_results[key]

        if r.nil?
          query_users << u
        elsif r >= 0
          scores << r
        end
      end

      scores.concat(WbiDomainScore.wbt_scores_for_users_on_date(query_users, d)) unless query_users.empty?
      by_day[d] = {:cardinality => scores.length, :average => (scores.length.zero? ? 0.0 : scores.sum / scores.length.to_f)}
    end

    by_day.to_a.sort_by(&:first).map {|x| [x.first.to_s(:db), x.second]}
  end

  ###################################################################
  # Registration hooks
  def populate(auth_data)
    provider   = auth_data.provider
    uid        = auth_data.uid

    attrs = [:first_name, :last_name, :email, :password_confirmation, :gender, :zip, :country, :time_zone_id, :date_of_birth,
             :facebook_uid, :archive_facebook_uid, :facebook_session_key, :terms]

    attrs.each {|key| self.send("#{key}=", self.send(key) || auth_data[key])}

    # special case password, for authlogic
    self.password = auth_data.password if auth_data.password

    # special case FB access token expiration, since it's a split timestamp
    if auth_data.facebook_session_key_expires_at
      self.facebook_session_key_expires_at = auth_data.facebook_session_key_expires_at
    end

    if provider && uid
      self.authentications << (Authentication.find_by_provider_and_uid(provider, uid) ||
                               Authentication.new(:provider => provider, :uid => uid, :email => self.email))
    end
  end

  def explicitly_accept_current_terms!
    TermsPrivacyConsent.explicit_accept!(self)
  end

  def implicitly_accept_current_terms!
    TermsPrivacyConsent.implicit_accept!(self)
  end

  ###################################################################
  # User blocking
  def block!(user)
    transaction do
      self.lock!
      UserBlock.create!(:blocker => self, :blockee => user) unless blocking?(user)
    end
  end

  def unblock!(user)
    transaction do
      self.lock!
      self.blockee_user_blocks.where(:blockee_id => user.id).each do |user_block|
        user_block.delete!
      end
    end
  end

  def blocking?(user)
    blockees.include?(user)
  end

  def blocked_by?(user)
    blockers.include?(user)
  end

  def blocking_or_blocked_by?(user)
    blocking?(user) || blocked_by?(user)
  end

  def show_block_option_for?(user)
    return user != self
  end

  def blocked_user_keys
    @blocked_user_keys ||= hidden_users.index_by(&:key)
  end

  def is_skylight_user?
    self.authentications.for_provider('skylight').any?
  end

  def is_wbid_user?
    self.authentications.for_provider('wbid').any?
  end

  ###################################################################
  # Content reporting
  def reported_reply_map(challenge_hows, stream_items)
    how_items, non_how_items = stream_items.partition {|item| item.related_object_type == ChallengeHow.to_s}

    how_ids     = challenge_hows.map(&:id) + how_items.map(&:related_object_id)
    reply_ids   = ChallengeHowReply.where(challenge_how_id: how_ids).pluck(:id)
    comment_ids = Comment.where(related_object_type: StreamItem.to_s, related_object_id: non_how_items.map(&:id))

    reply_reports   = content_reports.where(:content_type => ChallengeHowReply.to_s, :content_id => reply_ids)
    comment_reports = content_reports.where(:content_type => Comment.to_s,           :content_id => comment_ids)

    result = {}
    (reply_reports + comment_reports).each do |report|
      key = "#{report.content_type}-#{report.content_id}"
      result[key] = true
    end

    result
  end

  ###################################################################
  # Feature Groups
  def has_feature_access?(feature)
    feature_group_for(feature).present?
  end

  def feature_group_for(feature)
    FeatureGroup.feature_group_for_user(feature, self)
  end

  # Validate the given password and password confirmation.
  def validate_passwords(password, password_confirmation)
    if password.blank? || password.length < 5
      errors.add(:password, "must be at least 5 characters")
    elsif password != password_confirmation
      errors.add(:password_confirmation, "does not match password")
    elsif Validation::BAD_PASSWORDS.include?(password)
      errors.add(:password, "should be harder to guess")
    end
  end

  def valid_for_email_signup?
    valid?
    send(:validate_date_of_birth, 'must be at least 13 years old to join Daily Challenge')
    validate_passwords(password, password_confirmation)
    send(:validate_local_name)
    errors.empty?
  end

  ###################################################################
  # Private Instance Methods
  private

  def sponsored_user
    @sponsored_user ||= SponsoredUser.new(self)
  end

  def challenge_video_participant
    @challenge_video_participant ||= ChallengeVideoParticipant.new(self)
  end

  def set_default_values
    self.key                             ||= rand(18446744073709551615).to_s(36).rjust(13,'0')
    self.archive_facebook_uid            ||= self.facebook_uid
    self.facebook_session_key_expires_at ||= Time.now unless facebook_session_key.blank?
    self.archive_email                   ||= self.email

    self.picture_updated_at = Time.now if (new_record? && picture_updated_at.blank?)
  end

  def capitalize_names
    self.first_name = first_name.sub(/^(\w)/) {|s| s.capitalize}
    self.last_name = last_name.sub(/^(\w)/) {|s| s.capitalize}
  end

  # This runs after validation, so we should have a valid zip or none
  def set_timezone
    return if time_zone

    self.time_zone = if zip.present?
      code = ZipCode.find_by_zip_code(zip)
      (code && code.time_zone) ? code.time_zone : TimeZone.find_by_name('US/Eastern')
    elsif country.present?
      # Pick the first one available by country.
      TimeZone.by_country(country).first
    else # Now that TZs are set from browser or WBID, this should never happen
      TimeZone.default
    end
  end

  # Defaults the country if no country is assigned and the zip code is provided.
  def set_country
    if self.zip.present? && self.country.blank?
      self.country = "United States"
    end
  end

  def set_full_name
    self.full_name = "#{first_name} #{last_name}"
  end

  # We want to maintain the value of the archive email address automatically as the email address changes
  # unless we have disabled or banned the account.
  def set_archive_email
    self.archive_email = email if self.active?
  end

  def ensure_consistent_country_name
    self.country = "United States" if self.country == "United States of America"
  end

  def validate_local_name
    return unless first_name && last_name

    self.first_name = first_name.strip
    self.last_name  = last_name.strip

    # Capitalize first letter of first name
    self.first_name = (first_name[0, 1].upcase + first_name[1, first_name.length]) unless self.first_name.blank?
    # Ensure last name is at least 2 characters in length
    errors.add(:last_name, "must be at least 2 characters") if last_name.length < 2
  end

  def validate_local_password
    return if password.blank? && password_confirmation.blank? && !crypted_password.blank? # TODO: this may need some different kind of logic for existing users changing passwords, etc.
    self.validate_passwords(self.password, self.password_confirmation)
  end

  def valid_zip_code
    if zip.present?
      errors.add(:zip, "does not exist") unless ZipCode.exists?(zip_code: zip)
    end
  end

  def validate_date_of_birth(message = "Sorry! You must be at least 13 years old to join Daily Challenge.")
    errors.add(:date_of_birth, "is invalid") if date_of_birth.blank?

    unless date_of_birth.blank?
      cutoff = Date.current - 13.years
      errors.add(:date_of_birth, message) if date_of_birth > cutoff
    end
  end

  def valid_gender
    if gender.blank?
      errors.add(:gender, "can't be blank")
    elsif !([Gender::FEMALE, Gender::MALE, Gender::UNKNOWN].include?(gender))
      errors.add(:gender, "is invalid")
    end
  end

  def remove_stamp_messages
    ChallengeStampMessage.for(self).flush!
  end

  def initialize_connection_cache
    CachedUserConnection.create(self.id)
  end

  def enroll_in_streamlined_privacy
    feature_groups.create(feature: FeatureGroup::STREAMLINED_PRIVACY)
  end

  def enroll_in_one_small_action_ab_test
    experiment = AbTest::Experiment.one_small_action
    experiment.create_participant_record(self) if experiment.active?
  end
end
