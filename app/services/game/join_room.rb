module Game
  class JoinRoom
    MAX_PLAYERS = 12
    NAME_MAX = 16

    def self.clean_name(raw)
      name = raw.to_s.strip.squeeze(" ")
      raise Game::Error, "Please enter a name" if name.empty?
      raise Game::Error, "Name must be #{NAME_MAX} letters or fewer" if name.length > NAME_MAX
      name
    end

    def self.call(code:, name:) = new(code, name).call

    def initialize(code, name)
      @code = code.to_s.upcase.strip
      @name = name
    end

    def call
      name = self.class.clean_name(@name)
      room = Room.find_by(code: @code)
      raise Game::Error, "Room not found. Check the code." if room.nil? || room.closed?

      room.with_lock do
        raise Game::Error, "Room is full (#{MAX_PLAYERS} players max)" if room.players.count >= MAX_PLAYERS
        raise Game::Error, "That name is taken in this room" if room.players.any? { |p| p.name.casecmp?(name) }

        player = room.players.create!(name: name, token: SecureRandom.hex(16), spectator: room.in_game?)
        room.update!(last_activity_at: Time.current)
        [room, player]
      end
    end
  end
end
