require "rails_helper"

RSpec.describe CloseIdleRoomsJob do
  it "closes rooms idle for more than 2 hours and leaves the rest" do
    old = Room.create!(code: "AAAA", last_activity_at: 3.hours.ago)
    fresh = Room.create!(code: "BBBB", last_activity_at: 10.minutes.ago)
    described_class.perform_now
    expect(old.reload).to be_closed
    expect(fresh.reload).to be_lobby
  end
end
