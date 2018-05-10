RSpec.describe AuthenticationsController do
  describe "#create" do
    let(:auth_hash) { { provider: "wbid", uid: "omniauth_uid", credentials: { token: "asdf", refresh_token: "jkla", expires_at: Time.now.to_i }, info: { email: "foo@example.com", name: "John Doe" } } }
    let(:omniauth_params) { {} }
    let(:authentication_token) { nil }

    before do
      Timecop.freeze
      request.env["omniauth.auth"] = OmniAuth::AuthHash.new(auth_hash)
      request.env["omniauth.params"] = omniauth_params
      # allow(AuthenticationToken).to receive_message_chain(:active, :find_by).with(provider_code: "wbid").and_return(authentication)
      allow(AuthenticationToken).to receive_message_chain(:active, :find_by).with(provider_code: "wbid", uid: "omniauth_uid").and_return(authentication)
      allow(AuthenticationToken).to receive(:create!).and_return(authentication_token)
    end

    context "there is already a WD account connected to that provider+UID" do
      let(:user) { stub_model(User) }
      let(:authentication) { double(user: user) }
      let(:omniauth_origin) { nil }

      before do
        allow(controller).to receive(:bypass_sign_in)
        request.env["omniauth.origin"] = omniauth_origin

        post :create, provider_code: "wbid"
      end

      it { should redirect_to(root_path) }

      it "signs the user in" do
        expect(controller).to have_received(:bypass_sign_in).with(authentication.user)
      end

      context "the auth_mode is API" do
        let(:omniauth_params) { { "auth_mode" => "api" } }
        let(:authentication_token) { { authentication_token: { foo: "bar" }} }

        it { should respond_with(:created) }
        its("response.body") { should eq(authentication_token.to_json) }

        it "creates an authentication token" do
          expect(AuthenticationToken).to have_received(:create!).with(user: user, provider: "wbid")
        end
      end

      context "omniauth.origin is set to a disallowed URL" do
        let(:omniauth_origin) { "/foo/bar" }

        it { should redirect_to(root_path) }
      end
    end

    context "processing an invitation" do
      let(:user) { stub_model(User) }
      let(:authentication) { double(user: user) }
      let(:omniauth_origin) { nil }
      let!(:sender) { create(:user, invite_key: "h3ll0w0rld") }
      let!(:invite) { create(:invite, sender: sender, key: "abc8675309") }

      before do
        allow(controller).to receive(:bypass_sign_in)
        allow(controller).to receive(:process_email_invitation)
        allow(controller).to receive(:process_link_invitation)
        request.env["omniauth.origin"] = omniauth_origin

        post :create, provider_code: "wbid"
      end

      context "there is an invitation key passed" do
        let(:omniauth_params) { { "invitation_key" => "abc8675309" } }

        it "processes the email invitation" do
          expect(controller).to have_received(:process_email_invitation).with(user, "abc8675309")
        end

        it { should redirect_to(root_path) }
      end

      context "there is a user invite key passed" do
        let(:omniauth_params) { { "user_invite_key" => "h3ll0w0rld" } }

        it "processes the link invitation" do
          expect(controller).to have_received(:process_link_invitation).with(user, "h3ll0w0rld")
        end

        it { should redirect_to(root_path) }
      end
    end

    context "there is a matching WD user based on the email" do
      let(:authentication) { nil }
      let(:user) { stub_model(User) }
      let(:registration_service) { double(success?: true, user: user) }
      let(:omniauth_origin) { nil }

      before do
        allow(AccountRegistrationService).to receive(:new).with(auth_hash).and_return(registration_service)
        allow(controller).to receive(:bypass_sign_in)
        request.env["omniauth.origin"] = omniauth_origin

        post :create, provider_code: "wbid"
      end

      it "signs the user in" do
        expect(controller).to have_received(:bypass_sign_in).with(registration_service.user)
      end

      context "the auth_mode is API" do
        let(:omniauth_params) { { "auth_mode" => "api" } }
        let(:authentication_token) { { authentication_token: { foo: "bar" }} }

        it { should respond_with(:created) }
        its("response.body") { should eq(authentication_token.to_json) }

        it "creates an authentication token" do
          expect(AuthenticationToken).to have_received(:create!).with(user: user, provider: "wbid")
        end
      end

      context "omniauth.origin is set to a disallowed URL" do
        let(:omniauth_origin) { "/foo/bar" }

        it { should redirect_to(root_path) }
      end

      context "the registration fails" do
        let(:registration_service) { double(success?: false) }

        it { should respond_with(:forbidden) }
      end
    end
  end

  describe "#failure" do
    before { get :failure }

    it { should respond_with(:forbidden) }
  end
end
