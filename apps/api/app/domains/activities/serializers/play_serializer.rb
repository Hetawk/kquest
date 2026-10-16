module Activities
  module Serializers
    class PlaySerializer
      def self.call(activity_version)
        snapshot = activity_version.question_snapshot

        {
          id: activity_version.id,
          title: activity_version.activity.title,
          cover_image_url: activity_version.cover_image_url,
          share_code: activity_version.share_code,
          questions: snapshot.map do |question|
            {
              id: question.fetch("id"),
              prompt: question.fetch("prompt"),
              points: question.fetch("points"),
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
            correct = response.fetch("option_id") == question.fetch("correct_option_id")
            {
              question_id: question.fetch("id"),
              prompt: question.fetch("prompt"),
              selected_option_id: response.fetch("option_id"),
              correct_option_id: question.fetch("correct_option_id"),
              timed_out: response.fetch("option_id").nil?,
              points_awarded: response["points_awarded"] ||
                Questions::Types::SingleChoice.score(
                  question: question,
                  selected_option_id: response.fetch("option_id")
                ),
              speed_bonus: response.fetch("speed_bonus", 0),
              response_time_ms: response["response_time_ms"],
              points_possible: Questions::Types::SingleChoice.maximum_points(question),
              base_points: question.fetch("points"),
              correct: correct
            }
          end
        }
      end
    end
  end
end
