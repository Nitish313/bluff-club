require "rails_helper"

RSpec.describe Game::SubmitBluff do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  before do
    room.rounds.create!(position: 0, question: "Capital of Australia?", answer: "Canberra")
    Game::Advance.enter(room, "writing")
  end

  it "saves the bluff" do
    bluff = described_class.call(room: room, player: host, text: "  Sydney ")
    expect(bluff.text).to eq("Sydney")
    expect(bluff.normalized).to eq("sydney")
  end

  it "lets a player change their bluff before time is up" do
    described_class.call(room: room, player: host, text: "Sydney")
    described_class.call(room: room, player: host, text: "Perth")
    expect(room.current_round.bluffs.where(player: host).pluck(:text)).to eq(["Perth"])
  end

  it "rejects the real answer" do
    expect { described_class.call(room: room, player: host, text: "the canberra!") }
      .to raise_error(Game::Error, /too close/i)
  end

  it "rejects a bluff another player already wrote" do
    described_class.call(room: room, player: host, text: "Sydney")
    expect { described_class.call(room: room, player: guest, text: "SYDNEY") }
      .to raise_error(Game::Error, /already/i)
  end

  it "rejects empty and long text" do
    expect { described_class.call(room: room, player: host, text: " ") }.to raise_error(Game::Error, /type/i)
    expect { described_class.call(room: room, player: host, text: "x" * 61) }.to raise_error(Game::Error, /60/)
  end

  it "rejects outside the writing phase" do
    room.update!(status: "voting")
    expect { described_class.call(room: room, player: host, text: "Sydney") }.to raise_error(Game::Error, /writing/i)
  end

  it "rejects a spectator" do
    guest.update!(spectator: true)
    expect { described_class.call(room: room, player: guest, text: "Sydney") }.to raise_error(Game::Error, /watching/i)
  end

  it "stays in writing even when everyone has written" do
    described_class.call(room: room, player: host, text: "Sydney")
    described_class.call(room: room, player: guest, text: "Perth")
    expect(room.reload).to be_writing
  end
end
