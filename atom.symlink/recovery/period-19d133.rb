class Billing::Period < ApplicationRecord
  belongs_to :contract
  belongs_to :subscription
  belongs_to :plan

  has_one :event, as: :resource

  validates :external_invoice_id, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :paid, inclusion: { in: [true, false] }

  with_options if: :paid? do
    validates :amount, presence: true
    validates :charged_at, presence: true
    validates :external_charge_id, presence: true
    validates :card_details, presence: true
  end

  scope :paid, -> { where(paid: true) }
  scope :non_zero, -> { where("amount > '0.00'::float8::numeric::money") }

  def self.generate(payload)
    invoice_object_hash = payload["data"]["object"]
    subscription = Billing::Subscription.find_by(external_id: invoice_object_hash["subscription"])

    self.create!(
      contract: subscription.contract,
      subscription: subscription,
      plan: subscription.plan,
      external_invoice_id: invoice_object_hash["id"],
      starts_at: Time.at(invoice_object_hash["period_start"]),
      ends_at: Time.at(invoice_object_hash["period_end"])
    )
  end

  def mark_paid!(charge_id)
    stripe_charge = Stripe::Charge.retrieve(charge_id)

    self.update!(
      external_charge_id: stripe_charge[:id],
      amount: stripe_charge[:amount] / 100.to_d,
      charged_at: Time.at(stripe_charge[:created]),
      card_details: stripe_charge[:source].to_h.slice(:brand, :last4, :exp_month, :exp_year),
      paid: true
    )
  end
end
