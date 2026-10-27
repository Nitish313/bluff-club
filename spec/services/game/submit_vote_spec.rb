require "rails_helper"

RSpec.describe Game::SubmitVote do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let(:round) { room.rounds.create!(position: 0, question: "Q", answer: "Truth") }
  let(:options) { Game::Options.for(round) }

  before do
    round.bluffs.create!(player: host, text: "Host fake", normalized: "host fake")
    round.bluffs.create!(player: guest, text: "Guest fake", normalized: "guest fake")
    Game::Advance.enter(room, "voting")
  end

  def index_of(text) = options.index { |o| o[:text] == text }

  it "saves a vote for the truth" do
    vote = described_class.call(room: room, player: host, option_index: index_of("Truth"))
    expect(vote).to be_truth
  end

  it "saves a vote for a bluff" do
    vote = described_class.call(room: room, player: host, option_index: index_of("Guest fake"))
    expect(vote.bluff.player).to eq(guest)
  end

  it "rejects voting for your own bluff" do
    expect { described_class.call(room: room, player: host, option_index: index_of("Host fake")) }
      .to raise_error(Game::Error, /own/i)
  end

  it "rejects a bad index" do
    expect { described_class.call(room: room, player: host, option_index: 99) }.to raise_error(Game::Error, /pick/i)
    expect { described_class.call(room: room, player: host, option_index: -1) }.to raise_error(Game::Error, /pick/i)
  end

  it "rejects a second vote" do
    described_class.call(room: room, player: host, option_index: index_of("Truth"))
    expect { described_class.call(room: room, player: host, option_index: index_of("Truth")) }
      .to raise_error(Game::Error, /already/i)
  end

  it "rejects outside voting" do
    room.update!(status: "writing")
    expect { described_class.call(room: room, player: host, option_index: 0) }.to raise_error(Game::Error, /voting/i)
  end

  it "rejects a spectator" do
    guest.update!(spectator: true)
    expect { described_class.call(room: room, player: guest, option_index: index_of("Truth")) }
      .to raise_error(Game::Error, /watching/i)
  end

  it "moves to reveal when everyone has voted" do
    described_class.call(room: room, player: host, option_index: index_of("Truth"))
    described_class.call(room: room, player: guest, option_index: index_of("Truth"))
    expect(room.reload).to be_reveal
    expect(host.reload.score).to eq(1000)
  end
end
