require "rails_helper"

RSpec.describe Game::GenerateQuestions do
  let(:url) { "https://api.openai.com/v1/chat/completions" }
  let(:good) do
    { choices: [{ message: { content: {
      questions: [{ question: "Who directed Sholay?", answer: "Ramesh Sippy" },
                  { question: "Year Sholay released?", answer: "1975" }]
    }.to_json } }] }.to_json
  end

  around do |ex|
    old = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "test-key"
    ex.run
    ENV["OPENAI_API_KEY"] = old
  end

  it "asks OpenAI for questions on the topic and returns them" do
    stub = stub_request(:post, url)
      .with(headers: { "Authorization" => "Bearer test-key" }) { |req| JSON.parse(req.body)["messages"].last["content"].include?("Bollywood") }
      .to_return(status: 200, body: good, headers: { "Content-Type" => "application/json" })
    out = described_class.call(topic: "Bollywood")
    expect(stub).to have_been_requested
    expect(out).to eq([{ "question" => "Who directed Sholay?", "answer" => "Ramesh Sippy" },
                       { "question" => "Year Sholay released?", "answer" => "1975" }])
  end

  it "drops entries with a missing question or answer and trims text" do
    body = { choices: [{ message: { content: { questions: [
      { question: "  Q1? ", answer: " A1 " }, { question: "Q2?", answer: "" }, { question: "", answer: "A3" }, "junk"
    ] }.to_json } }] }.to_json
    stub_request(:post, url).to_return(status: 200, body: body)
    expect(described_class.call(topic: "x")).to eq([{ "question" => "Q1?", "answer" => "A1" }])
  end

  it "rejects an empty topic without calling OpenAI" do
    expect { described_class.call(topic: "  ") }.to raise_error(Game::Error, /topic/i)
    expect(a_request(:post, url)).not_to have_been_made
  end

  it "rejects a topic that is too long" do
    expect { described_class.call(topic: "x" * 61) }.to raise_error(Game::Error, /60/)
  end

  it "fails clearly when the key is missing" do
    ENV["OPENAI_API_KEY"] = nil
    expect { described_class.call(topic: "x") }.to raise_error(Game::Error, /not set up/i)
    expect(described_class).not_to be_enabled
  end

  it "says the key is wrong on 401" do
    stub_request(:post, url).to_return(status: 401, body: "bad key")
    expect { described_class.call(topic: "x") }.to raise_error(Game::Error, /key/i)
  end

  it "says the account has no credit on 429" do
    stub_request(:post, url).to_return(status: 429, body: "insufficient_quota")
    expect { described_class.call(topic: "x") }.to raise_error(Game::Error, /credit/i)
  end

  it "fails clearly on other OpenAI errors" do
    stub_request(:post, url).to_return(status: 500, body: "boom")
    expect { described_class.call(topic: "x") }.to raise_error(Game::Error, /try again/i)
  end

  it "fails clearly when the answer is not JSON" do
    stub_request(:post, url).to_return(status: 200, body: { choices: [{ message: { content: "not json" } }] }.to_json)
    expect { described_class.call(topic: "x") }.to raise_error(Game::Error, /try again/i)
  end

  it "fails clearly when the request times out" do
    stub_request(:post, url).to_timeout
    expect { described_class.call(topic: "x") }.to raise_error(Game::Error, /try again/i)
  end
end
