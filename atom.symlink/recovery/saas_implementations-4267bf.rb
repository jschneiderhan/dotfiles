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
    column :phone_number

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
      row :phone_number
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
      row :landing_page_banner_background_color

      row :created_at
    end

    panel "Participation Information" do
      attributes_table_for saas_implementation do
        row "Custom Landing Page Color" do
          span(class: "status_tag", style: "background-color: #{saas_implementation.landing_page_banner_background_color}") do
            saas_implementation.custom_landing_page_banner_background_color? ? "Custom" : "Default"
          end
        end

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

        row "Support Tickets Created (by Purchaser)" do
          if Rails.env.production?
            zendesk_client = ZendeskAPI::Client.new do |config|
              config.url = Rails.application.secrets.zendesk[:url]
              config.username = Rails.application.secrets.zendesk[:username]
              config.token = Rails.application.secrets.zendesk[:token]
            end
            count = zendesk_client.search(query: "type:ticket requester:#{saas_implementation.user.email}").count

            status = count > 0 ? "yes" : "no"
            status_tag status, label: count
          else
            status_tag "no", label: "N/A"
          end
        end

        row "User Information" do
          metrics = [
            { name: "Daily Challenge", users_metric: Metrics::Dc::Users, engaged_participants_metric: Metrics::Dc::EngagedParticipants },
            { name: "QuitNet", users_metric: Metrics::Qn::Users, engaged_participants_metric: Metrics::Qn::EngagedParticipants},
            { name: "Walkadoo", users_metric: Metrics::Wd::Users, engaged_participants_metric: Metrics::Qn::EngagedParticipants},
            { name: "Well-Being ID", users_metric: Metrics::Pl::Users },
            { name: "Well-Being Tracker", users_metric: Metrics::Wbt::Users, engaged_participants_metric: Metrics::Wbt::EngagedParticipant },
          ]
          table_for metrics do
            column "Product", :name
            column "Total" do |m|
              value = m[:users_metric].new([saas_implementation.segment], saas_implementation.starts_at).data_points.to_h["totalUsers"]
              status = case value
              when 0..1
                "red"
              when 2..5
                "orange"
              else
                "active"
              end
              status_tag status, label: value
            end

            column "Active" do |m|
              value = m[:users_metric].new([saas_implementation.segment], saas_implementation.starts_at).data_points.to_h["totalUsers"]
              status = case value
              when 0..1
                "red"
              when 2..5
                "orange"
              else
                "active"
              end
              status_tag status, label: value
            end

            column "Engaged" do |m|
              value = m[:engaged_participants_metric].try do |metric|
                metric.new([saas_implementation.segment], saas_implementation.starts_at).data_points.collect {|dp| dp[1]}.sum
              end
              if value.nil?
                status_tag "inactive", label: "N/A"
              else
                status = case value
                when 0..1
                  "red"
                when 2..5
                  "orange"
                else
                  "active"
                end
                status_tag status, label: value
              end
            end
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
