ActiveAdmin.register SaasImplementation do
  menu label: "SaaS implementations", parent: "Implementations", priority: 1

  actions :index, :show

  config.sort_order = "created_at_desc"

  scope :visible, default: true
  scope :deactivated

  index do
    column :company_name do |saas_implementation|
      link_to(saas_implementation.company_name, admin_saas_implementation_path(saas_implementation))
    end
    column :code
    column :billing_type do |saas_implementation|
      saas_implementation.billing_type.titleize
    end

    unless params[:scope] == 'deactivated'
      column :status do |saas_implementation|
        status_tag saas_implementation.status
      end
    end

    column :starts_at do |saas_implementation|
      saas_implementation.starts_at&.in_time_zone(saas_implementation.time_zone)
    end

    if params[:scope] == 'deactivated'
      column :ends_at do |saas_implementation|
        saas_implementation.ends_at.in_time_zone(saas_implementation.time_zone)
      end
    end

    column :created_at

    actions
  end

  filter :billing_type, as: :select, collection: SaasImplementation.billing_types.transform_keys(&:titleize).sort
  filter :company_name
  filter :code
  filter :created_at

  show do |saas_implementation|
    attributes_table do
      row :customer
      row :contract
      row :code
      row :company_name
      row :billing_type do
        saas_implementation.billing_type.titleize
      end
      row :eligibility_type do
        saas_implementation.eligibility_type&.titleize
      end
      row :time_zone
      row :starts_at do
        saas_implementation.starts_at&.in_time_zone(saas_implementation.time_zone)
      end
      row :logo do
        if saas_implementation.logo
          image_tag(saas_implementation.logo.url, class: 'standard-logo')
        end
      end

      row :created_at
    end

    panel "Participation Information" do
      attributes_table_for saas_implementation do
        row "Custom Logo" do
          status_tag saas_implementation.custom_logo?
        end

        row "Eligible Participants" do
          count = saas_implementation.eligible_user_count(with_excluded: false)

          status = case count
          when 0..1
            "red"
          when 2..5
            "orange"
          else
            "active"
          end

          status_tag status, label: count
        end

        row "Support Tickets Created (by Purchaser)" do
          count = $zendesk_client.search(query: 'type:ticket requester:#{}').count
        end
      end
    end

    panel "Billing Subscription" do
      subscription = saas_implementation.current_billing_subscription

      attributes_table_for subscription do
        row :status do
          status_tag subscription.status
        end
        row "Billing plan" do
          "#{subscription.plan.name} — #{number_to_currency(subscription.plan.price)}/mo"
        end
        row "Eligibles" do
          total = saas_implementation.eligible_user_count

          if total
            without_excluded = saas_implementation.eligible_user_count(with_excluded: false)
            difference = total - without_excluded

            "#{without_excluded} eligible / #{difference} excluded / #{total} total"
          else
            "None"
          end
        end
        row :external_id do
          subscription.active? ? link_to(subscription.external_id, "https://dashboard.stripe.com/subscriptions/#{subscription.external_id}", target: "_blank") : subscription.external_id
        end
        row :created_at
        row :trial_ends_at
      end
    end

    panel "Implementation Owner" do
      user = saas_implementation.user

      attributes_table_for user do
        row :name do
          link_to(user.name, admin_user_path(user.id), target: "_blank")
        end
        row :email
      end
    end
  end
end
