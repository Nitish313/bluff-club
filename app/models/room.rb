class Room < ApplicationRecord
  STATUSES = %w[lobby writing voting reveal finished closed].freeze
  IN_GAME = %w[writing voting reveal].freeze

  has_many :players, dependent: :destroy
  has_many :rounds, -> { order(:position) }, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def in_game? = IN_GAME.include?(status)
  def host?(player) = host_player_id == player.id
  def current_round = rounds.find_by(position: current_round_index)
  def active_players = players.where(connected: true, spectator: false).order(:id)
  def custom_questions_list = JSON.parse(custom_questions.presence || "[]")
end
