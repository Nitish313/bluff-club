require "rails_helper"

RSpec.describe Game::Presence do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  it "marks a player online" do
    host.update!(connected: false)
    described_class.connected(host)
    expect(host.reload).to be_connected
  end

  it "marks a player offline and queues host hand-over for the host" do
    described_class.disconnected(host)
    expect(host.reload).not_to be_connected
    expect(HostMigrationJob).to have_been_enqueued.with(room.id, host.id)
  end

  it "does not queue hand-over for a guest" do
    described_class.disconnected(guest)
    expect(HostMigrationJob).not_to have_been_enqueued
  end

  it "ends the phase early if the leaver was the last one not done" do
    room.rounds.create!(position: 0, question: "Q", answer: "T")
    Game::Advance.enter(room, "writing")
    room.current_round.bluffs.create!(player: guest, text: "x", normalized: "x")
    described_class.disconnected(host)
    expect(room.reload).to be_voting
  end

  describe ".migrate_host" do
    it "gives host to the next online player" do
      host.update!(connected: false)
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(guest.id)
    end

    it "does nothing if the host came back" do
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(host.id)
    end

    it "does nothing if host already changed" do
      room.update!(host_player_id: guest.id)
      host.update!(connected: false)
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(guest.id)
    end

    it "keeps the old host when nobody else is online" do
      host.update!(connected: false)
      guest.update!(connected: false)
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(host.id)
    end
  end
end
