module Questions
  module Types
    class Scoring
      def self.score_with_speed(question:, correct:, elapsed_seconds:)
        return { points_awarded: 0, speed_bonus: 0 } unless correct

        base_points = question.fetch("points")
        return { points_awarded: base_points, speed_bonus: 0 } unless question.fetch("speed_scoring", false)

        time_limit = SingleChoice.live_time_limit_seconds(question)

        remaining_ratio = (1 - (elapsed_seconds.to_f / time_limit)).clamp(0.0, 1.0)
        maximum_bonus = question.fetch("speed_bonus_points", base_points)
        bonus = (maximum_bonus * remaining_ratio).round
        { points_awarded: base_points + bonus, speed_bonus: bonus }
      end
    end
  end
end
