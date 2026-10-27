module Game
  module CodeGenerator
    LETTERS = %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z].freeze

    def self.generate = Array.new(4) { LETTERS.sample }.join

    def self.unique
      10.times do
        code = generate
        return code unless Room.exists?(code: code)
      end
      raise Game::Error, "Could not make a room code. Try again."
    end
  end
end
