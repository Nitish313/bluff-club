require "rails_helper"

RSpec.describe Game::PlayAgain do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let!(:gone) { Game::JoinRoom.call(code: room.code, name: "Gone").last }

  before do
    round = room.rounds.create!(position: 0, question: "Q", answer: "T")
    bluff = round.bluffs.create!(player: gone, text: "x", normalized: "x")
    round.votes.create!(player: host, bluff: bluff)
    round.votes.create!(player: guest, bluff: nil)
    room.players.update_all(score: 500)
    guest.update!(spectator: true)
    gone.update!(connected: false)
    room.update!(status: "finished")
  end

  it "resets the room to the lobby" do
    described_class.call(room: room, player: host)
    expect(room.reload).to be_lobby
    expect(room.rounds.count).to eq(0)
    expect(room.players.pluck(:score)).to all(eq(0))
    expect(guest.reload).not_to be_spectator
  end

  it "drops players who left" do
    described_class.call(room: room, player: host)
    expect(room.players.pluck(:name)).to match_array(%w[Host Guest])
  end

  it "only the host can restart" do
    expect { described_class.call(room: room, player: guest) }.to raise_error(Game::Error, /host/i)
  end

  it "refuses while a game is running" do
    room.update!(status: "voting")
    expect { described_class.call(room: room, player: host) }.to raise_error(Game::Error, /running/i)
  end
end
