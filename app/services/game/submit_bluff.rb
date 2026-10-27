module Game
  class SubmitBluff
    MAX_LENGTH = 60

    def self.call(room:, player:, text:)
      raise Game::Error, "Not the writing phase" unless room.writing?
      raise Game::Error, "You are watching this game. You can play the next one." if player.spectator?

      text = text.to_s.strip.squeeze(" ")
      raise Game::Error, "Type an answer first" if text.empty?
      raise Game::Error, "Keep it under #{MAX_LENGTH} characters" if text.length > MAX_LENGTH

      round = room.current_round
      norm = Game::Text.normalize(text)
      raise Game::Error, "Too close to the real answer. Try another." if norm == Game::Text.normalize(round.answer)
      if round.bluffs.where(normalized: norm).where.not(player_id: player.id).exists?
        raise Game::Error, "Someone already wrote that. Try another."
      end

      bluff = round.bluffs.find_or_initialize_by(player_id: player.id)
      bluff.update!(text: text, normalized: norm)
      Game::Advance.maybe_finish_phase(room)
      bluff
    end
  end
end
