class Vote < ApplicationRecord
  belongs_to :round
  belongs_to :player
  belongs_to :bluff, optional: true

  def truth? = bluff_id.nil?
end
