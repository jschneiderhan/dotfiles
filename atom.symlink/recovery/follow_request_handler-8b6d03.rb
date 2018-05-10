class FollowRequestHandler
  def self.create_friendship_or_request!(requester, requestee)
    if !requester.following?(requestee)
      if requestee.private?
        requester.outgoing_follow_requests.find_or_create_by(requestee_id: requestee.id) do |follow_request|
          MessageDigestQueue.enqueue(requestee, :follow_request_notification, follow_request)
        end
      else
        FollowRequestHandler::create_friendship!(requester, requestee)
      end
    end
  end

  def self.create_request!(requester, requestee)
    FollowRequest.transaction do
      requester.outgoing_follow_requests.create!(requestee_id: requestee.id).tap do |follow_request|
        FollowRequestResolver.new(follow_request).approve_or_enqueue!
      end
    end
  end

  def self.reject!(follow_request)
    follow_request.reject!
  end

  def self.create_friendship!(requester, requestee)
    requester.with_lock do
      friendship = requester.friendships.create!(friend_id: requestee.id)
      Stamps::Following.new(friendship).run
      MessageDigestQueue.enqueue(friendship.friend, :friendship_notification, friendship)
      friendship
    end
  end

  def self.approve!(follow_request)
    FollowRequest.transaction do
      follow_request.approve!
      FollowRequestHandler::create_friendship!(follow_request.requester, follow_request.requestee)
    end
  end

  class FollowRequestResolver
    attr_reader :follow_request

    def initialize(follow_request)
      @follow_request = follow_request
    end

    def requester
      @requester ||= follow_request.requester
    end

    def requestee
      @requestee ||= follow_request.requestee
    end

    def approve_or_enqueue!
      requestee.public? ? approve_request! : enqueue_request!
    end

    def approve_request!
      FollowRequestHandler::approve!(follow_request)
    end

    def enqueue_request!
      if friendship_exists?
        raise "friendship already exists"
      else
        MessageDigestQueue.enqueue(requestee, :follow_request_notification, follow_request)
      end
    end

    def friendship_exists?
      requester.friendships.where(friend: requestee).present?
    end
  end
end
