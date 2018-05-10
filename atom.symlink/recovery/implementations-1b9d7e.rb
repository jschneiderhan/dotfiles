ActiveAdmin.register Implementation do
  menu label: "Turn-key implementations", parent: "Implementations", priority: 2

  permit_params :customer_id, :code, :name, :description, :logo, :retained_logo, :eligibility_type, :eligibility_password, :time_zone, :production_starts_at, :adp_purchase_id

  config.sort_order = "name_asc"

  actions :index, :new, :create, :show

  def create
    debugger
    super
  end

  index do
    column :name do |implementation|
      link_to(implementation.name, admin_implementation_path(implementation))
    end
    column :code
    column :production_starts_at do |implementation|
      implementation.production_starts_at.in_time_zone(implementation.time_zone)
    end
    column :created_at

    actions
  end

  filter :customer, collection: Customer.order(:name)
  filter :eligibility_type, as: :select, collection: Implementation.eligibility_types.transform_keys(&:titleize).sort
  filter :code

  show do |implementation|
    attributes_table do
      row :contract
      row :code
      row :name
      row :description
      row :eligibility_type do
        implementation.eligibility_type.titleize
      end
      row :adp_purchase do
        implementation.adp_purchase&.description
      end
      row :eligibility_password
      row :time_zone

      row :production_starts_at do
        implementation.production_starts_at.in_time_zone(implementation.time_zone)
      end
      row :logo do
        image_tag(implementation.logo.url, class: 'standard-logo')
      end

      row :created_at
    end
  end

  form do |f|
    f.semantic_errors

    inputs multipart: true do
      input :customer_id, as: :select, collection: Customer.all.order(:name)
      input :code
      input :name
      input :description
      input :logo, as: :file
      input :retained_logo, as: :hidden
      input :eligibility_type, as: :select, collection: Implementation.eligibility_types.keys.collect { |type| [type.titleize, type] }
      input :adp_purchase_id, as: :select, hint: "Only valid if eligibility type is 'ADP'", collection: Adp::Purchase.unassigned.includes(:subscription_created_event).order(:created_at).map { |p| [p.description, p.id] }
      input :eligibility_password, as: :string, hint: "Only required if eligibility type is 'Password'", input_html: { rows: 1, columns: 25, maxlength: 25, style: "resize: none;" }
      input :time_zone, as: :select, collection: TimeZone.all_canonical_identifiers, selected: (f.object.time_zone || "US/Eastern")
      input :production_starts_at, as: :date_picker

      actions
    end
  end
end
