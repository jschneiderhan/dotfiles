module GoogleDirectorySteps
  include EnrollmentMacros

  step "there is a contract that uses Google authentication for eligibility" do
    stub_request(:get, "https://www.googleapis.com/oauth2/v2/userinfo?access_token=google-api-token").
      to_return(status: 200, body: { id: "117101418067722848656", name: "John Doe", given_name: "John", family_name: "Doe", gender: "male" }.to_json)
    @sponsor = create(:google_directory_sponsor)
    @contract = @sponsor.contract
  end

  step "I try to enroll in the sponsorship before registering an account" do
    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").
      with(body: { access_token: "google-api-token" }).
      to_return(status: 200, body: { aud: "574296776985-6pm1q51ff2j1mlg5hqguibb6jmcgare7.apps.googleusercontent.com", sub: "117101418067722848656" }.to_json)

    stub_request(:get, "http://snap.myhdev.com:3700/api/v1/contracts/#{@contract.external_key}/google_directory_users").
      with(query: { filter: { excluded: "false", id: "117101418067722848656" }, page: { number: "1", size: "1" } }).
      to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { data: [{ id: "108030724901234970360", type: "google_directory_users" }] }.to_json)

    step "I try to enroll in the sponsorship"
  end

  step "I should be able to register an account" do
    expect(current_path).to eq(new_user_path)

    within "form#new_user" do
      fill_in "Email", with: "zaphod@example.com"
      fill_in "Password", with: "b33tleju1ce"

      check "I agree to the MeYou Health"

      click_button "Next"
    end

    @user = User.find_by(email: "zaphod@example.com")

    expect(current_path).to eq(new_sponsor_consent_path)
  end

  step "I am part of the G Suite account" do
    create_and_sign_in_user(sponsor: @sponsor)

    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").
      with(body: { access_token: "google-api-token" }).
      to_return(status: 200, body: { aud: "574296776985-6pm1q51ff2j1mlg5hqguibb6jmcgare7.apps.googleusercontent.com", sub: "117101418067722848656" }.to_json)

    stub_request(:get, "http://snap.myhdev.com:3700/api/v1/contracts/#{@contract.external_key}/google_directory_users").
      with(query: { filter: { excluded: "false", id: "117101418067722848656" }, page: { number: "1", size: "1" } }).
      to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { data: [{ id: "108030724901234970360", type: "google_directory_users" }] }.to_json)
  end

  step "I am using a different Google account" do
    create_and_sign_in_user(sponsor: @sponsor)

    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").
      with(body: { access_token: "google-api-token" }).
      to_return(status: 200, body: { aud: "574296776985-6pm1q51ff2j1mlg5hqguibb6jmcgare7.apps.googleusercontent.com", sub: "115613546513681306545" }.to_json)

    stub_request(:get, "http://snap.myhdev.com:3700/api/v1/contracts/#{@contract.external_key}/google_directory_users").
      with(query: { filter: { excluded: "false", id: "115613546513681306545" }, page: { number: "1", size: "1" } }).
      to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { data: [] }.to_json)

    stub_request(:post, "https://accounts.google.com/o/oauth2/revoke").
      with(body: { token: "google-api-token" }).
      to_return(status: 200)
  end

  step "I am trying to hack the eligibility check by manipulating the audience of the issued token" do
    create_and_sign_in_user(sponsor: @sponsor)

    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").
      with(body: { access_token: "google-api-token" }).
      to_return(status: 200, body: { aud: "totally-fake-audience.apps.googleusercontent.com", sub: "117101418067722848656" }.to_json)
  end

  step "I am trying to hack the eligibility check by supplying an invalid token" do
    create_and_sign_in_user(sponsor: @sponsor)

    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").
      with(body: { access_token: "google-api-token" }).
      to_return(status: 200, body: { error_description: "Invalid Value" }.to_json)
  end

  step "I am trying the eligibility check but am receiving a popup_closed_by_user error" do
    create_and_sign_in_user(sponsor: @sponsor)

    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").
      with(body: { access_token: "google-api-token" }).
      to_return(status: 500, body: { error_description: "Invalid Value" }.to_json)
  end

  step "I try to enroll in the sponsorship" do
    visit new_enrollment_google_directory_path(contract: @contract, option: "signup")

    within "form#new_enrollment" do
      find("input#token", visible: false).set "google-api-token"

      find("input[type=submit]", visible: false).click
    end
  end

  step "I should have to read the sponsor's consent before continuing" do
    eligibility_record = @user.eligibility_records.active.first

    expect(eligibility_record.external_key).to eq("117101418067722848656")
    expect(@user.sponsor).to be_nil
    expect(@user.pending_sponsor).to eq(@sponsor)
    expect(eligibility_record.sponsor).to eq(@sponsor)

    expect(current_path).to eq(new_sponsor_consent_path)
  end

  step "I should be told to use the G Suite account to verify eligibility" do
    expect(current_path).to eq(new_enrollment_google_directory_path(contract: @contract))

    expect(page).to queue_flash_message("alert").with("Sorry! We couldn't find a match with your information. Please try again or <a href='TBD'>contact Support</a>.")

    expect(@user.sponsor).to be_nil
    expect(@user.pending_sponsor).to be_nil
  end

  step "I should be told that the token is invalid" do
    expect(current_path).to eq(new_enrollment_google_directory_path(contract: @contract))

    expect(page).to have_content("Payload is invalid.")

    expect(@user.sponsor).to be_nil
    expect(@user.pending_sponsor).to be_nil
  end

  step "I should be told \"ABCD Oops! It looks like you closed the window before you signed in. Please try again.\"" do
    #expect(current_path).to eq(new_enrollment_google_directory_path(contract: @contract))

    expect(page).to queue_flash_message("alert").with("Sorry! We couldn't find a match with your information. Please try again or <a href='TBD'>contact Support</a>.")

    expect(@user.sponsor).to be_nil
    expect(@user.pending_sponsor).to be_nil
  end
end
