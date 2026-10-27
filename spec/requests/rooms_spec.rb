require "rails_helper"

RSpec.describe "Rooms and players" do
  it "creates a room" do
    post "/rooms", params: { name: "Nitish" }, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["code"]).to match(/\A[A-Z]{4}\z/)
    expect(body["token"]).to be_present
    expect(body["player_id"]).to be_present
  end

  it "returns the error message for a bad name" do
    post "/rooms", params: { name: "" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to match(/name/i)
  end

  it "joins a room" do
    room = Game::CreateRoom.call(name: "Host").first
    post "/players", params: { code: room.code, name: "Aman" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["code"]).to eq(room.code)
  end

  it "returns an error for a bad code" do
    post "/players", params: { code: "ZZZZ", name: "Aman" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "serves the page at / and /r/CODE" do
    get "/"
    expect(response).to have_http_status(:ok)
    get "/r/ABCD"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-prefill-code="ABCD"')
  end
end
