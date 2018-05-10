class FollowRequestsController < ApplicationController
  before_action :authenticate_user!

  layout false

  def create
    friendship_or_request = FollowRequestHandler.create_friendship_or_request!(current_user, requestee)

    track_event(tag: 'requested.follow.user', user: current_user, entity: friendship_or_request)

    if friendship_or_request
      respond_to do |format|
        format.html do
          if request.xhr?
            render partial: partial,
              locals: {
                user: requestee,
                pending: friendship_or_request.try(:pending?)
              },
              status: 201
          else
            redirect_to user_path(requestee)
          end
        end

        format.json { render json: friendship_or_request.to_json }
      end
    else
      render nothing: true, status: 409
    end
  end

  def update
    follow_request = FollowRequest.find(params[:id])

    if can?(:manage, follow_request)
      if follow_request.pending?
        if approved_request?
          FollowRequestHandler.approve!(follow_request)
          flash[:notice] = t(".approved", name: follow_request.requester.name)
        else
          FollowRequestHandler.reject!(follow_request)
          flash[:notice] = t(".rejected", name: follow_request.requester.name)
        end
      else
        flash[:notice] = t(".already_handled", name: follow_request.requester.name)
      end
    else
      flash[:alert] = t(".no_permission")
    end

  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t(".not_found")
  ensure
    redirect_to connections_followers_path
  end

  def follow
    if FollowRequestHandler.create_friendship_or_request!(current_user, requestee)
      redirect_to params[:redirect]
    else
      render nothing: true, status: 409
    end
  end

  def approve
    follow_request = FollowRequest.find(params[:follow_request_id])

    if can?(:manage, follow_request)
      if follow_request.pending?
        FollowRequestHandler.approve!(follow_request)
        flash[:notice] = t(".approved", name: follow_request.requester.name)
      else
        flash[:notice] = t(".already_handled", name: follow_request.requester.name)
      end
    else
      flash[:alert] = t(".no_permission")
    end

  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t(".not_found")
  ensure
    redirect_to connections_followers_path
  end

  private

  def requestee
    @requestee ||= User.find(params[:requestee_id])
  end

  def partial
    if FriendshipsController::ALLOWED_PARTIALS.include? params[:partial]
      "shared/#{params[:partial]}"
    else
      "shared/follow_options_link"
    end
  end

  def approved_request?
    params[:approved] == "true"
  end
end
