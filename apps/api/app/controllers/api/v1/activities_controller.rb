module Api
  module V1
    class ActivitiesController < ApplicationController
      def create
        return unless prototype_api_only?

        attributes = params.require(:activity).permit(
          :title,
          :description,
          questions: [ :prompt, :correct_option_id, :points, { options: [ :id, :text ] } ]
        )
        question_definitions = attributes.delete(:questions) || []

        activity = Activity.new(title: attributes[:title], description: attributes[:description])
        question_definitions.each_with_index do |definition, index|
          activity.questions.build(
            position: index + 1,
            question_type: "single_choice",
            prompt: definition[:prompt],
            options: definition[:options]&.map(&:to_h),
            correct_option_id: definition[:correct_option_id],
            points: definition[:points]
          )
        end

        if activity.save
          render(
            json: {
              data: {
                id: activity.id,
                title: activity.title,
                description: activity.description,
                question_count: activity.questions.size,
                status: activity.status
              }
            },
            status: :created
          )
        else
          render_validation_error(activity)
        end
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "The submitted data is invalid.",
          status: :unprocessable_entity,
          details: { activity: [ { code: "required", message: "Activity details are required." } ] }
        )
      end
    end
  end
end
