class PurgeExpiredPlaySessionsJob < ApplicationJob
  queue_as :low

  def perform
    PlaySession.where("expires_at < ?", 1.day.ago).delete_all
  end
end
