module Api
  module V1
    class PublicationsController < ApplicationController
      before_action :require_current_user

      def create
        return unless current_user

        activity = current_user.activities.find_by(id: params[:activity_id])
        return render_not_found unless activity

        version = Activities::Services::PublishActivity.call(activity: activity)

        render(
          json: {
            data: {
              title: activity.title,
              activity_id: activity.id,
              version: version.version_number,
              share_code: version.share_code,
              play_path: "/play/#{version.share_code}"
            }
          },
          status: :created
        )
      rescue ActiveRecord::RecordInvalid => error
        render_validation_error(error.record)
      end
    end
  end
end
