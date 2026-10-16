module Api
  module V1
    class PublicationsController < ApplicationController
      def create
        return unless prototype_api_only?

        activity = Activity.find_by(id: params[:activity_id])
        return render_not_found unless activity

        version = Activities::Services::PublishActivity.call(activity: activity)

        render(
          json: {
            data: {
              title: activity.title,
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
