RSpec.describe 'Saas Implementations API' do
  before { Timecop.freeze(Time.zone.parse("2018-01-01 00:00:00 PST")) }

  describe '#create' do
    let!(:billing_plan) { FactoryBot.create(:billing_plan) }

    before do
      issued_at = Time.now
      expires_at = issued_at + 1.month
      token = JWT.encode({
        sub: "some-user-key",
        iat: issued_at.to_i,
        uid: "a-session-id",
        jti: Digest::MD5.hexdigest([issued_at.to_i, SecureRandom.hex(32)].join(':')),
        iss: 'Well-Being ID',
        exp: expires_at.to_i
      }, Rails.application.secrets.sso_key)

      cookies[:wbid_sso_session] = token

      WebMock.stub_request(:get, 'http://account.myhdev.com:3400/api/client/sessions/a-session-id/valid').to_return(status: 200)
      WebMock.stub_request(:get, 'http://account.myhdev.com:3400/api/client/users/some-user-key').
        with(headers: { 'X-Api-Version' => '1', 'X-Myh-Client-Id' => '20d6a6139d615c6ec7bd705869c08909af7a9e64c6f957340beceefc5a4e19bd' }).
        to_return(status: 200, body: { user: { wbid_user_key: 'some-user-key', email: 'john@example.com', first_name: 'John', last_name: 'Smith' } }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      post api_saas_implementations_path, as: :json, headers: { 'CONTENT_TYPE' => 'application/vnd.api+json', 'HTTP_ACCEPT' => 'application/vnd.api+json' }, params: { data: { type: "saas_implementations", attributes: { company_name: "ACME Corp.", time_zone: "America/Los_Angeles", card_token: "stripe-token-value" }, relationships: { billing_plan: { data: { type: "billing_plans", id: billing_plan.id.to_s } } } } }
    end

    it { should have_json_api_response(201).
      with_resource('saas_implementations',
        'status' => 'pending',
        'company_name' => 'ACME Corp.',
        'code' => 'acme-corp',
        'logo' => /\Ahttp:\/\/snap\.myhdev\.com:3700\/media\/[a-z0-9]+\?sha=[a-z0-9]+\z/i,
        'eligibility_type' => nil,
        'card_details' => {
         'brand' => 'Visa',
         'last4' => '4242',
         'exp_month' => 4,
         'exp_year' => 2024
        },
        'trial_ends_at' => '2018-01-31T20:00:00.000Z',
        'cycle_day' => 31,
        'onboarding_latest_step_completed' => nil,
        'onboarding_next_step' => 'welcome',
        'onboarded' => false
      ).
      with_related('billing_plan').
      with_related('contract')
    }

    it "creates the appropriate objects in Stripe" do
      expect(a_request(:post, "https://api.stripe.com/v1/customers").with(body: { description: "ACME Corp.", email: "john@example.com", metadata: { wbid_user_key: "some-user-key" }, source: "stripe-token-value" })).to have_been_made
      expect(a_request(:post, "https://api.stripe.com/v1/subscriptions").with(body: { customer: "cus_abc123", items: [{ plan: billing_plan.external_id }], trial_end: "1517428800" })).to have_been_made
    end

    it "sets up a Billing Subscription record" do
      user = User.find_by!(wbid_user_key: "some-user-key")
      saas_implementation = user.saas_implementations.find_by!(company_name: "ACME Corp.")
      billing_subscription = saas_implementation.billing_subscriptions.active.first
      billing_services_agreement = saas_implementation.billing_services_agreements.first

      expect(billing_subscription).to be_active
      expect(billing_subscription.activated_at).to be_within(1).of(Time.now)
      expect(billing_subscription.external_id).to eq("sub_def456")

      expect(billing_services_agreement.user).to eq(user)
      expect(billing_services_agreement.version).to eq(1)
      expect(billing_services_agreement.agreed_at).to be_within(1).of(Time.now)
    end
  end

  describe '#index' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active) }
    let(:unauthorized_saas_implementation) { FactoryBot.create(:saas_implementation, :active) }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").
        and_return(status: 201, body: { id: "cus_abc123" }.to_json).
        and_return(status: 201, body: { id: "cus_abc456" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").
        and_return(status: 201, body: { id: "sub_def456" }.to_json).
        and_return(status: 201, body: { id: "sub_def789" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation
      unauthorized_saas_implementation

      sso_signed_get saas_implementation.user, api_saas_implementations_path
    end

    it { should have_json_api_response(200).with_total_resources(1) }
  end

  describe '#show' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Foo 1") }
    let(:user) { saas_implementation.user }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation

      sso_signed_get user, api_saas_implementation_path(saas_implementation)
    end

    it { should have_json_api_response(200).
      with_resource('saas_implementations',
        'status' => 'active',
        'company_name' => 'Foo 1',
        'code' => 'foo-1',
        'logo' => anything,
        'eligibility_type' => 'google_directory',
        'card_details' => {
         'brand' => 'Visa',
         'last4' => '4242',
         'exp_month' => 4,
         'exp_year' => 2024
        },
        'trial_ends_at' => '2018-01-31T20:00:00.000Z',
        'cycle_day' => 31,
        'onboarding_latest_step_completed' => nil,
        'onboarding_next_step' => 'welcome',
        'onboarded' => false
      )
    }

    context "the User wasn't the one who created the SaasImplementation" do
      let(:user) { FactoryBot.create(:user) }

      it { should have_json_api_response(404) }
    end
  end

  describe '#update' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, company_name: "Foo 1") }
    let(:user) { saas_implementation.user }
    let(:logo_base64_data) { Base64.strict_encode64(File.read(Rails.root.join('spec', 'fixtures', 'logo.jpg'))) }
    let(:attributes_params) { { company_name: "Foo 2", code: "foo-2-special", eligibility_type: "google_directory", logo: "data:image/jpeg;base64,#{logo_base64_data}", onboarding_latest_step_completed: "setup-program" } }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation
      saas_implementation.update!(onboarding_latest_step_completed: "welcome")

      sso_signed_update user, api_saas_implementation_path(saas_implementation), params: { data: { id: saas_implementation.id, type: "saas_implementations", attributes: attributes_params } }.to_json
    end

    it { should have_json_api_response(200).
      with_resource('saas_implementations',
        'status' => 'active',
        'company_name' => 'Foo 2',
        'code' => 'foo-2-special',
        'logo' => anything,
        'eligibility_type' => 'google_directory',
        'card_details' => {
         'brand' => 'Visa',
         'last4' => '4242',
         'exp_month' => 4,
         'exp_year' => 2024
        },
        'trial_ends_at' => '2018-01-31T20:00:00.000Z',
        'cycle_day' => 31,
        'onboarding_latest_step_completed' => 'setup-program',
        'onboarding_next_step' => 'select-eligibility',
        'onboarded' => false
      )
    }

    it "activates the SaasImplementation" do
      saas_implementation.reload

      expect(saas_implementation).to be_active
      expect(saas_implementation.starts_at).to be_within(1).of(Time.now)
      expect(saas_implementation.eligibility_type).to eq("google_directory")
      expect(saas_implementation.logo_uid).to be_present
      expect(saas_implementation.customer).to be_present
      expect(saas_implementation.contract).to be_present

      expect(saas_implementation).to have(1).vanity_url
      expect(saas_implementation.segment).to have(1).segment_update_notification

      expect(user).to have(1).resource_permission
      expect(user.resource_permissions.first.resource).to eq(saas_implementation.contract)
    end

    context "the logo and company name can always be updated" do
      let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Something old") }
      let(:attributes_params) { { company_name: "Something new", logo: "data:image/jpeg;base64,#{logo_base64_data}" } }

      it { should have_json_api_response(200).
        with_resource('saas_implementations',
          hash_including(
            'company_name' => 'Something new',
            'logo' => anything # no really good way to assert change here
          )
        )
      }
    end

    context "the eligibility type cannot be updated after being initially selected" do
      let(:saas_implementation) { FactoryBot.create(:saas_implementation, eligibility_type: :adp) }
      let(:attributes_params) { { eligibility_type: "google_directory" } }

      it { should have_json_api_response(200).
        with_resource('saas_implementations',
          hash_including('eligibility_type' => 'adp')
        )
      }
    end

    context "the code cannot be updated after the implementation has been activated" do
      let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Foo Bar") }
      let(:attributes_params) { { code: "baz" } }

      it { should have_json_api_response(200).
        with_resource('saas_implementations',
          hash_including('code' => 'foo-bar')
        )
      }
    end

    context "the User wasn't the one who created the SaasImplementation" do
      let(:user) { FactoryBot.create(:user) }

      it { should have_json_api_response(404) }
    end
  end

  describe 'related billing plan path' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Foo 1") }
    let(:user) { saas_implementation.user }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation

      sso_signed_get user, billing_plan_api_saas_implementation_path(saas_implementation)
    end

    it { should have_json_api_response(200).
      with_resource('billing_plans',
        hash_including('name' => saas_implementation.billing_plan.name)
      )
    }

    context 'the billing plan has been deactivated' do
      let(:saas_implementation) { super().tap { |si| si.billing_plan.deactivated! } }

      it { should have_json_api_response(200).
        with_resource('billing_plans',
          hash_including('name' => saas_implementation.billing_plan.name)
        )
      }
    end
  end

  describe 'related contract path' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Foo 1") }
    let(:user) { saas_implementation.user }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation

      sso_signed_get user, contract_api_saas_implementation_path(saas_implementation)
    end

    it { should have_json_api_response(200).
      with_resource('contracts',
        hash_including('name' => 'Foo 1')
      )
    }

    context 'the saas implementation has not yet got a contract' do
      let(:saas_implementation) { FactoryBot.create(:saas_implementation, company_name: "Foo 1") }

      it { should have_json_api_response(404) }
    end
  end

  describe 'related organization path' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Foo 1") }
    let(:user) { saas_implementation.user }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation

      sso_signed_get user, organization_api_saas_implementation_path(saas_implementation)
    end

    it { should have_json_api_response(200).
      with_resource('organizations',
        hash_including('name' => 'Foo 1')
      )
    }

    context 'the saas implementation has not yet got a contract' do
      let(:saas_implementation) { FactoryBot.create(:saas_implementation, company_name: "Foo 1") }

      it { should have_json_api_response(404) }
    end
  end

  describe 'related segment path' do
    let(:saas_implementation) { FactoryBot.create(:saas_implementation, :active, company_name: "Foo 1") }
    let(:user) { saas_implementation.user }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      saas_implementation

      sso_signed_get user, segment_api_saas_implementation_path(saas_implementation)
    end

    it { should have_json_api_response(200).
      with_resource('segments',
        hash_including('name' => 'Foo 1')
      )
    }

    context 'the saas implementation has not yet got a contract' do
      let(:saas_implementation) { FactoryBot.create(:saas_implementation, company_name: "Foo 1") }

      it { should have_json_api_response(404) }
    end
  end

  describe 'related billing period path' do
    let(:billing_period) { FactoryBot.create(:billing_period, :paid, amount: 0.199e3) }
    let(:zero_billing_period) { FactoryBot.create(:billing_period, :paid, saas_implementation: saas_implementation, amount: 111) }
    let(:saas_implementation) { billing_period.subscription.saas_implementation }
    let(:user) { saas_implementation.user }

    before do
      WebMock.stub_request(:post, "https://api.stripe.com/v1/customers").and_return(status: 201, body: { id: "cus_abc123" }.to_json)
      WebMock.stub_request(:post, "https://api.stripe.com/v1/subscriptions").and_return(status: 201, body: { id: "sub_def456" }.to_json)
      WebMock.stub_request(:get, "https://api.stripe.com/v1/customers/cus_abc123").and_return(status: 201, body: { id: "cus_abc123", default_source: "card_dinersclub33bb55", sources:  {data: [{id: "card_dinersclub33bb55", brand:"Visa", exp_month:4, exp_year:2024, last4:"4242"}]} }.to_json)

      # don't invoke the creation until after the WebMock stubs have been set
      billing_period
      zero_billing_period

      sso_signed_get user, billing_periods_api_saas_implementation_path(saas_implementation)
    end

    it { should have_json_api_response(200).
      with_resource('billing_periods',
        
    }

    it { should have_json_api_response(200).with_total_resources(1) }

    context 'there are no paid billing periods' do
      let(:billing_period) { FactoryBot.create(:billing_period) }
      let(:saas_implementation) { billing_period.subscription.saas_implementation }
      let(:user) { saas_implementation.user }

      it { should have_json_api_response(200).with_total_resources(0) }
    end
  end
end
