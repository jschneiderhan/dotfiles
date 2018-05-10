RSpec.describe Implementation do
  it { should belong_to(:contract).dependent(:destroy) }
  it { should belong_to(:customer).dependent(:destroy) }

  it { should have_one(:organization).through(:contract) }
  it { should have_one(:segment).through(:contract) }

  it { should have_many(:vanity_urls).through(:contract) }

<<<<<<< HEAD
=======
  describe "validations" do
    describe "adp_purchase" do
      context "when :adp" do
        subject { Implementation.new(eligibility_type: :adp) }

        it { should_not validate_absence_of(:adp_purchase) }
      end

      context "when :password" do
        subject { Implementation.new(eligibility_type: :password) }

        it { should validate_absence_of(:adp_purchase) }
      end

      context "when :google_directory" do
        subject { Implementation.new(eligibility_type: :google_directory) }

        it { should validate_absence_of(:adp_purchase) }
      end

      context "when :email" do
        subject { Implementation.new(eligibility_type: :email) }

        it { should validate_absence_of(:adp_purchase) }
      end
    end
  end

>>>>>>> Add email eligibility for turnkey implementations
  describe ".eligibility_types" do
    # if this changes, update the examples below
    specify { expect(Implementation.eligibility_types.keys).to eq(["password", "google_directory", "adp", "email"]) }

    specify { expect(Implementation.eligibility_types[:password]).to eq(Contract.eligibility_types[:password]) }
    specify { expect(Implementation.eligibility_types[:google_directory]).to eq(Contract.eligibility_types[:google_directory]) }
    specify { expect(Implementation.eligibility_types[:adp]).to eq(Contract.eligibility_types[:adp]) }
    specify { expect(Implementation.eligibility_types[:email]).to eq(Contract.eligibility_types[:email]) }
  end

  describe "#save" do
    let(:customer) { FactoryBot.create(:customer) }
    let(:production_starts_at) { Time.local(2017, 10, 18) }

    subject do
      Implementation.new(
        customer: customer,
        code: "johnny-putter",
        description: "Johnson Cow Pat and Udder Company Description",
        eligibility_type: "password",
        eligibility_password: "johnnyputter",
        logo: Rails.root.join('spec', 'fixtures', 'johnnyputter.png').open,
        name: "Johnson Cow Pat and Udder Company",
        production_starts_at: production_starts_at,
        time_zone: "America/New_York"
      )
    end

    before do
      Timecop.freeze(Time.local(2017, 10, 11))
      allow(SegmentUpdateNotificationJob).to receive(:perform_async)
    end

    context "given a savable object" do
      let!(:save_result) { subject.save }

      it { expect(save_result).to be_truthy }

      it "created a segment update notification" do
        expect(s = SegmentUpdateNotification.last).to be_present
        expect(s.segment).to eq(subject.contract.reload.segments.last)
      end

      it "kicked off a segment update notification job" do
        expect(SegmentUpdateNotificationJob).to have_received(:perform_async).with(SegmentUpdateNotification.last.id)
      end

      it "created the contract, organization and segment" do
        expect(c = Contract.find_by(url_code: "johnny-putter")).to have_attributes(
          customer_id: customer.id,
          name: "Johnson Cow Pat and Udder Company",
          uat_starts_at: Time.current,
          uat_ends_at: Float::INFINITY,
          production_starts_at: production_starts_at,
          production_ends_at: Float::INFINITY,
          time_zone: "America/New_York",
          eligibility_type: "password",
          product_ids: ["wellbeingtracker", "dailychallenge", "walkadoo", "quitnet"],
          default_product_id: "wellbeingtracker",
          product_configurations: {
            "quitnet" => {
              "offers_hways_nrt" => false,
              "wbo_phone_prompt" => false,
              "coaching_phone_number" => nil,
              "offers_phone_coaching" => false,
              "third_party_nrt_email" => false,
              "offers_digital_coaching" => false,
              "enrollment_period_duration" => 12
            },
            "wellbeingtracker" => {
              "landing_page_sections" => ["wbt", "daily_challenge", "walkadoo", "quitnet"] }
          }
        )

        expect(c.vanity_urls).to contain_exactly(an_object_having_attributes(
          code: "johnny-putter",
          primary: true
        ))

        expect(c.organizations).to contain_exactly(an_object_having_attributes(name: c.name))

        expect(c.segments).to contain_exactly(an_object_having_attributes(
          name: c.name,
          description: "Johnson Cow Pat and Udder Company Description",
          code: c.url_code,
          prototype: c.url_code,
          uat_starts_at: c.uat_starts_at,
          uat_ends_at: c.uat_ends_at,
          production_starts_at: c.production_starts_at,
          production_ends_at: c.production_ends_at,
          auto_enroll_product_ids: ["dailychallenge"],
          product_configurations: {
            "wellbeingid" => {
              "password" => "johnnyputter",
              "requires_consent" => true
            },
            "dailychallenge" => {
              "show_label" => true
            }
          }
        ))
      end
    end

    context "given an unsavable object" do
      before { allow_any_instance_of(Contract).to receive(:save).and_return(false) }

      let!(:save_result) { subject.save }

      it { expect(save_result).to be_falsey }
      its(:contract_id) { should be_nil }
    end
  end

  describe "#time_zone=" do
    context "given an IANA data-identifier (identifier of a canonical zone)" do
      subject { Implementation.new(time_zone: "America/New_York") }

      its(:time_zone) { should eq("America/New_York") }
    end

    context "given an IANA link-identifier (identifier of a non-canonical zone)" do
      subject { Implementation.new(time_zone: "US/Eastern") }

      # canonical data-id for this link is what is stored
      its(:time_zone) { should eq("America/New_York") }
    end

    context "given a nil time zone" do
      subject { Implementation.new }

      its(:time_zone) { should be_nil }
    end
  end
end
