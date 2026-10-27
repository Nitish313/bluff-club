require "rails_helper"

RSpec.describe Game::Options do
  let(:room) { Room.create!(code: "ABCD") }
  let(:round) { room.rounds.create!(position: 0, question: "Q", answer: "Truth") }
  let(:p1) { room.players.create!(name: "A", token: "a") }
  let(:p2) { room.players.create!(name: "B", token: "b") }

  before do
    round.bluffs.create!(player: p1, text: "Fake one", normalized: "fake one")
    round.bluffs.create!(player: p2, text: "Fake two", normalized: "fake two")
  end

  it "mixes the truth in with the bluffs" do
    texts = described_class.for(round).map { |o| o[:text] }
    expect(texts).to match_array(["Fake one", "Fake two", "Truth"])
  end

  it "gives the same order every time for the same round" do
    expect(described_class.for(round).map { |o| o[:text] }).to eq(described_class.for(round).map { |o| o[:text] })
  end

  it "marks the truth with bluff nil" do
    truth = described_class.for(round).find { |o| o[:bluff].nil? }
    expect(truth[:text]).to eq("Truth")
  end
end
