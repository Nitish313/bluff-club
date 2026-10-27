module Game
  module Options
    # The list players vote on: all bluffs plus the truth, in a fixed random order per round.
    def self.for(round)
      items = round.bluffs.includes(:player).order(:id).map { |b| { text: b.text, bluff: b } }
      items << { text: round.answer, bluff: nil }
      items.shuffle(random: Random.new(round.id * 7919))
    end
  end
end
