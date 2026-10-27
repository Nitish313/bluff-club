require "rails_helper"

RSpec.describe Game::CreateRoom do
  it "makes a room with the creator as host" do
    room, player = described_class.call(name: " Nitish ")
    expect(room.code).to match(/\A[A-Z]{4}\z/)
    expect(room).to be_lobby
    expect(player.name).to eq("Nitish")
    expect(room.host?(player)).to be true
    expect(player.token).to be_present
  end

  it "rejects an empty name" do
    expect { described_class.call(name: "   ") }.to raise_error(Game::Error, /name/i)
  end

  it "rejects a long name" do
    expect { described_class.call(name: "a" * 17) }.to raise_error(Game::Error, /16/)
  end
end
