module Game
  module Packs
    DIR = Rails.root.join("config/packs")

    def self.all
      @all ||= Dir[DIR.join("*.yml")].sort.map { |f| load_file(f) }
    end

    def self.find(key) = all.find { |p| p[:key] == key }

    def self.summary = all.map { |p| { key: p[:key], name: p[:name], count: p[:questions].size } }

    def self.load_file(path)
      data = YAML.safe_load_file(path)
      questions = data["questions"].map do |q|
        { "question" => q["question"].to_s, "answer" => q["answer"].to_s }
      end
      { key: File.basename(path, ".yml"), name: data["name"], questions: questions }
    end
  end
end
