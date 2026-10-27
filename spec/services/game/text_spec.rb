require "rails_helper"

RSpec.describe Game::Text do
  it "lowercases and trims" do
    expect(described_class.normalize("  Canberra ")).to eq("canberra")
  end

  it "drops punctuation and extra spaces" do
    expect(described_class.normalize("Mount  Kilimanjaro!")).to eq("mount kilimanjaro")
  end

  it "drops a leading the / a / an" do
    expect(described_class.normalize("The Yangtze")).to eq("yangtze")
    expect(described_class.normalize("An apple")).to eq("apple")
  end

  it "drops commas in numbers" do
    expect(described_class.normalize("10,080")).to eq("10080")
  end
end
