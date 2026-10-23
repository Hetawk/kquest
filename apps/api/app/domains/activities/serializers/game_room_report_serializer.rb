module Activities
  module Serializers
    class GameRoomReportSerializer
      def self.call(room)
        snapshot = room.activity_version.question_snapshot
        sessions = room.play_sessions.to_a
        attempts = Attempt.where(
          game_room_id: room.id,
          submission_key: sessions.map(&:submission_key)
        ).index_by(&:submission_key)
        participants = sessions.map do |session|
          attempt = attempts.fetch(session.submission_key)
          responses = session.responses.index_by { |response| response.fetch("question_id") }
          {
            session: session,
            attempt: attempt,
            responses: responses
          }
        end.sort_by do |participant|
          [
            -participant.fetch(:attempt).score,
            participant.fetch(:attempt).total_response_time_ms,
            participant.fetch(:session).learner_name.downcase,
            participant.fetch(:session).id
          ]
        end

        questions = snapshot.each_with_index.map do |question, index|
          correct_option_ids = question.fetch(
            "correct_option_ids",
            [ question.fetch("correct_option_id") ]
          )
          question_results = participants.map do |participant|
            response = participant.fetch(:responses).fetch(question.fetch("id"))
            selected_option_ids = selected_ids(response, question)
            {
              selected_answer: answer_text(question, selected_option_ids),
              is_correct: selected_option_ids.sort == correct_option_ids.sort,
              timed_out: selected_option_ids.empty?,
              points_awarded: response.fetch("points_awarded"),
              response_time_ms: response["response_time_ms"]
            }
          end
          correct_count = question_results.count { |result| result.fetch(:is_correct) }
          timed_out_count = question_results.count { |result| result.fetch(:timed_out) }
          answered_count = participants.length - timed_out_count

          {
            id: question.fetch("id"),
            number: index + 1,
            prompt: question.fetch("prompt"),
            points_possible: question.fetch("points"),
            correct_answer: answer_text(question, correct_option_ids),
            participant_count: participants.length,
            answered_count: answered_count,
            correct_count: correct_count,
            missed_count: answered_count - correct_count,
            timed_out_count: timed_out_count,
            accuracy_percent: percentage(correct_count, participants.length)
          }
        end

        participant_rows = participants.each_with_index.map do |participant, index|
          session = participant.fetch(:session)
          attempt = participant.fetch(:attempt)
          {
            learner_name: session.learner_name,
            avatar_id: session.avatar_id,
            rank: index + 1,
            score: attempt.score,
            max_score: attempt.max_score,
            questions: snapshot.map do |question|
              response = participant.fetch(:responses).fetch(question.fetch("id"))
              selected_option_ids = selected_ids(response, question)
              {
                question_id: question.fetch("id"),
                selected_answer: answer_text(question, selected_option_ids),
                correct_answer: answer_text(
                  question,
                  question.fetch("correct_option_ids", [ question.fetch("correct_option_id") ])
                ),
                is_correct: selected_option_ids.sort ==
                  question.fetch("correct_option_ids", [ question.fetch("correct_option_id") ]).sort,
                timed_out: selected_option_ids.empty?,
                points_awarded: response.fetch("points_awarded"),
                points_possible: question.fetch("points"),
                response_time_ms: response["response_time_ms"]
              }
            end
          }
        end
        total_correct = questions.sum { |question| question.fetch(:correct_count) }
        total_responses = participants.length * questions.length

        {
          room_code: room.room_code,
          title: room.activity_version.title,
          completed_at: room.ended_at&.iso8601(6),
          participant_count: participants.length,
          question_count: questions.length,
          average_score: participants.empty? ? 0 :
            (participants.sum { |participant| participant.fetch(:attempt).score }.to_f / participants.length).round,
          max_score: participants.first&.fetch(:attempt)&.max_score || 0,
          accuracy_percent: percentage(total_correct, total_responses),
          questions: questions,
          participants: participant_rows
        }
      end

      def self.selected_ids(response, question)
        if question.fetch("question_type", "single_choice") == "multiple_select"
          response.fetch("option_ids", [])
        else
          [ response["option_id"] ].compact
        end
      end
      private_class_method :selected_ids

      def self.answer_text(question, option_ids)
        options = question.fetch("options").index_by { |option| option.fetch("id") }
        option_ids.filter_map { |id| options[id]&.fetch("text") }.join("; ")
      end
      private_class_method :answer_text

      def self.percentage(numerator, denominator)
        return 0 if denominator.zero?

        (numerator.to_f * 100 / denominator).round
      end
      private_class_method :percentage
    end
  end
end
