class FollowRequest < ActiveRecord::Base
  belongs_to :requester, class_name: "User",
    inverse_of: :outgoing_follow_requests

  belongs_to :requestee, class_name: "User",
    inverse_of: :incoming_follow_requests

  flexible_enum :status do
    pending 1
    approved 2, setter: :approve!
    rejected 3, setter: :reject!
    blocked 4
  end

  notification_source_for :follow_request_notifications

  validates_presence_of :requester, :requestee
  validate :no_blocking_permitted
  before_save :prevent_duplicate_pending_requests
  after_commit :enqueue_postal_event, :create_trackr_event, on: :create

  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.status ||= PENDING

    true
  end

  def enqueue_postal_event
    PostalEventJob.perform_async("follow_request", "user_id" => self.requestee_id, "follow_request_id" => self.id)
  end

  def create_trackr_event
    track_event(tag: 'requested.follow.user', user: current_user, target_user: requestee, entity: friendship_or_request)
    PostalEventJob.perform_async("follow_request", "user_id" => self.requestee_id, "follow_request_id" => self.id)
  end

  def no_blocking_permitted
    if new_record? && blocked_in_either_direction?
      errors.add(:follow_request, "One of the users has blocked the other")
    end
  end

  def prevent_duplicate_pending_requests
    raise ActiveRecord::RecordInvalid.new(self) if pending? && pending_requests.present?
  end

  def blocked_in_either_direction?
    UserBlock.where(blocker: requester, blockee: requestee).present? || UserBlock.where(blocker: requestee, blockee: requester).present?
  end

  def pending_requests
    FollowRequest.where(requester: requester, requestee: requestee, status: PENDING)
  end
end
