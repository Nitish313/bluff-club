require "rails_helper"

RSpec.describe Game::Advance do
  let(:room) { Room.create!(code: "ABCD") }
  let!(:p1) { room.players.create!(name: "A", token: "a") }
  let!(:p2) { room.players.create!(name: "B", token: "b") }
  let!(:p3) { room.players.create!(name: "C", token: "c") }
  let!(:r0) { room.rounds.create!(position: 0, question: "Q0", answer: "T0") }
  let!(:r1) { room.rounds.create!(position: 1, question: "Q1", answer: "T1") }

  before { room.update!(host_player_id: p1.id) }

  describe ".enter" do
    it "sets the phase, a deadline and queues the timer job" do
      described_class.enter(room, "writing")
      expect(room.reload).to be_writing
      expect(room.phase_ends_at).to be_within(2.seconds).of(60.seconds.from_now)
      expect(room.phase_token).to be_present
      expect(PhaseTimeoutJob).to have_been_enqueued.with(room.id, room.phase_token)
    end
  end

  describe ".on_timeout" do
    it "moves writing to voting when the token matches" do
      described_class.enter(room, "writing")
      expect(described_class.on_timeout(room, room.phase_token)).to be true
      expect(room.reload).to be_voting
    end

    it "does nothing when the token is old" do
      described_class.enter(room, "writing")
      expect(described_class.on_timeout(room, "stale")).to be false
      expect(room.reload).to be_writing
    end
  end

  describe "voting -> reveal gives points" do
    it "gives 1000 for the truth and 500 per fooled player" do
      described_class.enter(room, "voting")
      b1 = r0.bluffs.create!(player: p1, text: "F1", normalized: "f1")
      r0.votes.create!(player: p2, bluff: b1)   # p2 fooled by p1
      r0.votes.create!(player: p3, bluff: nil)  # p3 found the truth
      described_class.on_timeout(room, room.phase_token)
      expect(room.reload).to be_reveal
      expect(p1.reload.score).to eq(500)
      expect(p2.reload.score).to eq(0)
      expect(p3.reload.score).to eq(1000)
    end
  end

  describe "reveal -> next round or finished" do
    it "goes to the next round" do
      described_class.enter(room, "reveal")
      described_class.on_timeout(room, room.phase_token)
      expect(room.reload).to be_writing
      expect(room.current_round_index).to eq(1)
    end

    it "finishes after the last round" do
      room.update!(current_round_index: 1)
      described_class.enter(room, "reveal")
      described_class.on_timeout(room, room.phase_token)
      expect(room.reload).to be_finished
      expect(room.phase_ends_at).to be_nil
    end
  end

  describe ".maybe_finish_phase" do
    it "ends writing early when every active player has a bluff" do
      described_class.enter(room, "writing")
      [p1, p2, p3].each { |p| r0.bluffs.create!(player: p, text: p.name, normalized: p.name.downcase) }
      expect(described_class.maybe_finish_phase(room)).to be true
      expect(room.reload).to be_voting
    end

    it "waits when someone has not written yet" do
      described_class.enter(room, "writing")
      r0.bluffs.create!(player: p1, text: "x", normalized: "x")
      expect(described_class.maybe_finish_phase(room)).to be false
      expect(room.reload).to be_writing
    end

    it "ignores players who are offline" do
      described_class.enter(room, "writing")
      p3.update!(connected: false)
      [p1, p2].each { |p| r0.bluffs.create!(player: p, text: p.name, normalized: p.name.downcase) }
      expect(described_class.maybe_finish_phase(room)).to be true
    end

    it "never advances when nobody is online" do
      described_class.enter(room, "writing")
      room.players.update_all(connected: false)
      expect(described_class.maybe_finish_phase(room)).to be false
    end
  end

  describe ".skip" do
    it "lets the host skip the reveal" do
      described_class.enter(room, "reveal")
      expect(described_class.skip(room, p1)).to be true
      expect(room.reload).to be_writing
    end

    it "stops a non host" do
      described_class.enter(room, "reveal")
      expect { described_class.skip(room, p2) }.to raise_error(Game::Error, /host/i)
    end

    it "does nothing outside reveal" do
      described_class.enter(room, "writing")
      expect(described_class.skip(room, p1)).to be false
    end
  end
end
