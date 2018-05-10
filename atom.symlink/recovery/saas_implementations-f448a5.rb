ActiveAdmin.register SaasImplementation do
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

        row "Visited Support Site" do
          count, first_at, last_at = PurchaseAnalyticsEvent
            .where(saas_implementation: saas_implementation, event_type: :support_site_view)
            .pluck("COUNT(id)", "MIN(recorded_at)", "MAX(recorded_at)").first

          status_tag count.zero? ? "red" : "active", label: "#{count} #{"visit".pluralize(count)}"

          if count == 1
            "at #{pretty_format(first_at.in_time_zone(saas_implementation.time_zone))}"
          elsif count > 1
            "from #{pretty_format(first_at.in_time_zone(saas_implementation.time_zone))} to #{pretty_format(last_at.in_time_zone(saas_implementation.time_zone))}"
          end
        end

        row "Enrolled Users" do
          Metrics::Dc::NewUsers.
          table_for [{name: "Daily Challenge", value: 100}, {name: "QuitNet", value: 101}, {name: "Walkadoo", value: 102}] do
            column "Product", :name
            column "# Users", :value
          end
        end
      end
    end

    panel "Billing Subscription" do
      billing_plan = saas_implementation.billing_plan
      subscription = saas_implementation.current_billing_subscription
      adp_purchase = saas_implementation.adp_purchase

      common_rows = proc do
        row "Billing plan" do
          "#{billing_plan.name} — #{number_to_currency(billing_plan.price)}/mo"
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

        row :created_at
      end

      if subscription
        attributes_table_for subscription do
          row "Status" do
            status_tag subscription.status
            " via Stripe"
          end

          instance_exec(&common_rows)

          row "External" do
            subscription.active? ? link_to(subscription.external_id, "https://dashboard.stripe.com/subscriptions/#{subscription.external_id}", target: "_blank") : subscription.external_id
          end

          row :trial_ends_at
        end
      end

      if adp_purchase
        attributes_table_for adp_purchase do
          row "Status" do
            status_tag adp_purchase.status
            " via ADP"
          end

          instance_exec(&common_rows)

          row "External" do
            link_to "ADP Platform Accounts", Rails.application.secrets[:adp_app_direct_accounts_urls].fetch(adp_purchase.adp_app_code.to_sym)
          end
        end
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

    if cancellation = saas_implementation.cancellation
      panel "Cancellation details", id: "cancellation" do
        attributes_table_for cancellation do
          row SaasImplementationCancellation::QUESTIONS[:why] do
            cancellation.why
          end
          row SaasImplementationCancellation::QUESTIONS[:duration] do
            cancellation.duration
          end
          row SaasImplementationCancellation::QUESTIONS[:improvements] do
            cancellation.improvements
          end
          row SaasImplementationCancellation::QUESTIONS[:alternative] do
            cancellation.alternative
          end
        end
      end
    end
  end
end
