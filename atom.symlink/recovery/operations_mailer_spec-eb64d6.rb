RSpec.describe OperationsMailer do
  describe "#new_customer_operations_alert" do
    let!(:saas_implementation) { FactoryBot.create(:saas_implementation) }

    subject(:mail) { OperationsMailer.new_customer_operations_alert(saas_implementation.id) }

    its(:to) { should contain_exactly(Rails.application.secrets.new_customer_email_address) }
    its(:subject) { should eq("#{saas_implementation.company_name} just became a customer!") }
    its(:body) { should include("A new SaaS implementation has been created with the following details.") }
    its(:body) { should include("Company name: <a href=\"http://snap.myhdev.com:3700/admin/saas_implementations/#{saas_implementation.id}\">#{saas_implementation.company_name}</a>") }
    its(:body) { should include("Billing plan: #{saas_implementation.billing_plan.name}, price: #{ActiveSupport::NumberHelper.number_to_currency(saas_implementation.billing_plan.price, precision: 0)}") }
    its(:body) { should include("Purchased by: blah") }
  end
end
