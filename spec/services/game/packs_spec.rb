require "rails_helper"

RSpec.describe Game::Packs do
  it "loads every pack file" do
    keys = described_class.all.map { |p| p[:key] }
    expect(keys).to include("general", "science", "tech")
  end

  it "every pack has at least 10 questions with a question and an answer" do
    described_class.all.each do |pack|
      expect(pack[:questions].size).to be >= 10
      pack[:questions].each do |q|
        expect(q["question"]).to be_present
        expect(q["answer"]).to be_present
      end
    end
  end

  it "finds a pack by key" do
    expect(described_class.find("general")[:name]).to eq("General Knowledge")
    expect(described_class.find("nope")).to be_nil
  end

  it "gives a short summary for the lobby" do
    s = described_class.summary.find { |p| p[:key] == "tech" }
    expect(s).to include(key: "tech", name: "Tech & Internet")
    expect(s[:count]).to be >= 10
  end
end
