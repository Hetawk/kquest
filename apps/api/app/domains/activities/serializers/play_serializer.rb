module Activities
  module Serializers
    class PlaySerializer
      def self.call(activity_version)
        snapshot = activity_version.question_snapshot

        {
          id: activity_version.id,
          title: activity_version.title,
          cover_image_url: activity_version.cover_image_url,
          share_code: activity_version.share_code,
          questions: snapshot.map do |question|
            {
              id: question.fetch("id"),
              prompt: question.fetch("prompt"),
              question_type: question.fetch("question_type", "single_choice"),
              points: question.fetch("points"),
              speed_bonus_points: question.fetch("speed_bonus_points", question.fetch("points")),
              speed_scoring: question.fetch("speed_scoring", false),
              time_limit_seconds: question.fetch("time_limit_seconds", 30),
              options: question.fetch("options").map do |option|
                { id: option.fetch("id"), text: option.fetch("text") }
              end
            }
          end
        }
      end

      def self.result(attempt)
        snapshot = attempt.activity_version.question_snapshot
        responses = attempt.responses.index_by { |response| response.fetch("question_id") }

        {
          id: attempt.id,
          learner_name: attempt.learner_name,
          score: attempt.score,
          max_score: attempt.max_score,
          total_response_time_ms: attempt.responses.sum { |response| response["response_time_ms"].to_i },
          results: snapshot.map do |question|
            response = responses.fetch(question.fetch("id"))
            multiple_select = question.fetch("question_type", "single_choice") == "multiple_select"
            selected_option_ids = response.fetch("option_ids", [])
            correct_option_ids = question.fetch("correct_option_ids", [ question.fetch("correct_option_id") ])
            correct = if multiple_select
              selected_option_ids.sort == correct_option_ids.sort
            else
              response.fetch("option_id") == question.fetch("correct_option_id")
            end
            result = {
              question_id: question.fetch("id"),
              prompt: question.fetch("prompt"),
              timed_out: multiple_select ? selected_option_ids.empty? : response.fetch("option_id").nil?,
              points_awarded: response.fetch("points_awarded"),
              speed_bonus: response.fetch("speed_bonus", 0),
              response_time_ms: response["response_time_ms"],
              points_possible: Questions::Types::SingleChoice.maximum_points(question),
              base_points: question.fetch("points"),
              correct: correct
            }
            if multiple_select
              result[:selected_option_ids] = selected_option_ids
              result[:correct_option_ids] = correct_option_ids
            else
              result[:selected_option_id] = response.fetch("option_id")
              result[:correct_option_id] = question.fetch("correct_option_id")
            end
            result
          end
        }
      end
    end
  end
end
