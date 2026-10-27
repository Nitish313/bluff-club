require "net/http"

module Game
  # Asks OpenAI for trivia questions on a topic. Returns [{"question","answer"}, ...].
  class GenerateQuestions
    # OPENAI_API_URL lets a test or proxy point this elsewhere.
    URL = URI(ENV.fetch("OPENAI_API_URL", "https://api.openai.com/v1/chat/completions"))
    MODEL = "gpt-4o-mini"
    COUNT = 8
    TOPIC_MAX = 60
    TIMEOUT = 20

    def self.enabled? = ENV["OPENAI_API_KEY"].present?

    def self.call(topic:, count: COUNT) = new(topic, count).call

    def initialize(topic, count)
      @topic = topic.to_s.strip.squeeze(" ")
      @count = count.to_i.clamp(1, 10)
    end

    def call
      raise Game::Error, "Type a topic first" if @topic.empty?
      raise Game::Error, "Keep the topic under #{TOPIC_MAX} characters" if @topic.length > TOPIC_MAX
      raise Game::Error, "Question generator is not set up on this server" unless self.class.enabled?

      questions = parse(request)
      raise Game::Error, "No usable questions came back. Try another topic." if questions.empty?
      questions
    end

    private

    def request
      http = Net::HTTP.new(URL.host, URL.port)
      http.use_ssl = URL.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      req = Net::HTTP::Post.new(URL.path, "Content-Type" => "application/json",
        "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}")
      req.body = body.to_json
      res = http.request(req)
      return res.body if res.is_a?(Net::HTTPSuccess)

      Rails.logger.warn("OpenAI #{res.code}: #{res.body.to_s.first(300)}")
      raise Game::Error, failure_message(res.code)
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError
      raise Game::Error, "The question generator did not answer. Try again."
    end

    def failure_message(code)
      case code.to_i
      when 401 then "OpenAI rejected the API key. Check OPENAI_API_KEY on the server."
      when 429 then "OpenAI says the account has no credit left, or too many requests. Check billing."
      else "The question generator is busy (OpenAI error #{code}). Try again in a moment."
      end
    end

    def body
      { model: MODEL, temperature: 0.8, response_format: { type: "json_object" },
        messages: [{ role: "system", content: SYSTEM_PROMPT }, { role: "user", content: user_prompt }] }
    end

    def user_prompt
      "Topic: #{@topic}\nWrite #{@count} questions."
    end

    def parse(raw)
      content = JSON.parse(raw).dig("choices", 0, "message", "content")
      list = JSON.parse(content.to_s)["questions"]
      Array(list).filter_map do |q|
        next unless q.is_a?(Hash)
        question = q["question"].to_s.strip
        answer = q["answer"].to_s.strip
        { "question" => question, "answer" => answer } if question.present? && answer.present?
      end
    rescue JSON::ParserError, TypeError
      raise Game::Error, "The question generator sent something odd. Try again."
    end

    SYSTEM_PROMPT = <<~TEXT.freeze
      You write trivia questions for a bluffing party game. Players invent fake answers,
      so each true answer must be short (1 to 4 words or a number), specific and checkable.
      Avoid yes/no questions and avoid answers that are long sentences.
      Reply with JSON only: {"questions":[{"question":"...","answer":"..."}]}
    TEXT
  end
end
