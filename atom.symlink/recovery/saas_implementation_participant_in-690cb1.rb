class SaasImplementationParticipantInfoMetrics

  attr_reader :saas_implementation, :db

  def initialize(saas_implementation)
    @saas_implementation = saas_implementation
    @purchaser = saas_implementation.user
    @segment = saas_implementation.segment
    @db = Sequel.connect(Rails.application.secrets.dwh_url)
  end

  def purchaser_enrolled(service)
    enrollment_query = "
      SELECT DISTINCT
          pr.user_wbid_key
        , pr.service
        FROM c.wbid_sponsor_profiles sp
          INNER JOIN c.wbid_product_registrations pr ON sp.user_wbid_key = pr.user_wbid_key
            AND (c.to_date_key(pr.activated_at) <= c.to_date_key(sp.removed_at) OR sp.removed_at IS NULL)
            AND (c.to_date_key(pr.deactivated_at) >= c.to_date_key(sp.enrolled_at) OR pr.deactivated_at IS NULL)
            AND service = ?
        WHERE sp.segment_key::uuid = ?
        AND pr.user_wbid_key=?"
    db.fetch(enrollment_query, service, saas_implementation.segment.id, saas_implementation.user.wbid_user_key).count > 0
  end

  def purchaser_signed_in(service)
    false
  end

  def purchaser_dc_completed_challenge
    # insight_server_app doesn't have access to the e_
    false
  end

  def purchaser_dc_connections_created
    false
  end

  def purchaser_wbt_completed_survey
    false
  end

  def purchaser_wd_connected_device
    false
  end

  def purchaser_wd_followed_another_user
    false
  end
end
