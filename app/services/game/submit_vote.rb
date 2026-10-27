module Game
  class SubmitVote
    def self.call(room:, player:, option_index:)
      raise Game::Error, "Not the voting phase" unless room.voting?
      raise Game::Error, "You are watching this game. You can play the next one." if player.spectator?

      round = room.current_round
      index = option_index.to_i
      option = index.negative? ? nil : Game::Options.for(round)[index]
      raise Game::Error, "Pick an answer from the list" if option.nil?
      raise Game::Error, "That is your own bluff!" if option[:bluff]&.player_id == player.id
      raise Game::Error, "You already voted" if round.votes.exists?(player_id: player.id)

      vote = round.votes.create!(player: player, bluff: option[:bluff])
      Game::Advance.maybe_finish_phase(room)
      vote
    end
  end
end
