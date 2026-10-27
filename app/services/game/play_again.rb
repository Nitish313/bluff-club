module Game
  class PlayAgain
    def self.call(room:, player:)
      raise Game::Error, "Only the host can restart" unless room.host?(player)
      raise Game::Error, "Game is still running" unless room.finished? || room.lobby?

      Room.transaction do
        room.rounds.destroy_all
        room.players.where(connected: false).destroy_all
        room.players.update_all(score: 0, spectator: false)
        room.update!(status: "lobby", current_round_index: 0, phase_token: nil, phase_ends_at: nil,
          last_activity_at: Time.current)
      end
    end
  end
end
