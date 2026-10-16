module Questions
  module Types
    class Scoring
      def self.score_with_speed(question:, correct:, elapsed_seconds:)
        return { points_awarded: 0, speed_bonus: 0 } unless correct

        base_points = question.fetch("points")
        return { points_awarded: base_points, speed_bonus: 0 } unless question.fetch("speed_scoring", false)

        time_limit = question.fetch("time_limit_seconds", SingleChoice::DEFAULT_TIME_LIMIT_SECONDS)
        return { points_awarded: base_points, speed_bonus: 0 } unless time_limit.positive?

        remaining_ratio = [ 1 - (elapsed_seconds.to_f / time_limit), 0 ].max
        bonus = (base_points * remaining_ratio).round
        { points_awarded: base_points + bonus, speed_bonus: bonus }
      end
    end
  end
end
