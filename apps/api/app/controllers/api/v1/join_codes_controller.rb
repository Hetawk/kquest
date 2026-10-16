module Api
  module V1
    class JoinCodesController < ApplicationController
      def show
        code = params[:code].to_s.upcase
        return render_not_found unless ActivityVersion::CODE_REGEX.match?(code)

        room = GameRoom.find_by(room_code: code)
        if room
          return render json: { data: { kind: "live_room", path: "/room/#{room.room_code}" } }
        end

        version = ActivityVersion.find_by(share_code: code)
        return render_not_found unless version

        render json: { data: { kind: "self_paced", path: "/play/#{version.share_code}" } }
      end
    end
  end
end
