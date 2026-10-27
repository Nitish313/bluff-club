module Game
  module Text
    # Makes two answers easy to compare: "The Yangtze!" and "yangtze" become the same.
    def self.normalize(str)
      s = str.to_s.downcase.strip
      s = s.gsub(/(\d),(\d)/, '\1\2')
      s = s.gsub(/[^a-z0-9\s]/, " ").squeeze(" ").strip
      s.sub(/\A(the|a|an)\s+/, "")
    end
  end
end
