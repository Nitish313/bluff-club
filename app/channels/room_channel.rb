class RoomChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find_by(code: params[:code].to_s.upcase)
    @player = @room&.players&.find_by(token: params[:token].to_s)
    return reject if @player.nil? || @room.closed?

    stream_for @room
    Game::Presence.connected(@player)
    transmit(hello)
    Game::Broadcast.call(@room)
  end

  def unsubscribed
    return if @player.nil?
    Game::Presence.disconnected(@player)
    Game::Broadcast.call(@room)
  end

  def start_game(data)
    run do
      Game::Start.call(room: room, player: player, pack: data["pack"], question_count: data["question_count"],
        custom_questions: data["custom_questions"])
    end
  end

  def submit_bluff(data)
    run do
      bluff = Game::SubmitBluff.call(room: room, player: player, text: data["text"])
      transmit({ type: "bluff_ok", text: bluff.text })
    end
  end

  def submit_vote(data)
    run { Game::SubmitVote.call(room: room, player: player, option_index: data["index"]) }
  end

  def next_round
    run { Game::Advance.skip(room, player) }
  end

  def play_again
    run { Game::PlayAgain.call(room: room, player: player) }
  end

  # Backup for the timer job: a browser whose countdown hit zero asks the server to check.
  def tick
    run do
      r = room
      Game::Advance.on_timeout(r, r.phase_token) if r.phase_ends_at && r.phase_ends_at <= Time.current
    end
  end

  private

  def room = @room.reload
  def player = @player.reload

  def run
    yield
    Game::Broadcast.call(@room)
  rescue Game::Error => e
    transmit({ type: "error", message: e.message })
  end

  def hello
    bluff = @room.in_game? ? @room.current_round&.bluffs&.find_by(player_id: @player.id) : nil
    { type: "hello", player_id: @player.id, my_bluff: bluff&.text }
  end
end
