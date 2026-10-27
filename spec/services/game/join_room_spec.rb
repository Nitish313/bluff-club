require "rails_helper"

RSpec.describe Game::JoinRoom do
  let!(:room) { Game::CreateRoom.call(name: "Host").first }

  it "joins with the code in any case" do
    joined, player = described_class.call(code: room.code.downcase, name: "Aman")
    expect(joined).to eq(room)
    expect(player.name).to eq("Aman")
    expect(player).not_to be_spectator
  end

  it "rejects an unknown code" do
    expect { described_class.call(code: "ZZZZ", name: "Aman") }.to raise_error(Game::Error, /not found/i)
  end

  it "rejects a closed room" do
    room.update!(status: "closed")
    expect { described_class.call(code: room.code, name: "Aman") }.to raise_error(Game::Error, /not found/i)
  end

  it "rejects a name already used in the room, ignoring case" do
    expect { described_class.call(code: room.code, name: "host") }.to raise_error(Game::Error, /taken/i)
  end

  it "rejects the 13th player" do
    11.times { |i| described_class.call(code: room.code, name: "P#{i}") }
    expect { described_class.call(code: room.code, name: "Late") }.to raise_error(Game::Error, /full/i)
  end

  it "makes a spectator when the game is running" do
    room.update!(status: "writing")
    _, player = described_class.call(code: room.code, name: "Late")
    expect(player).to be_spectator
  end
end
