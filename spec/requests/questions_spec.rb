require "rails_helper"

RSpec.describe "Generate questions" do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let(:questions) { [{ "question" => "Q?", "answer" => "A" }] }

  it "returns questions for the host" do
    allow(Game::GenerateQuestions).to receive(:call).with(topic: "Cricket").and_return(questions)
    post "/questions", params: { code: room.code, token: host.token, topic: "Cricket" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["questions"]).to eq(questions)
  end

  it "refuses a guest" do
    expect(Game::GenerateQuestions).not_to receive(:call)
    post "/questions", params: { code: room.code, token: guest.token, topic: "Cricket" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to match(/host/i)
  end

  it "refuses a bad token or code" do
    post "/questions", params: { code: room.code, token: "nope", topic: "Cricket" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/questions", params: { code: "ZZZZ", token: host.token, topic: "Cricket" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses while a game is running" do
    Game::Start.call(room: room, player: host, pack: "general", question_count: 2)
    post "/questions", params: { code: room.code, token: host.token, topic: "Cricket" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to match(/lobby/i)
  end

  it "passes service errors through" do
    allow(Game::GenerateQuestions).to receive(:call).and_raise(Game::Error, "Question generator is not set up")
    post "/questions", params: { code: room.code, token: host.token, topic: "Cricket" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to match(/not set up/i)
  end
end
