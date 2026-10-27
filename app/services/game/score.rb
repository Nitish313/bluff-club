module Game
  module Score
    TRUTH_POINTS = 1000
    FOOL_POINTS = 500

    def self.call(round)
      round.votes.includes(:bluff, :player).each do |vote|
        if vote.truth?
          vote.player.increment!(:score, TRUTH_POINTS)
        else
          vote.bluff.player.increment!(:score, FOOL_POINTS)
        end
      end
    end
  end
end
