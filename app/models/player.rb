class Player < ApplicationRecord
  belongs_to :room
  has_many :votes, dependent: :destroy
  has_many :bluffs, dependent: :destroy

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
end
