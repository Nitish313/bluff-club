class QuestionsController < ApplicationController
  def create
    room = Room.find_by(code: params[:code].to_s.upcase)
    player = room&.players&.find_by(token: params[:token].to_s)
    raise Game::Error, "Room not found" if player.nil?
    raise Game::Error, "Only the host can do that" unless room.host?(player)
    raise Game::Error, "You can only make questions in the lobby" if room.in_game?

    render json: { questions: Game::GenerateQuestions.call(topic: params[:topic]) }
  rescue Game::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
