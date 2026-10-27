class Bluff < ApplicationRecord
  belongs_to :round
  belongs_to :player
  has_many :votes, dependent: :destroy

  validates :text, :normalized, presence: true
end
