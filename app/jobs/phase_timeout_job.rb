class PhaseTimeoutJob < ApplicationJob
  queue_as :default

  def perform(room_id, token)
    room = Room.find_by(id: room_id)
    return if room.nil?
    Game::Broadcast.call(room) if Game::Advance.on_timeout(room, token)
  end
end
