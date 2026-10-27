require "rails_helper"

RSpec.describe Room do
  let(:room) { Room.create!(code: "ABCD") }

  it "starts in the lobby" do
    expect(room).to be_lobby
    expect(room).not_to be_in_game
  end

  it "knows the host" do
    host = room.players.create!(name: "Nitish", token: "t1")
    other = room.players.create!(name: "Aman", token: "t2")
    room.update!(host_player_id: host.id)
    expect(room.host?(host)).to be true
    expect(room.host?(other)).to be false
  end

  it "returns the current round by position" do
    r0 = room.rounds.create!(position: 0, question: "Q0", answer: "A0")
    r1 = room.rounds.create!(position: 1, question: "Q1", answer: "A1")
    expect(room.current_round).to eq(r0)
    room.update!(current_round_index: 1)
    expect(room.current_round).to eq(r1)
  end

  it "lists active players: connected and not spectators" do
    a = room.players.create!(name: "A", token: "a")
    room.players.create!(name: "B", token: "b", connected: false)
    room.players.create!(name: "C", token: "c", spectator: true)
    expect(room.active_players).to eq([a])
  end

  it "rejects a bad status" do
    expect { room.update!(status: "sleeping") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
