class Round < ApplicationRecord
  belongs_to :room
  # Votes point at bluffs, so votes must go first when a round is deleted.
  has_many :votes, dependent: :destroy
  has_many :bluffs, dependent: :destroy

  validates :position, :question, :answer, presence: true
end
