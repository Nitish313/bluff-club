require "rails_helper"

RSpec.describe RoomChannel, type: :channel do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  it "subscribes with a good code and token, and sends hello plus state" do
    subscribe(code: room.code.downcase, token: host.token)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(room)
    expect(transmissions.first).to include("type" => "hello", "player_id" => host.id)
  end

  it "rejects a bad token" do
    subscribe(code: room.code, token: "nope")
    expect(subscription).to be_rejected
  end

  it "marks the player offline on unsubscribe" do
    subscribe(code: room.code, token: guest.token)
    unsubscribe
    expect(guest.reload).not_to be_connected
  end

  it "sends an error message back to only this player" do
    subscribe(code: room.code, token: guest.token)
    perform :start_game, pack: "general", question_count: 3
    expect(transmissions.last).to include("type" => "error", "message" => "Only the host can start")
  end

  it "starts the game and broadcasts" do
    subscribe(code: room.code, token: host.token)
    expect { perform :start_game, pack: "general", question_count: 3 }
      .to have_broadcasted_to(room).with(hash_including(status: "writing"))
  end

  it "replies bluff_ok with the text after a bluff" do
    room.rounds.create!(position: 0, question: "Q", answer: "T")
    Game::Advance.enter(room, "writing")
    subscribe(code: room.code, token: host.token)
    perform :submit_bluff, text: "Fake"
    expect(transmissions.last).to include("type" => "bluff_ok", "text" => "Fake")
  end

  it "tick moves the phase on only when time is really up" do
    room.rounds.create!(position: 0, question: "Q", answer: "T")
    Game::Advance.enter(room, "writing")
    subscribe(code: room.code, token: host.token)
    perform :tick
    expect(room.reload).to be_writing
    room.update!(phase_ends_at: 1.second.ago)
    perform :tick
    expect(room.reload).to be_voting
  end
end
