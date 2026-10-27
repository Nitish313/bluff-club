class RoomsController < ApplicationController
  def create
    room, player = Game::CreateRoom.call(name: params[:name])
    render json: { code: room.code, token: player.token, player_id: player.id }
  rescue Game::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
