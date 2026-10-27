module Game
  module Broadcast
    # Send the full room state to every browser in the room.
    def self.call(room)
      room.reload
      RoomChannel.broadcast_to(room, Game::State.call(room))
    end
  end
end
