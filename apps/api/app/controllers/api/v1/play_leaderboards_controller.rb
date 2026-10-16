module Api
  module V1
    class PlayLeaderboardsController < ApplicationController
      before_action :prototype_api_only?

      def show
        activity_version = ActivityVersion.find_by(share_code: normalized_share_code)
        return render_not_found unless activity_version

        attempts = activity_version.attempts.where(game_room_id: nil)
          .order(score: :desc, total_response_time_ms: :asc)
          .order(Arel.sql("LOWER(learner_name) ASC"), :id)
        render json: {
          data: {
            status: "provisional",
            participant_count: attempts.count,
            podium: attempts.limit(3).map.with_index do |attempt, index|
              entry(attempt, index + 1)
            end,
            standings: attempts.limit(20).map.with_index do |attempt, index|
              entry(attempt, index + 1)
            end
          }
        }
      end

      private

      def normalized_share_code
        code = params[:share_code].to_s.upcase
        code if ActivityVersion::CODE_REGEX.match?(code)
      end

      def entry(attempt, rank)
        {
          rank: rank,
          learner_name: attempt.learner_name,
          score: attempt.score,
          max_score: attempt.max_score,
          response_time_ms: attempt.total_response_time_ms
        }
      end
    end
  end
end
