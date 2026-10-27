require "rails_helper"

RSpec.describe Game::Start do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  it "builds rounds from the pack and enters writing" do
    described_class.call(room: room, player: host, pack: "science", question_count: 4)
    expect(room.reload).to be_writing
    expect(room.rounds.count).to eq(4)
    expect(room.pack).to eq("science")
    expect(room.current_round_index).to eq(0)
    expect(PhaseTimeoutJob).to have_been_enqueued
  end

  it "caps the question count at 10 and floors at 1" do
    described_class.call(room: room, player: host, pack: "general", question_count: 99)
    expect(room.rounds.count).to eq(10)
  end

  it "only the host can start" do
    expect { described_class.call(room: room, player: guest, pack: "general", question_count: 3) }
      .to raise_error(Game::Error, /host/i)
  end

  it "needs two players" do
    guest.update!(connected: false)
    expect { described_class.call(room: room, player: host, pack: "general", question_count: 3) }
      .to raise_error(Game::Error, /2 players/i)
  end

  it "rejects an unknown pack" do
    expect { described_class.call(room: room, player: host, pack: "nope", question_count: 3) }
      .to raise_error(Game::Error, /pack/i)
  end

  it "uses custom questions and skips blank ones" do
    custom = [
      { "question" => "Our first product?", "answer" => "HowNow" },
      { "question" => "", "answer" => "x" }
    ]
    described_class.call(room: room, player: host, pack: "custom", question_count: 5, custom_questions: custom)
    expect(room.rounds.count).to eq(1)
    expect(room.rounds.first.answer).to eq("HowNow")
  end

  it "rejects a custom pack with no usable questions" do
    expect { described_class.call(room: room, player: host, pack: "custom", question_count: 5, custom_questions: []) }
      .to raise_error(Game::Error, /custom question/i)
  end

  it "resets scores and spectators" do
    guest.update!(score: 900)
    host.update!(score: 100)
    described_class.call(room: room, player: host, pack: "general", question_count: 3)
    expect(room.players.pluck(:score)).to all(eq(0))
    expect(room.players.pluck(:spectator)).to all(be false)
  end

  it "can start again after a finished game that has votes" do
    described_class.call(room: room, player: host, pack: "general", question_count: 1)
    round = room.current_round
    bluff = round.bluffs.create!(player: host, text: "x", normalized: "x")
    round.votes.create!(player: guest, bluff: bluff)
    room.update!(status: "finished")
    described_class.call(room: room, player: host, pack: "general", question_count: 2)
    expect(room.reload.rounds.count).to eq(2)
    expect(Vote.count).to eq(0)
  end

  it "refuses while a game is running" do
    room.update!(status: "voting")
    expect { described_class.call(room: room, player: host, pack: "general", question_count: 3) }
      .to raise_error(Game::Error, /already started/i)
  end
end
