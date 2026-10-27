class HostMigrationJob < ApplicationJob
  queue_as :default

  def perform(room_id, old_host_id)
    room = Room.find_by(id: room_id)
    return if room.nil?
    Game::Presence.migrate_host(room, old_host_id)
    Game::Broadcast.call(room)
  end
end
