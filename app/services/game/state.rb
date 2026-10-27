module Game
  class State
    def self.call(room) = new(room).to_h

    def initialize(room)
      @room = room
      @round = room.current_round if room.in_game?
    end

    def to_h
      {
        code: @room.code,
        status: @room.status,
        host_id: @room.host_player_id,
        settings: { pack: @room.pack, question_count: @room.question_count },
        packs: Game::Packs.summary,
        ai_enabled: Game::GenerateQuestions.enabled?,
        players: players,
        round: round_payload,
        all_done: Game::Advance.all_done?(@room),
        reveal: reveal_payload,
        server_time: Time.current.iso8601(3)
      }
    end

    private

    def players
      @room.players.order(:id).map do |p|
        { id: p.id, name: p.name, score: p.score, connected: p.connected, spectator: p.spectator,
          done: done_ids.include?(p.id) }
      end
    end

    def done_ids
      @done_ids ||= if @round.nil? then []
      elsif @room.writing? then @round.bluffs.pluck(:player_id)
      elsif @room.voting? then @round.votes.pluck(:player_id)
      else []
      end
    end

    def round_payload
      return nil if @round.nil?
      h = { index: @room.current_round_index, total: @room.rounds.count, question: @round.question,
        phase_ends_at: @room.phase_ends_at&.iso8601(3) }
      h[:options] = Game::Options.for(@round).map.with_index { |o, i| { index: i, text: o[:text] } } if @room.voting?
      h
    end

    def reveal_payload
      return nil unless @room.reveal? && @round
      votes = @round.votes.includes(:player).to_a
      options = Game::Options.for(@round).map do |o|
        bluff = o[:bluff]
        voters = votes.select { |v| v.bluff_id == bluff&.id }.map { |v| v.player.name }
        per_vote = bluff ? Game::Score::FOOL_POINTS : Game::Score::TRUTH_POINTS
        { text: o[:text], truth: bluff.nil?, author: bluff&.player&.name, voters: voters,
          points: voters.size * per_vote }
      end
      { answer: @round.answer, options: options }
    end
  end
end
