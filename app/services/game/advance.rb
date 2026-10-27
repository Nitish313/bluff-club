module Game
  class Advance
    DURATIONS = { "writing" => 60, "voting" => 30, "reveal" => 10 }.freeze

    # Put the room into a phase, set the deadline, and queue the timer.
    def self.enter(room, status)
      token = SecureRandom.hex(8)
      seconds = DURATIONS.fetch(status)
      room.update!(status: status, phase_token: token, phase_ends_at: seconds.seconds.from_now,
        last_activity_at: Time.current)
      PhaseTimeoutJob.set(wait: seconds.seconds).perform_later(room.id, token)
    end

    # Called by the timer job. The token check stops an old timer from acting twice.
    def self.on_timeout(room, token)
      room.with_lock do
        return false unless room.in_game? && room.phase_token == token
        next_phase(room)
        true
      end
    end

    # Called after every bluff or vote. Ends the phase early when everyone online is done.
    def self.maybe_finish_phase(room)
      room.with_lock do
        return false unless room.writing? || room.voting?
        players = room.active_players.to_a
        return false if players.empty?
        return false unless players.all? { |p| done?(room, p) }
        next_phase(room)
        true
      end
    end

    # Host presses "Next" during the reveal.
    def self.skip(room, player)
      raise Game::Error, "Only the host can do that" unless room.host?(player)
      room.with_lock do
        return false unless room.reveal?
        next_phase(room)
        true
      end
    end

    def self.done?(room, player)
      round = room.current_round
      return false if round.nil?
      if room.writing?
        round.bluffs.exists?(player_id: player.id)
      else
        round.votes.exists?(player_id: player.id)
      end
    end

    def self.next_phase(room)
      case room.status
      when "writing"
        enter(room, "voting")
      when "voting"
        Game::Score.call(room.current_round)
        enter(room, "reveal")
      when "reveal"
        if room.current_round_index + 1 >= room.rounds.count
          room.update!(status: "finished", phase_token: nil, phase_ends_at: nil)
        else
          room.update!(current_round_index: room.current_round_index + 1)
          enter(room, "writing")
        end
      end
    end
  end
end
