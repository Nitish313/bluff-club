# Runs every hour (config/recurring.yml). A closed room cannot be joined any more.
class CloseIdleRoomsJob < ApplicationJob
  IDLE_AFTER = 2.hours

  def perform
    Room.where(last_activity_at: ...IDLE_AFTER.ago).where.not(status: "closed").update_all(status: "closed")
  end
end
