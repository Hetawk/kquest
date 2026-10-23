module Api
  module V1
    class GameRoomsController < ApplicationController
      before_action :require_current_user, only: %i[create start advance expire report]

      def create
        return unless current_user

        activity = current_user.activities.find_by(id: params[:activity_id], status: "published")
        return render_not_found unless activity

        version = activity.activity_versions.order(version_number: :desc).first
        return render_not_found unless version

        room = GameRoom.create!(activity_version: version, host_user: current_user)
        render json: {
          data: Activities::Serializers::GameRoomSerializer.call(room, include_participant_keys: true)
        }, status: :created
      rescue ActiveRecord::RecordInvalid => error
        render_validation_error(error.record)
      end

      def show
        room = GameRoom.includes(:activity_version, :play_sessions).find_by(room_code: normalized_room_code)
        return render_not_found unless room

        participant = room.play_sessions.find_by(id: params[:session_id]) if params[:session_id].present?
        return render_not_found if params[:session_id].present? && !participant

        render json: {
          data: Activities::Serializers::GameRoomSerializer.call(
            room,
            participant_session: participant,
            include_participant_keys: room.host_user_id == current_user&.id
          )
        }
      end

      def join
        room = GameRoom.includes(:activity_version).find_by(room_code: normalized_room_code)
        return render_not_found unless room

        attributes = params.require(:participant).permit(:learner_name, :avatar_id)
        avatar_id = attributes[:avatar_id].presence || PlaySession::DEFAULT_AVATAR_ID
        return render_invalid_avatar unless PlaySession::AVATAR_IDS.include?(avatar_id)

        session, repeated = Assessments::Services::StartPlaySession.call(
          activity_version: room.activity_version,
          learner_name: attributes[:learner_name],
          start_key: request.headers["Idempotency-Key"],
          game_room: room,
          avatar_id:
        )
        render(
          json: { data: {
            session_id: session.id,
            learner_name: session.learner_name,
            avatar_id: session.avatar_id,
            room: Activities::Serializers::GameRoomSerializer.call(room, participant_session: session)
          } },
          status: repeated ? :ok : :created
        )
      rescue Assessments::Services::StartPlaySession::IdempotencyConflict
        render_error(
          code: "invalid_game_join",
          message: "Enter a valid name and join while the host is accepting players.",
          status: :unprocessable_entity
        )
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "A learner name is required.",
          status: :unprocessable_entity
        )
      end

      def update
        room = GameRoom.find_by(room_code: normalized_room_code)
        return render_not_found unless room

        session = room.play_sessions.find_by(id: params[:session_id])
        return render_not_found unless session
        attributes = params.require(:participant).permit(:learner_name, :avatar_id)
        return render_error(code: "validation_failed", message: "Choose a name or character to update.", status: :unprocessable_entity) if attributes.empty?

        if attributes.key?(:learner_name)
          return render_error(code: "name_locked", message: "Your name cannot be changed after you answer this round.", status: :conflict) if session.responses.any? { |response| response["question_id"] == room.activity_version.question_snapshot[room.current_question_index]&.fetch("id") }

          name = attributes[:learner_name].to_s.strip
          return render_error(code: "invalid_name", message: "Choose a name between 1 and 80 characters.", status: :unprocessable_entity) unless name.length.between?(1, 80)

          session.learner_name = name
        end
        if attributes.key?(:avatar_id)
          return render_invalid_avatar unless PlaySession::AVATAR_IDS.include?(attributes[:avatar_id])

          session.avatar_id = attributes[:avatar_id]
        end

        session.save!
        render json: { data: { learner_name: session.learner_name, avatar_id: session.avatar_id } }
      rescue ActionController::ParameterMissing
        render_error(code: "validation_failed", message: "A learner name is required.", status: :unprocessable_entity)
      end

      def start
        room = find_host_room
        return unless room

        room = Assessments::Services::AdvanceGameRoom.start!(room: room)
        render json: {
          data: Activities::Serializers::GameRoomSerializer.call(room, include_participant_keys: true)
        }
      rescue Assessments::Services::AdvanceGameRoom::InvalidTransition
        render_room_transition_error
      end

      def advance
        room = find_host_room
        return unless room

        requested_index = params[:question_index]
        question_index = if requested_index.nil?
          nil
        elsif requested_index.to_s.match?(/\A\d+\z/)
          requested_index.to_i
        else
          raise Assessments::Services::AdvanceGameRoom::InvalidTransition
        end
        room = Assessments::Services::AdvanceGameRoom.next!(room: room, question_index: question_index)
        render json: {
          data: Activities::Serializers::GameRoomSerializer.call(room, include_participant_keys: true)
        }
      rescue Assessments::Services::AdvanceGameRoom::InvalidTransition
        render_room_transition_error
      end

      def expire
        room = find_host_room
        return unless room

        room = Assessments::Services::AdvanceGameRoom.expire!(room:)
        render json: {
          data: Activities::Serializers::GameRoomSerializer.call(room, include_participant_keys: true)
        }
      rescue Assessments::Services::AdvanceGameRoom::QuestionNotExpired
        render_error(
          code: "question_not_expired",
          message: "The shared question timer has not expired yet.",
          status: :conflict
        )
      rescue Assessments::Services::AdvanceGameRoom::InvalidTransition
        render_room_transition_error
      end

      def report
        room = find_host_room
        return unless room
        return render_room_transition_error unless room.status == "completed"

        render json: { data: Activities::Serializers::GameRoomReportSerializer.call(room) }
      end

      def answer
        room = GameRoom.find_by(room_code: normalized_room_code)
        return render_not_found unless room

        session = room.play_sessions.find_by(id: params[:session_id])
        return render_not_found unless session

        attributes = params.require(:answer).permit(:question_id, :option_id, option_ids: [])
        result = Assessments::Services::AdvanceGameRoomAnswer.call(
          session: session,
          question_id: attributes[:question_id],
          option_id: attributes[:option_id],
          option_ids: attributes[:option_ids],
          request_key: request.headers["Idempotency-Key"]
        )
        render json: { data: result }
      rescue Assessments::Services::AdvanceGameRoomAnswer::QuestionNotExpired
        render_error(code: "question_not_expired", message: "Choose an answer before time runs out.", status: :conflict)
      rescue Assessments::Services::AdvanceGameRoomAnswer::IdempotencyConflict
        render_error(
          code: "idempotency_conflict",
          message: "This answer request key was already used for a different response.",
          status: :conflict
        )
      rescue Assessments::Services::AdvanceGameRoomAnswer::InvalidAnswer
        render_error(code: "invalid_answer", message: "This question can no longer accept that answer.", status: :unprocessable_entity)
      rescue ActionController::ParameterMissing
        render_error(code: "validation_failed", message: "A question identifier is required.", status: :unprocessable_entity)
      end

      private

      def normalized_room_code
        code = params[:room_code].to_s.upcase
        code if ActivityVersion::CODE_REGEX.match?(code)
      end

      def find_host_room
        return unless current_user

        room = current_user.game_rooms.find_by(room_code: normalized_room_code)
        return room if room

        render_not_found
      end

      def render_room_transition_error
        render_error(
          code: "invalid_room_transition",
          message: "The room is no longer in a state that allows this action.",
          status: :conflict
        )
      end

      def render_invalid_avatar
        render_error(
          code: "invalid_avatar",
          message: "Choose one of the available learner characters.",
          status: :unprocessable_entity
        )
      end
    end
  end
end
