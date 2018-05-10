class SaasImplementationParticipantInfoMetrics

  attr_reader :saas_implementation, :db

  def initialize(saas_implementation)
    @saas_implementation = saas_implementation
    @purchaser = saas_implementation.user
    @segment = saas_implementation.segment
    @db = Sequel.connect(Rails.application.secrets.dwh_url)
  end

  def purchaser_enrolled(service)
  end
enrollment_query = "SELECT DISTINCT
          pr.user_wbid_key
        , pr.service
        FROM c.wbid_sponsor_profiles sp
          INNER JOIN c.wbid_product_registrations pr ON sp.user_wbid_key = pr.user_wbid_key
            AND (c.to_date_key(pr.activated_at) <= c.to_date_key(sp.removed_at) OR sp.removed_at IS NULL)
            AND (c.to_date_key(pr.deactivated_at) >= c.to_date_key(sp.enrolled_at) OR pr.deactivated_at IS NULL)
            AND service = ?
        WHERE sp.segment_key::uuid = ?
        AND pr.user_wbid_key=?"

  end
end
