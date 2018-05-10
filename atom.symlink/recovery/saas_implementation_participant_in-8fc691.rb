class SaasImplementationParticipantInfoMetrics

  attr_reader :saas_implementation, :segment, :purchaser, :dwh_db, :wbid_db

  def initialize(saas_implementation)
    @saas_implementation = saas_implementation
    @purchaser = saas_implementation.user
    @segment = saas_implementation.segment
    @dwh_db = Sequel.connect(Rails.application.secrets.dwh_url)
    @wbid_db = Sequel.connect(Rails.application.secrets.wbid_database_url)
  end

  def purchaser_enrolled(service)
    enrollment_query = "
    SELECT DISTINCT
        u.key
      , pr.product_id
      FROM sponsor_profiles sp
        INNER JOIN users u on sp.user_id = u.id
        INNER JOIN product_registrations pr ON sp.user_id = pr.user_id
        INNER JOIN sponsors s on sp.sponsor_id = s.id
          AND (pr.activated_at <= sp.removed_at OR sp.removed_at IS NULL)
          AND (pr.deactivated_at >= sp.enrolled_at OR pr.deactivated_at IS NULL)
          AND pr.product_id = ?
      WHERE s.external_key::uuid = ?
      AND u.key = ?"
    wbid_db.fetch(enrollment_query, service, segment.id, purchaser.wbid_user_key).count > 0
  end

  def purchaser_signed_in(service)
    # Need to add 'signed.in' events to DC, WD, WBT, DC
    false
  end

  def purchaser_dc_completed_challenge
    # insight_server_app doesn't have access to the e_completed_challenge table. Should we add a new view?
    false
  end

  def purchaser_dc_connections_created
    # I don't see an event for this
    false
  end

  def purchaser_wbt_completed_survey
    # I don't see an event fot this either
    false
  end

  def purchaser_wd_connected_device
    # I don't see an event here either
    false
  end

  def purchaser_wd_followed_another_user
    # I don't see any events for this
    false
  end
end
