require "rails_helper"

RSpec.describe Game::State do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let(:round) { room.rounds.create!(position: 0, question: "Q?", answer: "Truth") }

  it "describes the lobby" do
    s = described_class.call(room)
    expect(s[:code]).to eq(room.code)
    expect(s[:status]).to eq("lobby")
    expect(s[:host_id]).to eq(host.id)
    expect(s[:players].map { |p| p[:name] }).to eq(%w[Host Guest])
    expect(s[:packs].map { |p| p[:key] }).to include("general")
    expect(s[:round]).to be_nil
    expect(s[:reveal]).to be_nil
  end

  it "shows the question and who is done during writing" do
    round.bluffs.create!(player: host, text: "x", normalized: "x")
    Game::Advance.enter(room, "writing")
    s = described_class.call(room)
    expect(s[:round][:question]).to eq("Q?")
    expect(s[:round][:index]).to eq(0)
    expect(s[:round][:total]).to eq(1)
    expect(s[:round][:phase_ends_at]).to be_present
    expect(s[:players].find { |p| p[:id] == host.id }[:done]).to be true
    expect(s[:players].find { |p| p[:id] == guest.id }[:done]).to be false
    expect(s[:all_done]).to be false
    expect(s[:round]).not_to have_key(:options)
  end

  it "flags all_done when every active player has answered" do
    round.bluffs.create!(player: host, text: "x", normalized: "x")
    round.bluffs.create!(player: guest, text: "y", normalized: "y")
    Game::Advance.enter(room, "writing")
    expect(described_class.call(room)[:all_done]).to be true
  end

  it "ignores offline players for all_done" do
    round.bluffs.create!(player: host, text: "x", normalized: "x")
    guest.update!(connected: false)
    Game::Advance.enter(room, "writing")
    expect(described_class.call(room)[:all_done]).to be true
  end

  it "tells the browser whether the AI generator is available" do
    allow(Game::GenerateQuestions).to receive(:enabled?).and_return(true)
    expect(described_class.call(room)[:ai_enabled]).to be true
    allow(Game::GenerateQuestions).to receive(:enabled?).and_return(false)
    expect(described_class.call(room)[:ai_enabled]).to be false
  end

  it "is not all_done in the lobby" do
    expect(described_class.call(room)[:all_done]).to be false
  end

  it "lists options during voting without authors or the truth flag" do
    round.bluffs.create!(player: host, text: "Fake", normalized: "fake")
    Game::Advance.enter(room, "voting")
    s = described_class.call(room)
    expect(s[:round][:options].map { |o| o[:text] }).to match_array(%w[Fake Truth])
    expect(s[:round][:options].first.keys).to match_array(%i[index text])
  end

  it "shows everything during reveal" do
    bluff = round.bluffs.create!(player: host, text: "Fake", normalized: "fake")
    round.votes.create!(player: guest, bluff: bluff)
    round.votes.create!(player: host, bluff: nil)
    Game::Advance.enter(room, "reveal")
    s = described_class.call(room)
    expect(s[:reveal][:answer]).to eq("Truth")
    fake = s[:reveal][:options].find { |o| o[:text] == "Fake" }
    expect(fake).to include(truth: false, author: "Host", voters: ["Guest"], points: 500)
    truth = s[:reveal][:options].find { |o| o[:truth] }
    expect(truth).to include(voters: ["Host"], points: 1000)
  end
end
