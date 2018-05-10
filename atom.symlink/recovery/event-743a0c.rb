class Billing::Event < ApplicationRecord
  belongs_to :resource, polymorphic: true, optional: true

  validates :external_id, presence: true, uniqueness: { allow_blank: true }
  validates :event_type, presence: true
  validates :payload, presence: true
  validates :occurred_at, presence: true

  before_create :process_billing_event, if: :billing_event?

  private

  def billing_event?
    event_type.in?(["invoice.created", "invoice.payment_succeeded"])
  end

  def process_billing_event
    if event_type == "invoice.created"
      create_new_billing_period
    elsif event_type == "invoice.payment_succeeded"
      record_payment
    end
  end

  def create_new_billing_period
    self.resource = Billing::Period.generate(payload)
  end

  def record_payment
    billing_period = Billing::Period.find_by(external_invoice_id: payload["data"]["object"]["id"])

    billing_period.mark_paid!(payload["data"]["object"]["charge"])

    if !invoice_for_regular_period? && !invoice_for_trial_period?
      raise "Payload contains unexpected data. Event ID: #{payload["data"]["object"]["id"]}"
    end

    if invoice_for_regular_period?
      self.resource = Billing::Notification.create!(event_type: event_type.gsub('.', '_'), resource: billing_period)
    end
  end

  def invoice_for_trial_period?
    # amount == 0
    # charge is NULL
    # trial ends at > payload's date
    debugger
    if (payload["data"]["object"]["amount_due"] == 0) && (payload["data"]["object"]["charge"] == nil)
      return true
    else
      return false
    end
  end

  def invoice_for_regular_period?
    # amount > 0
    # charge is not NULL
    # trial ends at < payload's date
    if (payload["data"]["object"]["amount_due"] > 0) && (payload["data"]["object"]["charge"] != nil)
      return true
    else
      return false
    end
  end
end
