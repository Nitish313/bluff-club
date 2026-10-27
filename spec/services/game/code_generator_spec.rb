require "rails_helper"

RSpec.describe Game::CodeGenerator do
  it "makes 4 letter codes without I or O" do
    100.times do
      code = described_class.generate
      expect(code).to match(/\A[A-HJ-NP-Z]{4}\z/)
    end
  end

  it "skips a code that is already used" do
    Room.create!(code: "AAAA")
    allow(described_class).to receive(:generate).and_return("AAAA", "BBBB")
    expect(described_class.unique).to eq("BBBB")
  end
end
