module Game
  class Start
    MIN_PLAYERS = 2
    MAX_QUESTIONS = 10
    MAX_CUSTOM_LENGTH = 120

    def self.call(room:, player:, pack:, question_count:, custom_questions: nil)
      new(room, player, pack, question_count, custom_questions).call
    end

    def initialize(room, player, pack, question_count, custom_questions)
      @room = room
      @player = player
      @pack = pack.to_s
      @question_count = question_count.to_i.clamp(1, MAX_QUESTIONS)
      @custom_questions = custom_questions
    end

    def call
      raise Game::Error, "Only the host can start" unless @room.host?(@player)
      raise Game::Error, "Game already started" unless @room.lobby? || @room.finished?
      raise Game::Error, "Need at least #{MIN_PLAYERS} players" if @room.active_players.count < MIN_PLAYERS

      questions = pick_questions
      Room.transaction do
        @room.rounds.destroy_all
        questions.each_with_index do |q, i|
          @room.rounds.create!(position: i, question: q["question"], answer: q["answer"])
        end
        @room.players.update_all(score: 0, spectator: false)
        @room.update!(pack: @pack, question_count: questions.size, current_round_index: 0,
          custom_questions: @pack == "custom" ? custom_list.to_json : nil)
        Game::Advance.enter(@room, "writing")
      end
    end

    private

    def pick_questions
      pool = @pack == "custom" ? custom_list : Game::Packs.find(@pack)&.dig(:questions)
      raise Game::Error, "Pick a question pack" if pool.nil?
      raise Game::Error, "Add at least one custom question" if pool.empty?
      pool.shuffle.first(@question_count)
    end

    def custom_list
      @custom_list ||= Array(@custom_questions).map do |q|
        q = q.to_h.stringify_keys
        { "question" => q["question"].to_s.strip.first(MAX_CUSTOM_LENGTH),
          "answer" => q["answer"].to_s.strip.first(MAX_CUSTOM_LENGTH) }
      end.reject { |q| q["question"].empty? || q["answer"].empty? }.first(MAX_QUESTIONS)
    end
  end
end
