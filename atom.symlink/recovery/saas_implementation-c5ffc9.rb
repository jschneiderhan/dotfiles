class SaasImplementation < ApplicationRecord
  WELCOME_EMAIL_DELAY = 24.hours

  has_paper_trail class_name: "PaperTrail::SaasImplementationVersion"

  scope :finished_onboarding_state, -> (step) {
    joins(:onboarding_state).
    joins(%~
      LEFT JOIN saas_implementation_onboarding_events ON
        saas_implementation_onboarding_events.onboarding_state_id = saas_implementation_onboarding_states.id AND
        saas_implementation_onboarding_events.step = #{ActiveRecord::Base.connection.quote(step)}
    ~.squish)
  }

  enum status: [:pending, :active]
  # These enum values need to line up with `Contract.eligibility_types`
  enum eligibility_type: { google_directory: 9, adp: 10, email: 11 }

  belongs_to :user, dependent: :destroy
  belongs_to :billing_plan, class_name: "Billing::Plan"
  belongs_to :customer, dependent: :destroy, optional: true
  belongs_to :contract, dependent: :destroy, optional: true

  has_one :organization, through: :contract, source: :organizations
  has_one :segment, through: :contract, source: :segments
  has_one :onboarding_state, class_name: "SaasImplementationOnboardingState", autosave: true, dependent: :destroy

  has_many :vanity_urls, through: :contract
  has_many :billing_subscriptions, class_name: "Billing::Subscription", dependent: :destroy
  has_many :billing_services_agreements, class_name: "Billing::ServicesAgreement", dependent: :destroy
  has_many :periods, class_name: "Billing::Period", through: :billing_subscriptions

  validates :company_name, presence: true
  validates :code, presence: true, configuration_code: { allow_blank: true, max_length: 30 }, uniqueness: { allow_blank: true }
  validates :time_zone, presence: true, inclusion: { in: TimeZone.all_supported_names, allow_blank: true }
  validates :status, presence: true
  validates :logo, presence: true
  validates :eligibility_type, inclusion: { in: eligibility_types.keys, allow_blank: true }
  validate :code_not_in_use_by_existing_configurations

  with_options if: :pending? do
    validates :customer, absence: true
    validates :contract, absence: true
    validates :starts_at, absence: true
  end

  with_options if: :active? do
    validates :customer, presence: true
    validates :contract, presence: true
    validates :eligibility_type, presence: true
    validates :starts_at, presence: true
  end

  dragonfly_accessor :logo

  after_initialize :build_onboarding_state, if: :new_record?
  before_validation :finalize_initial_configuration, on: :create
  after_update :activate!, :check_if_card_needs_updating

  delegate :eligible_user_count, to: :contract, allow_nil: true
  delegate :card_details, :trial_ends_at, :cycle_day, to: :current_billing_subscription, allow_nil: true
  delegate :latest_step_completed, :latest_step_completed=, :next_step, to: :onboarding_state, prefix: :onboarding

  attr_accessor :wbid_user_key, :card_token

  def active_support_time_zone
    @active_support_time_zone ||= TimeZone.active_support_time_zone_for(time_zone)
  end

  def current_billing_subscription
    @current_billing_subscription ||= billing_subscriptions.where(status: [:pending, :active]).first
  end

  def users
    @users ||= User.active.joins(:resource_permissions).where(resource_permissions: { resource: organization })
  end

  def user_eligibility_key
    return unless active?

    case eligibility_type
    when "adp"
      contract.adp_purchases.consented.find_by(user: user)&.adp_practitioner_id
    when "google_directory"
      contract.google_directory_authorizations.active.find_by(user: user)&.subscriber_id
    when "email"
      contract.email_eligibilities.find_by(email: user.email)&.email
    else
      raise NotImplementedError
    end
  end

  def activate!
    case status
    when "pending"
      return false unless eligibility_type?

      build_hierarchy
      active!
      user.resource_permissions.create!(resource: contract)
      segment.create_segment_update_notification!
    when "active"
      if (saved_changes.keys & %w(company_name logo_uid)).any?
        customer.update!(name: company_name, logo: logo)
        contract.update!(name: company_name, logo: logo, header_logo: logo)
        organization.update!(name: company_name)
        segment.update!(name: company_name, description: company_name)
        segment.create_segment_update_notification!
      end
    else
      raise NotImplementedError
    end
  end

  def updateable_attributes
    attrs = [:company_name, :logo_url, :onboarding_latest_step_completed, :card_token]

    if pending?
      attrs << :code

      unless eligibility_type?
        attrs << :eligibility_type
      end
    end

    attrs
  end

  def onboarded?
    onboarding_next_step.blank?
  end

  private

  def code_in_use?(code, check_internally: true)
    # Force the use of savepoints with `requires_new`.
    #
    # Note that releasing a savepoint should not release any locks
    # acquired within the transaction prior to the savepoint being
    # released. That means any locks we acquire as part of this
    # transaction will persist for the duration of the outermost
    # transaction, which is the desired functionality for this method.
    ActiveRecord::Base.transaction(requires_new: true) do
      # This lock is done independent of `check_internally`, so that
      # all threads going through this code path are forced to wait
      # on this lock.
      #
      # If there are no SaasImplementation records with `code: code`,
      # then there are no rows to lock on. If 2 SaasImplementations
      # have the same code and both attempt to save to the database,
      # then the internal uniqueness constraint on the table will
      # stop one of them. After that point, this lock will be based
      # on at least 1 row, forcing all application threads to first
      # acquire the lock.
      internal_query = SaasImplementation.where(code: code)

      # Forcibly acquire the lock with a database call, since otherwise
      # lazy SQL execution may mean it never happens.
      ActiveRecord::Base.connection.execute(internal_query.lock.to_sql)

      queries = [
        [Segment.where(code: code), :contract],
        [Contract.where(url_code: code), nil],
        [VanityUrl.where(code: code), :contracts]
      ]

      potentially_existing_codes = queries.map do |query, contract_relation|
        query.lock

        if self.contract
          # ignore conflicts if this SaasImplementation is tied to the conflicting records

          if contract_relation
            query = query.joins(contract_relation)
          end

          query = query.where.not(contracts: { id: self.contract.id })
        end

        query
      end

      if check_internally
        potentially_existing_codes << internal_query.where.not(id: self.id)
      end

      potentially_existing_codes.any?(&:exists?)
    end
  end

  def unique_code_for(original_code)
    generated_code = original_code
    attempts = 1
    max_attempts = 3

    while attempts <= max_attempts && found = code_in_use?(generated_code)
      generated_code = "#{original_code}-#{rand(100)}"
      attempts += 1
    end

    if found
      # pick something very unlikely to be taken
      generated_code = "#{Time.now.strftime("%Y-%m-%d")}-#{SecureRandom.hex(8)}"

      NewRelic::Agent.notice_error("Failed to generate an available SaasImplementation code after #{max_attempts} attempts", error_details: "Company name #{self.company_name.inspect} failed to generate a code with #{original_code} or any suffix. Falling back to #{generated_code}")
    end

    generated_code
  end

  def code_not_in_use_by_existing_configurations
    # don't check this own table, since the internal uniqueness constraint will do that
    errors.add(:code, :taken) if code_in_use?(code, check_internally: false)
  end

  def finalize_initial_configuration
    self.code = unique_code_for(self.company_name.parameterize)
    self.logo = Dragonfly.app.generate(:default_saas_logo, self.company_name)
    self.build_user(wbid_user_key: wbid_user_key, role: :saas).tap(&:assign_attributes_from_wbid)
    self.billing_subscriptions.build(status: :pending, user: user, plan: billing_plan, external_id: card_token)
    self.billing_services_agreements.build(user: user)
  end

  def check_if_card_needs_updating
    return if card_token.blank? || current_billing_subscription.blank?

    current_billing_subscription.update_card!(card_token)
  end

  def build_hierarchy
    self.starts_at = Time.now

    self.customer = Customer.new(
      name: company_name,
      logo: logo,
    )

    self.contract = customer.contracts.build(
      name: company_name,
      url_code: code,
      header_logo: logo,
      logo: logo,
      uat_starts_at: starts_at,
      uat_ends_at: "infinity",
      production_starts_at: starts_at,
      production_ends_at: "infinity",
      time_zone: time_zone,
      eligibility_type: eligibility_type,
      product_ids: ["wellbeingtracker", "dailychallenge", "walkadoo", "quitnet"],
      default_product_id: "wellbeingtracker",

      product_configurations: {
        wellbeingtracker: {
          landing_page_sections: ["wbt", "daily_challenge", "walkadoo", "quitnet"]
        },
        quitnet: {
          offers_digital_coaching: false,
          offers_hways_nrt: false,
          offers_phone_coaching: false,
          coaching_phone_number: nil,
          wbo_phone_prompt: false,
          third_party_nrt_email: false,
          enrollment_period_duration: 12,
        }
      }
    )

    organization = contract.organizations.build(name: company_name)

    segment = organization.segments.build(
      name: company_name,
      description: company_name,
      code: code,
      prototype: code,
      uat_starts_at: starts_at,
      uat_ends_at: "infinity",
      production_starts_at: starts_at,
      production_ends_at: "infinity",
      auto_enroll_product_ids: ["dailychallenge"],
      product_configurations: {
        wellbeingid: { requires_consent: true },
        dailychallenge: { show_label: true }
      }
    )

    segment.build_assessment(
      requires_assessment: false,
      personalized_feedback: true,
      provides_score: false,
      assessment_version: "openhra-full"
    )

    dailychallenge_program = segment.programs.build(
      product_id: "dailychallenge",
      title: "Daily Challenge",
      label: "Everyday Well-Being",
      introduction: "Daily Challenge is a well-being experience that combines small daily actions and the power of making health changes with others. You receive a simple challenge each morning via email or SMS. Do the challenge, share how you did it, and give and get support from the robust Daily Challenge community.",
      heading: "Here's what it's all about:",
      description: "Daily Challenge is for anyone who wants to improve their well-being, one small step at a time! Explore a variety of simple challenges in topics like nutrition and exercise to stress management and work-life balance. Join the community of Daily Challenge members who support one another, and see how friends can help improve your well-being and make health change fun. Earn points, collect stamps, and reach new levels in the program!<br />Take just a few minutes a day, and you'll see how small actions can add up to big change.",
      logo: Rails.root.join("db", "seeds", "assets", "programs", "logo", "daily-challenge.png").open,
      rank: -40
    )

    dailychallenge_program.screenshots.build(
      image: Rails.root.join("db", "seeds", "assets", "program_screenshots", "image", "daily-challenge.jpg").open
    )

    walkadoo_program = segment.programs.build(
      product_id: "walkadoo",
      title: "Walkadoo",
      label: "Physical Activity",
      introduction: "Walkadoo is a pedometer-based program that makes walking fun! Each day, you get a step goal that's been created just for you, based on your walking habits. Take your steps, join the Walkadoo community, and get support from other members as you walk your way to better health!",
      heading: "Here's what it's all about:",
      description: "Walkadoo is for anyone who wants to be more active – and have fun as they do it! With custom step goals delivered daily, it's a whole new way to get more walking into your day. Use the website or the free app for iOS or Android to connect with the Walkadoo community, get support from other members, and reach new levels all along your Walkadoo journey.<br /><br />Take the first step, see how much fun walking can be!",
      logo: Rails.root.join("db", "seeds", "assets", "programs", "logo", "walkadoo.png").open,
      rank: -30
    )

    walkadoo_program.screenshots.build(
      image: Rails.root.join("db", "seeds", "assets", "program_screenshots", "image", "walkadoo.jpg").open
    )

    quitnet_program = segment.programs.build(
      product_id: "quitnet",
      title: "QuitNet",
      label: "Tobacco Cessation",
      introduction: "QuitNet is the longest-running quit-smoking program in the world – here since 1995 and still going strong! Connect and share with the QuitNet community, take the daily pledge to stay quit, and ask an expert your toughest questions. Use it at home – or take QuitNet with you on our mobile app.",
      heading: "Here's what it's all about:",
      description: "QuitNet is for current smokers who want to quit and ex-smokers who want to stay that way! Use it at home or on the go – the app makes it easy to connect and share with the QuitNet community, no matter where you are. Take the pledge and join the chain of others committed to staying quit each day. Reach out and get help from the community during a craving. Connect with thousands of supportive members.<br /><br />Quitting smoking is a journey. Don't take it alone! Join the QuitNet community and take the first step toward your smoke-free life.",
      logo: Rails.root.join("db", "seeds", "assets", "programs", "logo", "quitnet.png").open,
      rank: -20
    )

    quitnet_program.screenshots.build(
      image: Rails.root.join("db", "seeds", "assets", "program_screenshots", "image", "quitnet.jpg").open
    )
  end
end
