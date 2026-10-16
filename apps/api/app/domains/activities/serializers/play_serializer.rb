module Activities
  module Serializers
    class PlaySerializer
      def self.call(activity_version)
        snapshot = activity_version.question_snapshot

        {
          id: activity_version.id,
          title: activity_version.activity.title,
          share_code: activity_version.share_code,
          questions: snapshot.map do |question|
            {
              id: question.fetch("id"),
              prompt: question.fetch("prompt"),
              points: question.fetch("points"),
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
          results: snapshot.map do |question|
            response = responses.fetch(question.fetch("id"))
            {
              question_id: question.fetch("id"),
              prompt: question.fetch("prompt"),
              selected_option_id: response.fetch("option_id"),
              correct_option_id: question.fetch("correct_option_id"),
              points_awarded: Questions::Types::SingleChoice.score(
                question: question,
                selected_option_id: response.fetch("option_id")
              ),
              points_possible: question.fetch("points")
            }
          end
        }
      end
    end
  end
end
