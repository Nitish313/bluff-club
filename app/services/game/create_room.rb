module Game
  class CreateRoom
    def self.call(name:)
      player_name = Game::JoinRoom.clean_name(name)
      Room.transaction do
        room = Room.create!(code: Game::CodeGenerator.unique, last_activity_at: Time.current)
        player = room.players.create!(name: player_name, token: SecureRandom.hex(16))
        room.update!(host_player_id: player.id)
        [room, player]
      end
    end
  end
end
