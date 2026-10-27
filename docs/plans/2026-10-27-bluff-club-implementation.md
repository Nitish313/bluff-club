# Bluff Club Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and deploy a live multiplayer "bluff trivia" game at a public link, joinable by room code, for the Handshake x OpenAI contest.

**Architecture:** One Rails 8 app. The server owns all game state in the database. After every change it broadcasts the full room state over Action Cable, and the browser only draws what it receives. Game rules live in plain Ruby classes under `app/services/game/` with no network code, so they are unit tested. Timers are Active Job jobs that fire when a phase ends.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, Action Cable + Solid Cable, Active Job + Solid Queue, MySQL 8 (local) and Aiven free MySQL (production), importmap, plain HTML/CSS/JS, RSpec.

Design doc: `docs/plans/2026-10-27-bluff-club-design.md`

**Commit rule:** Nitish decides when to commit. Each task ends with a commit step. Only run it if he has said commits are OK for this repo. No Claude attribution lines in commit messages.

---

## Words used in this plan

- **Room**: one game table. Has a 4 letter code.
- **Player**: a person in a room. Has a secret token saved in the browser.
- **Round**: one question. A room has 1 to 10 rounds.
- **Bluff**: the fake answer a player writes.
- **Vote**: the answer a player picks.
- **Phase**: the current step of the room. One of `lobby`, `writing`, `voting`, `reveal`, `finished`.
- **State**: a JSON copy of the whole room, sent to every player after each change.

## Phase order

```
lobby -> writing -> voting -> reveal -> writing (next round) ... -> finished -> lobby (play again)
```

---

### Task 1: Create the Rails app

**Files:**
- Create: whole Rails app in `~/projects/bluff-club`

**Step 1: Check Ruby**

Run: `source ~/.rvm/scripts/rvm && rvm use 3.4.8 && ruby -v`
Expected: `ruby 3.4.8`

**Step 2: Install Rails and create the app in the existing folder**

```bash
cd ~/projects/bluff-club
source ~/.rvm/scripts/rvm && rvm use 3.4.8
gem install rails --no-document
rails new . --database=mysql --skip-git --skip-jbuilder --skip-action-mailer \
  --skip-action-mailbox --skip-action-text --skip-active-storage --skip-hotwire \
  --skip-solid --skip-kamal --skip-thruster --skip-docker --skip-test \
  --skip-rubocop --skip-brakeman --skip-ci --skip-dev-gems
echo "3.4.8" > .ruby-version
```

Expected: `rails -v` prints `Rails 8.1.x`. Folder has `app/`, `config/`, `Gemfile`.

**Step 3: Gems**

Edit `Gemfile`. Make sure these lines exist (keep the rest that `rails new` wrote, including `gem "mysql2"`):

```ruby
gem "solid_cable"
gem "solid_queue"

group :development, :test do
  gem "rspec-rails"
end
```

Run: `bundle install`
Expected: ends with `Bundle complete!`

**Step 4: Database config: local MySQL, Aiven MySQL in production**

Replace `config/database.yml` with:

```yaml
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: root
  password: <%= ENV.fetch("MYSQL_PASSWORD", "") %>
  host: 127.0.0.1

development:
  <<: *default
  database: bluff_club_development

test:
  <<: *default
  database: bluff_club_test

production:
  <<: *default
  url: <%= ENV["DATABASE_URL"] %>
```

The local root password is the same one used in `hownow3.1/config/database.yml`. Put it in the shell once:

```bash
echo 'export MYSQL_PASSWORD="<root password>"' >> ~/.bashrc && source ~/.bashrc
```

Run: `bin/rails db:create`
Expected: `Created database 'bluff_club_development'` and `'bluff_club_test'`.

**Step 5: RSpec**

Run: `bin/rails generate rspec:install`
Expected: creates `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`.

In `spec/rails_helper.rb`, add inside the `RSpec.configure do |config|` block:

```ruby
  config.include ActiveJob::TestHelper
```

And add this line to `config/environments/test.rb`:

```ruby
  config.active_job.queue_adapter = :test
```

Run: `bundle exec rspec`
Expected: `0 examples, 0 failures`

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: new Rails 8 app with RSpec"
```

---

### Task 2: Solid Cable and Solid Queue on one database

Why: Rails 8 wants a separate database for cable and for jobs. We have only one free MySQL database. So we put their tables in the main database.

**Files:**
- Modify: `config/cable.yml`, `config/queue.yml`, `config/environments/production.rb`, `config/environments/development.rb`, `config/puma.rb`
- Create: `db/migrate/*_create_solid_tables.rb`

**Step 1: Install generators**

Run: `bin/rails solid_cable:install solid_queue:install`
Expected: creates `db/cable_schema.rb`, `db/queue_schema.rb`, `config/cable.yml`, `config/queue.yml`, `config/recurring.yml`.

**Step 2: Point both at the main database**

Replace `config/cable.yml` with:

```yaml
development:
  adapter: async

test:
  adapter: test

production:
  adapter: solid_cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

In `config/environments/production.rb`, make sure these lines exist and that there is **no** `connects_to` line for solid_queue:

```ruby
  config.active_job.queue_adapter = :solid_queue
```

Delete the line `config.solid_queue.connects_to = { database: { writing: :queue } }` if it exists.

In `config/environments/development.rb`, add:

```ruby
  config.active_job.queue_adapter = :async
```

Check `config/puma.rb` has this line (Rails 8 adds it). If not, add it:

```ruby
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
```

**Step 3: Migration for the solid tables**

Run: `bin/rails g migration CreateSolidTables`

Open `db/queue_schema.rb` and `db/cable_schema.rb`. MySQL note: Solid Cable's `payload` column must be `binary` with `limit: 536870912` as generated; keep it. Copy every `create_table ... end` block (and `add_foreign_key` lines) from both files into the `change` method of the new migration. Do not copy the `ActiveRecord::Schema[...].define do` wrapper. Then delete `db/queue_schema.rb` and `db/cable_schema.rb`.

Run: `bin/rails db:migrate`
Expected: tables `solid_queue_jobs`, `solid_cable_messages` and others appear in `db/schema.rb`.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: solid cable and solid queue on the main database"
```

---

### Task 3: Tables and models

**Files:**
- Create: 5 migrations, `app/models/room.rb`, `player.rb`, `round.rb`, `bluff.rb`, `vote.rb`
- Test: `spec/models/room_spec.rb`

**Step 1: Migrations**

```bash
bin/rails g migration CreateRooms code:string:uniq status:string host_player_id:bigint pack:string question_count:integer current_round_index:integer phase_ends_at:datetime phase_token:string custom_questions:text last_activity_at:datetime
bin/rails g migration CreatePlayers room:references name:string token:string:uniq score:integer connected:boolean spectator:boolean
bin/rails g migration CreateRounds room:references position:integer question:text answer:text
bin/rails g migration CreateBluffs round:references player:references text:string normalized:string
bin/rails g migration CreateVotes round:references player:references bluff:references
```

Then edit the generated files so the columns have defaults and null rules:

`*_create_rooms.rb`:

```ruby
class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :code, null: false
      t.string :status, null: false, default: "lobby"
      t.bigint :host_player_id
      t.string :pack, null: false, default: "general"
      t.integer :question_count, null: false, default: 6
      t.integer :current_round_index, null: false, default: 0
      t.datetime :phase_ends_at
      t.string :phase_token
      t.text :custom_questions
      t.datetime :last_activity_at
      t.timestamps
    end
    add_index :rooms, :code, unique: true
  end
end
```

`*_create_players.rb`:

```ruby
class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :room, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token, null: false
      t.integer :score, null: false, default: 0
      t.boolean :connected, null: false, default: true
      t.boolean :spectator, null: false, default: false
      t.timestamps
    end
    add_index :players, :token, unique: true
  end
end
```

`*_create_rounds.rb`:

```ruby
class CreateRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :rounds do |t|
      t.references :room, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :question, null: false
      t.text :answer, null: false
      t.timestamps
    end
    add_index :rounds, [:room_id, :position], unique: true
  end
end
```

`*_create_bluffs.rb`:

```ruby
class CreateBluffs < ActiveRecord::Migration[8.1]
  def change
    create_table :bluffs do |t|
      t.references :round, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.string :text, null: false
      t.string :normalized, null: false
      t.timestamps
    end
    add_index :bluffs, [:round_id, :player_id], unique: true
  end
end
```

`*_create_votes.rb`:

```ruby
class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :round, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.references :bluff, null: true, foreign_key: true
      t.timestamps
    end
    add_index :votes, [:round_id, :player_id], unique: true
  end
end
```

Run: `bin/rails db:migrate`
Expected: no error.

**Step 2: Write the failing model test**

`spec/models/room_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Room do
  let(:room) { Room.create!(code: "ABCD") }

  it "starts in the lobby" do
    expect(room).to be_lobby
    expect(room).not_to be_in_game
  end

  it "knows the host" do
    host = room.players.create!(name: "Nitish", token: "t1")
    other = room.players.create!(name: "Aman", token: "t2")
    room.update!(host_player_id: host.id)
    expect(room.host?(host)).to be true
    expect(room.host?(other)).to be false
  end

  it "returns the current round by position" do
    r0 = room.rounds.create!(position: 0, question: "Q0", answer: "A0")
    r1 = room.rounds.create!(position: 1, question: "Q1", answer: "A1")
    expect(room.current_round).to eq(r0)
    room.update!(current_round_index: 1)
    expect(room.current_round).to eq(r1)
  end

  it "lists active players: connected and not spectators" do
    a = room.players.create!(name: "A", token: "a")
    room.players.create!(name: "B", token: "b", connected: false)
    room.players.create!(name: "C", token: "c", spectator: true)
    expect(room.active_players).to eq([a])
  end

  it "rejects a bad status" do
    expect { room.update!(status: "sleeping") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
```

**Step 3: Run it, see it fail**

Run: `bundle exec rspec spec/models/room_spec.rb`
Expected: FAIL, `uninitialized constant Room`

**Step 4: Models**

`app/models/room.rb`:

```ruby
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
```

`app/models/player.rb`:

```ruby
class Player < ApplicationRecord
  belongs_to :room
  has_many :bluffs, dependent: :destroy
  has_many :votes, dependent: :destroy

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
end
```

`app/models/round.rb`:

```ruby
class Round < ApplicationRecord
  belongs_to :room
  has_many :bluffs, dependent: :destroy
  has_many :votes, dependent: :destroy

  validates :position, :question, :answer, presence: true
end
```

`app/models/bluff.rb`:

```ruby
class Bluff < ApplicationRecord
  belongs_to :round
  belongs_to :player
  has_many :votes

  validates :text, :normalized, presence: true
end
```

`app/models/vote.rb`:

```ruby
class Vote < ApplicationRecord
  belongs_to :round
  belongs_to :player
  belongs_to :bluff, optional: true

  def truth? = bluff_id.nil?
end
```

**Step 5: Run, see it pass**

Run: `bundle exec rspec spec/models/room_spec.rb`
Expected: `5 examples, 0 failures`

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: rooms, players, rounds, bluffs, votes"
```

---

### Task 4: Small helpers: error class, text normalizer, room code generator

**Files:**
- Create: `app/services/game/error.rb`, `app/services/game/text.rb`, `app/services/game/code_generator.rb`
- Test: `spec/services/game/text_spec.rb`, `spec/services/game/code_generator_spec.rb`

**Step 1: Failing tests**

`spec/services/game/text_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::Text do
  it "lowercases and trims" do
    expect(described_class.normalize("  Canberra ")).to eq("canberra")
  end

  it "drops punctuation and extra spaces" do
    expect(described_class.normalize("Mount  Kilimanjaro!")).to eq("mount kilimanjaro")
  end

  it "drops a leading the / a / an" do
    expect(described_class.normalize("The Yangtze")).to eq("yangtze")
    expect(described_class.normalize("An apple")).to eq("apple")
  end

  it "drops commas in numbers" do
    expect(described_class.normalize("10,080")).to eq("10080")
  end
end
```

`spec/services/game/code_generator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::CodeGenerator do
  it "makes 4 letter codes without I or O" do
    100.times do
      code = described_class.generate
      expect(code).to match(/\A[A-HJ-NP-Z]{4}\z/)
    end
  end

  it "skips a code that is already used" do
    Room.create!(code: "AAAA")
    allow(described_class).to receive(:generate).and_return("AAAA", "BBBB")
    expect(described_class.unique).to eq("BBBB")
  end
end
```

**Step 2: Run, see them fail**

Run: `bundle exec rspec spec/services`
Expected: FAIL, `uninitialized constant Game`

**Step 3: Code**

`app/services/game/error.rb`:

```ruby
module Game
  class Error < StandardError; end
end
```

`app/services/game/text.rb`:

```ruby
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
```

`app/services/game/code_generator.rb`:

```ruby
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
```

**Step 4: Run, see them pass**

Run: `bundle exec rspec spec/services`
Expected: `6 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: text normalizer and room code generator"
```

---

### Task 5: Question packs

**Files:**
- Create: `config/packs/general.yml`, `config/packs/science.yml`, `config/packs/tech.yml`, `app/services/game/packs.rb`
- Test: `spec/services/game/packs_spec.rb`

**Step 1: Failing test**

`spec/services/game/packs_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::Packs do
  it "loads every pack file" do
    keys = described_class.all.map { |p| p[:key] }
    expect(keys).to include("general", "science", "tech")
  end

  it "every pack has at least 10 questions with a question and an answer" do
    described_class.all.each do |pack|
      expect(pack[:questions].size).to be >= 10
      pack[:questions].each do |q|
        expect(q["question"]).to be_present
        expect(q["answer"]).to be_present
      end
    end
  end

  it "finds a pack by key" do
    expect(described_class.find("general")[:name]).to eq("General Knowledge")
    expect(described_class.find("nope")).to be_nil
  end

  it "gives a short summary for the lobby" do
    s = described_class.summary.find { |p| p[:key] == "tech" }
    expect(s).to include(key: "tech", name: "Tech & Internet")
    expect(s[:count]).to be >= 10
  end
end
```

**Step 2: Run, see it fail**

Run: `bundle exec rspec spec/services/game/packs_spec.rb`
Expected: FAIL, `uninitialized constant Game::Packs`

**Step 3: Pack files**

`config/packs/general.yml`:

```yaml
name: General Knowledge
questions:
  - { question: "What year did the first iPhone go on sale?", answer: "2007" }
  - { question: "How many bones are in the adult human body?", answer: "206" }
  - { question: "What is the capital city of Australia?", answer: "Canberra" }
  - { question: "Which planet has the most moons?", answer: "Saturn" }
  - { question: "How many minutes are in a full week?", answer: "10,080" }
  - { question: "What is the tallest mountain in Africa?", answer: "Mount Kilimanjaro" }
  - { question: "Which country has the most time zones?", answer: "France" }
  - { question: "What is the longest river in Asia?", answer: "Yangtze" }
  - { question: "How many keys does a standard piano have?", answer: "88" }
  - { question: "In which year did the Titanic sink?", answer: "1912" }
  - { question: "What is the smallest country in the world?", answer: "Vatican City" }
  - { question: "How many hearts does an octopus have?", answer: "3" }
```

`config/packs/science.yml`:

```yaml
name: Science
questions:
  - { question: "What is the chemical symbol for gold?", answer: "Au" }
  - { question: "How many teeth does an adult human usually have?", answer: "32" }
  - { question: "What is the hardest natural substance on Earth?", answer: "Diamond" }
  - { question: "At what temperature in Celsius does water boil at sea level?", answer: "100" }
  - { question: "About how many minutes does sunlight take to reach Earth?", answer: "8" }
  - { question: "Which gas do plants take in from the air?", answer: "Carbon dioxide" }
  - { question: "How many chromosomes does a human cell have?", answer: "46" }
  - { question: "What is the largest organ of the human body?", answer: "Skin" }
  - { question: "Roughly what is the speed of sound in air, in km per hour?", answer: "1,235" }
  - { question: "Which planet is called the Red Planet?", answer: "Mars" }
  - { question: "How many legs does a spider have?", answer: "8" }
  - { question: "What is the most common element in the universe?", answer: "Hydrogen" }
```

`config/packs/tech.yml`:

```yaml
name: Tech & Internet
questions:
  - { question: "What year was Google founded?", answer: "1998" }
  - { question: "What does HTTP stand for?", answer: "HyperText Transfer Protocol" }
  - { question: "Who created the Linux kernel?", answer: "Linus Torvalds" }
  - { question: "What year was the first version of Ruby released?", answer: "1995" }
  - { question: "How many bits are in a byte?", answer: "8" }
  - { question: "What dessert was Android 1.5 named after?", answer: "Cupcake" }
  - { question: "In what year was YouTube launched?", answer: "2005" }
  - { question: "What was Twitter's original character limit per tweet?", answer: "140" }
  - { question: "What does CPU stand for?", answer: "Central Processing Unit" }
  - { question: "Which company owns GitHub?", answer: "Microsoft" }
  - { question: "In what year was the first email sent?", answer: "1971" }
  - { question: "How many pixels wide is a 4K UHD screen?", answer: "3,840" }
```

`app/services/game/packs.rb`:

```ruby
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
```

**Step 4: Run, see it pass**

Run: `bundle exec rspec spec/services/game/packs_spec.rb`
Expected: `4 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: three question packs"
```

---

### Task 6: Create room and join room

**Files:**
- Create: `app/services/game/create_room.rb`, `app/services/game/join_room.rb`
- Test: `spec/services/game/create_room_spec.rb`, `spec/services/game/join_room_spec.rb`

**Step 1: Failing tests**

`spec/services/game/create_room_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::CreateRoom do
  it "makes a room with the creator as host" do
    room, player = described_class.call(name: " Nitish ")
    expect(room.code).to match(/\A[A-Z]{4}\z/)
    expect(room).to be_lobby
    expect(player.name).to eq("Nitish")
    expect(room.host?(player)).to be true
    expect(player.token).to be_present
  end

  it "rejects an empty name" do
    expect { described_class.call(name: "   ") }.to raise_error(Game::Error, /name/i)
  end

  it "rejects a long name" do
    expect { described_class.call(name: "a" * 17) }.to raise_error(Game::Error, /16/)
  end
end
```

`spec/services/game/join_room_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::JoinRoom do
  let!(:room) { Game::CreateRoom.call(name: "Host").first }

  it "joins with the code in any case" do
    joined, player = described_class.call(code: room.code.downcase, name: "Aman")
    expect(joined).to eq(room)
    expect(player.name).to eq("Aman")
    expect(player).not_to be_spectator
  end

  it "rejects an unknown code" do
    expect { described_class.call(code: "ZZZZ", name: "Aman") }.to raise_error(Game::Error, /not found/i)
  end

  it "rejects a closed room" do
    room.update!(status: "closed")
    expect { described_class.call(code: room.code, name: "Aman") }.to raise_error(Game::Error, /not found/i)
  end

  it "rejects a name already used in the room, ignoring case" do
    expect { described_class.call(code: room.code, name: "host") }.to raise_error(Game::Error, /taken/i)
  end

  it "rejects the 13th player" do
    11.times { |i| described_class.call(code: room.code, name: "P#{i}") }
    expect { described_class.call(code: room.code, name: "Late") }.to raise_error(Game::Error, /full/i)
  end

  it "makes a spectator when the game is running" do
    room.update!(status: "writing")
    _, player = described_class.call(code: room.code, name: "Late")
    expect(player).to be_spectator
  end
end
```

**Step 2: Run, see them fail**

Run: `bundle exec rspec spec/services/game/create_room_spec.rb spec/services/game/join_room_spec.rb`
Expected: FAIL, `uninitialized constant Game::CreateRoom`

**Step 3: Code**

`app/services/game/join_room.rb`:

```ruby
module Game
  class JoinRoom
    MAX_PLAYERS = 12
    NAME_MAX = 16

    def self.clean_name(raw)
      name = raw.to_s.strip.squeeze(" ")
      raise Game::Error, "Please enter a name" if name.empty?
      raise Game::Error, "Name must be #{NAME_MAX} letters or fewer" if name.length > NAME_MAX
      name
    end

    def self.call(code:, name:) = new(code, name).call

    def initialize(code, name)
      @code = code.to_s.upcase.strip
      @name = name
    end

    def call
      name = self.class.clean_name(@name)
      room = Room.find_by(code: @code)
      raise Game::Error, "Room not found. Check the code." if room.nil? || room.closed?

      room.with_lock do
        raise Game::Error, "Room is full (#{MAX_PLAYERS} players max)" if room.players.count >= MAX_PLAYERS
        raise Game::Error, "That name is taken in this room" if room.players.any? { |p| p.name.casecmp?(name) }

        player = room.players.create!(name: name, token: SecureRandom.hex(16), spectator: room.in_game?)
        room.update!(last_activity_at: Time.current)
        [room, player]
      end
    end
  end
end
```

`app/services/game/create_room.rb`:

```ruby
module Game
  class CreateRoom
    def self.call(name:)
      player_name = Game::JoinRoom.clean_name(name)
      Room.transaction do
        room = Room.create!(code: Game::CodeGenerator.unique, last_activity_at: Time.current)
        player = room.players.create!(name: player_name, token: SecureRandom.hex(16))
        room.update!(host_player_id: player.id)
        [room, player]
      end
    end
  end
end
```

**Step 4: Run, see them pass**

Run: `bundle exec rspec spec/services/game/create_room_spec.rb spec/services/game/join_room_spec.rb`
Expected: `9 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: create and join rooms"
```

---

### Task 7: Phase machine, timers and scoring

This is the core. `Game::Advance` moves a room from one phase to the next. A timer job calls it when time is up. It is also called early when every player is done. A **token** on the room stops an old timer from moving a phase that already moved.

**Files:**
- Create: `app/services/game/advance.rb`, `app/services/game/score.rb`, `app/services/game/options.rb`, `app/jobs/phase_timeout_job.rb`
- Test: `spec/services/game/advance_spec.rb`, `spec/services/game/options_spec.rb`

**Step 1: Failing tests**

`spec/services/game/options_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::Options do
  let(:room) { Room.create!(code: "ABCD") }
  let(:round) { room.rounds.create!(position: 0, question: "Q", answer: "Truth") }
  let(:p1) { room.players.create!(name: "A", token: "a") }
  let(:p2) { room.players.create!(name: "B", token: "b") }

  before do
    round.bluffs.create!(player: p1, text: "Fake one", normalized: "fake one")
    round.bluffs.create!(player: p2, text: "Fake two", normalized: "fake two")
  end

  it "mixes the truth in with the bluffs" do
    texts = described_class.for(round).map { |o| o[:text] }
    expect(texts).to match_array(["Fake one", "Fake two", "Truth"])
  end

  it "gives the same order every time for the same round" do
    expect(described_class.for(round).map { |o| o[:text] }).to eq(described_class.for(round).map { |o| o[:text] })
  end

  it "marks the truth with bluff nil" do
    truth = described_class.for(round).find { |o| o[:bluff].nil? }
    expect(truth[:text]).to eq("Truth")
  end
end
```

`spec/services/game/advance_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::Advance do
  let(:room) { Room.create!(code: "ABCD") }
  let!(:p1) { room.players.create!(name: "A", token: "a") }
  let!(:p2) { room.players.create!(name: "B", token: "b") }
  let!(:p3) { room.players.create!(name: "C", token: "c") }
  let!(:r0) { room.rounds.create!(position: 0, question: "Q0", answer: "T0") }
  let!(:r1) { room.rounds.create!(position: 1, question: "Q1", answer: "T1") }

  before { room.update!(host_player_id: p1.id) }

  describe ".enter" do
    it "sets the phase, a deadline and queues the timer job" do
      described_class.enter(room, "writing")
      expect(room.reload).to be_writing
      expect(room.phase_ends_at).to be_within(2.seconds).of(60.seconds.from_now)
      expect(room.phase_token).to be_present
      expect(PhaseTimeoutJob).to have_been_enqueued.with(room.id, room.phase_token)
    end
  end

  describe ".on_timeout" do
    it "moves writing to voting when the token matches" do
      described_class.enter(room, "writing")
      expect(described_class.on_timeout(room, room.phase_token)).to be true
      expect(room.reload).to be_voting
    end

    it "does nothing when the token is old" do
      described_class.enter(room, "writing")
      expect(described_class.on_timeout(room, "stale")).to be false
      expect(room.reload).to be_writing
    end
  end

  describe "voting -> reveal gives points" do
    it "gives 1000 for the truth and 500 per fooled player" do
      described_class.enter(room, "voting")
      b1 = r0.bluffs.create!(player: p1, text: "F1", normalized: "f1")
      r0.votes.create!(player: p2, bluff: b1)   # p2 fooled by p1
      r0.votes.create!(player: p3, bluff: nil)  # p3 found the truth
      described_class.on_timeout(room, room.phase_token)
      expect(room.reload).to be_reveal
      expect(p1.reload.score).to eq(500)
      expect(p2.reload.score).to eq(0)
      expect(p3.reload.score).to eq(1000)
    end
  end

  describe "reveal -> next round or finished" do
    it "goes to the next round" do
      described_class.enter(room, "reveal")
      described_class.on_timeout(room, room.phase_token)
      expect(room.reload).to be_writing
      expect(room.current_round_index).to eq(1)
    end

    it "finishes after the last round" do
      room.update!(current_round_index: 1)
      described_class.enter(room, "reveal")
      described_class.on_timeout(room, room.phase_token)
      expect(room.reload).to be_finished
      expect(room.phase_ends_at).to be_nil
    end
  end

  describe ".maybe_finish_phase" do
    it "ends writing early when every active player has a bluff" do
      described_class.enter(room, "writing")
      [p1, p2, p3].each { |p| r0.bluffs.create!(player: p, text: p.name, normalized: p.name.downcase) }
      expect(described_class.maybe_finish_phase(room)).to be true
      expect(room.reload).to be_voting
    end

    it "waits when someone has not written yet" do
      described_class.enter(room, "writing")
      r0.bluffs.create!(player: p1, text: "x", normalized: "x")
      expect(described_class.maybe_finish_phase(room)).to be false
      expect(room.reload).to be_writing
    end

    it "ignores players who are offline" do
      described_class.enter(room, "writing")
      p3.update!(connected: false)
      [p1, p2].each { |p| r0.bluffs.create!(player: p, text: p.name, normalized: p.name.downcase) }
      expect(described_class.maybe_finish_phase(room)).to be true
    end

    it "never advances when nobody is online" do
      described_class.enter(room, "writing")
      room.players.update_all(connected: false)
      expect(described_class.maybe_finish_phase(room)).to be false
    end
  end

  describe ".skip" do
    it "lets the host skip the reveal" do
      described_class.enter(room, "reveal")
      expect(described_class.skip(room, p1)).to be true
      expect(room.reload).to be_writing
    end

    it "stops a non host" do
      described_class.enter(room, "reveal")
      expect { described_class.skip(room, p2) }.to raise_error(Game::Error, /host/i)
    end

    it "does nothing outside reveal" do
      described_class.enter(room, "writing")
      expect(described_class.skip(room, p1)).to be false
    end
  end
end
```

**Step 2: Run, see them fail**

Run: `bundle exec rspec spec/services/game/advance_spec.rb spec/services/game/options_spec.rb`
Expected: FAIL, `uninitialized constant Game::Options`

**Step 3: Code**

`app/services/game/options.rb`:

```ruby
module Game
  module Options
    # The list players vote on: all bluffs plus the truth, in a fixed random order per round.
    def self.for(round)
      items = round.bluffs.includes(:player).order(:id).map { |b| { text: b.text, bluff: b } }
      items << { text: round.answer, bluff: nil }
      items.shuffle(random: Random.new(round.id * 7919))
    end
  end
end
```

`app/services/game/score.rb`:

```ruby
module Game
  module Score
    TRUTH_POINTS = 1000
    FOOL_POINTS = 500

    def self.call(round)
      round.votes.includes(:bluff, :player).each do |vote|
        if vote.truth?
          vote.player.increment!(:score, TRUTH_POINTS)
        else
          vote.bluff.player.increment!(:score, FOOL_POINTS)
        end
      end
    end
  end
end
```

`app/services/game/advance.rb`:

```ruby
module Game
  class Advance
    DURATIONS = { "writing" => 60, "voting" => 30, "reveal" => 10 }.freeze

    # Put the room into a phase, set the deadline, and queue the timer.
    def self.enter(room, status)
      token = SecureRandom.hex(8)
      seconds = DURATIONS.fetch(status)
      room.update!(status: status, phase_token: token, phase_ends_at: seconds.seconds.from_now,
        last_activity_at: Time.current)
      PhaseTimeoutJob.set(wait: seconds.seconds).perform_later(room.id, token)
    end

    # Called by the timer job. The token check stops an old timer from acting twice.
    def self.on_timeout(room, token)
      room.with_lock do
        return false unless room.in_game? && room.phase_token == token
        next_phase(room)
        true
      end
    end

    # Called after every bluff or vote. Ends the phase early when everyone online is done.
    def self.maybe_finish_phase(room)
      room.with_lock do
        return false unless room.writing? || room.voting?
        players = room.active_players.to_a
        return false if players.empty?
        return false unless players.all? { |p| done?(room, p) }
        next_phase(room)
        true
      end
    end

    # Host presses "Next" during the reveal.
    def self.skip(room, player)
      raise Game::Error, "Only the host can do that" unless room.host?(player)
      room.with_lock do
        return false unless room.reveal?
        next_phase(room)
        true
      end
    end

    def self.done?(room, player)
      round = room.current_round
      return false if round.nil?
      if room.writing?
        round.bluffs.exists?(player_id: player.id)
      else
        round.votes.exists?(player_id: player.id)
      end
    end

    def self.next_phase(room)
      case room.status
      when "writing"
        enter(room, "voting")
      when "voting"
        Game::Score.call(room.current_round)
        enter(room, "reveal")
      when "reveal"
        if room.current_round_index + 1 >= room.rounds.count
          room.update!(status: "finished", phase_token: nil, phase_ends_at: nil)
        else
          room.update!(current_round_index: room.current_round_index + 1)
          enter(room, "writing")
        end
      end
    end
  end
end
```

`app/jobs/phase_timeout_job.rb`:

```ruby
class PhaseTimeoutJob < ApplicationJob
  queue_as :default

  def perform(room_id, token)
    room = Room.find_by(id: room_id)
    return if room.nil?
    Game::Broadcast.call(room) if Game::Advance.on_timeout(room, token)
  end
end
```

`Game::Broadcast` comes in Task 10. For now add a stub so the job loads:

`app/services/game/broadcast.rb`:

```ruby
module Game
  module Broadcast
    def self.call(room)
      # Filled in Task 10.
    end
  end
end
```

**Step 4: Run, see them pass**

Run: `bundle exec rspec spec/services/game/advance_spec.rb spec/services/game/options_spec.rb`
Expected: `16 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: phase machine, timer job, scoring"
```

---

### Task 8: Start game, submit bluff, submit vote, play again

**Files:**
- Create: `app/services/game/start.rb`, `app/services/game/submit_bluff.rb`, `app/services/game/submit_vote.rb`, `app/services/game/play_again.rb`
- Test: `spec/services/game/start_spec.rb`, `spec/services/game/submit_bluff_spec.rb`, `spec/services/game/submit_vote_spec.rb`, `spec/services/game/play_again_spec.rb`

**Step 1: Failing tests**

`spec/services/game/start_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::Start do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  it "builds rounds from the pack and enters writing" do
    described_class.call(room: room, player: host, pack: "science", question_count: 4)
    expect(room.reload).to be_writing
    expect(room.rounds.count).to eq(4)
    expect(room.pack).to eq("science")
    expect(room.current_round_index).to eq(0)
    expect(PhaseTimeoutJob).to have_been_enqueued
  end

  it "caps the question count at 10 and floors at 1" do
    described_class.call(room: room, player: host, pack: "general", question_count: 99)
    expect(room.rounds.count).to eq(10)
  end

  it "only the host can start" do
    expect { described_class.call(room: room, player: guest, pack: "general", question_count: 3) }
      .to raise_error(Game::Error, /host/i)
  end

  it "needs two players" do
    guest.update!(connected: false)
    expect { described_class.call(room: room, player: host, pack: "general", question_count: 3) }
      .to raise_error(Game::Error, /2 players/i)
  end

  it "rejects an unknown pack" do
    expect { described_class.call(room: room, player: host, pack: "nope", question_count: 3) }
      .to raise_error(Game::Error, /pack/i)
  end

  it "uses custom questions and skips blank ones" do
    custom = [
      { "question" => "Our first product?", "answer" => "HowNow" },
      { "question" => "", "answer" => "x" }
    ]
    described_class.call(room: room, player: host, pack: "custom", question_count: 5, custom_questions: custom)
    expect(room.rounds.count).to eq(1)
    expect(room.rounds.first.answer).to eq("HowNow")
  end

  it "rejects a custom pack with no usable questions" do
    expect { described_class.call(room: room, player: host, pack: "custom", question_count: 5, custom_questions: []) }
      .to raise_error(Game::Error, /custom question/i)
  end

  it "resets scores and spectators" do
    guest.update!(score: 900, spectator: true)
    host.update!(score: 100)
    expect { described_class.call(room: room, player: host, pack: "general", question_count: 3) }
      .to raise_error(Game::Error, /2 players/i)
    guest.update!(spectator: false)
    described_class.call(room: room, player: host, pack: "general", question_count: 3)
    expect(room.players.pluck(:score)).to all(eq(0))
  end
end
```

`spec/services/game/submit_bluff_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::SubmitBluff do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  before do
    room.rounds.create!(position: 0, question: "Capital of Australia?", answer: "Canberra")
    Game::Advance.enter(room, "writing")
  end

  it "saves the bluff" do
    bluff = described_class.call(room: room, player: host, text: "  Sydney ")
    expect(bluff.text).to eq("Sydney")
    expect(bluff.normalized).to eq("sydney")
  end

  it "lets a player change their bluff before time is up" do
    described_class.call(room: room, player: host, text: "Sydney")
    described_class.call(room: room, player: host, text: "Perth")
    expect(room.current_round.bluffs.where(player: host).pluck(:text)).to eq(["Perth"])
  end

  it "rejects the real answer" do
    expect { described_class.call(room: room, player: host, text: "the canberra!") }
      .to raise_error(Game::Error, /too close/i)
  end

  it "rejects a bluff another player already wrote" do
    described_class.call(room: room, player: host, text: "Sydney")
    expect { described_class.call(room: room, player: guest, text: "SYDNEY") }
      .to raise_error(Game::Error, /already/i)
  end

  it "rejects empty and long text" do
    expect { described_class.call(room: room, player: host, text: " ") }.to raise_error(Game::Error, /type/i)
    expect { described_class.call(room: room, player: host, text: "x" * 61) }.to raise_error(Game::Error, /60/)
  end

  it "rejects outside the writing phase" do
    room.update!(status: "voting")
    expect { described_class.call(room: room, player: host, text: "Sydney") }.to raise_error(Game::Error, /writing/i)
  end

  it "rejects a spectator" do
    guest.update!(spectator: true)
    expect { described_class.call(room: room, player: guest, text: "Sydney") }.to raise_error(Game::Error, /watching/i)
  end

  it "moves to voting when everyone has written" do
    described_class.call(room: room, player: host, text: "Sydney")
    expect(room.reload).to be_writing
    described_class.call(room: room, player: guest, text: "Perth")
    expect(room.reload).to be_voting
  end
end
```

`spec/services/game/submit_vote_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::SubmitVote do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let(:round) { room.rounds.create!(position: 0, question: "Q", answer: "Truth") }
  let(:options) { Game::Options.for(round) }

  before do
    round.bluffs.create!(player: host, text: "Host fake", normalized: "host fake")
    round.bluffs.create!(player: guest, text: "Guest fake", normalized: "guest fake")
    Game::Advance.enter(room, "voting")
  end

  def index_of(text) = options.index { |o| o[:text] == text }

  it "saves a vote for the truth" do
    vote = described_class.call(room: room, player: host, option_index: index_of("Truth"))
    expect(vote).to be_truth
  end

  it "saves a vote for a bluff" do
    vote = described_class.call(room: room, player: host, option_index: index_of("Guest fake"))
    expect(vote.bluff.player).to eq(guest)
  end

  it "rejects voting for your own bluff" do
    expect { described_class.call(room: room, player: host, option_index: index_of("Host fake")) }
      .to raise_error(Game::Error, /own/i)
  end

  it "rejects a bad index" do
    expect { described_class.call(room: room, player: host, option_index: 99) }.to raise_error(Game::Error, /pick/i)
  end

  it "rejects a second vote" do
    described_class.call(room: room, player: host, option_index: index_of("Truth"))
    expect { described_class.call(room: room, player: host, option_index: index_of("Truth")) }
      .to raise_error(Game::Error, /already/i)
  end

  it "rejects outside voting" do
    room.update!(status: "writing")
    expect { described_class.call(room: room, player: host, option_index: 0) }.to raise_error(Game::Error, /voting/i)
  end

  it "moves to reveal when everyone has voted" do
    described_class.call(room: room, player: host, option_index: index_of("Truth"))
    described_class.call(room: room, player: guest, option_index: index_of("Truth"))
    expect(room.reload).to be_reveal
    expect(host.reload.score).to eq(1000)
  end
end
```

`spec/services/game/play_again_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::PlayAgain do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let!(:gone) { Game::JoinRoom.call(code: room.code, name: "Gone").last }

  before do
    round = room.rounds.create!(position: 0, question: "Q", answer: "T")
    round.bluffs.create!(player: gone, text: "x", normalized: "x")
    room.players.update_all(score: 500)
    guest.update!(spectator: true)
    gone.update!(connected: false)
    room.update!(status: "finished")
  end

  it "resets the room to the lobby" do
    described_class.call(room: room, player: host)
    expect(room.reload).to be_lobby
    expect(room.rounds.count).to eq(0)
    expect(room.players.pluck(:score)).to all(eq(0))
    expect(guest.reload).not_to be_spectator
  end

  it "drops players who left" do
    described_class.call(room: room, player: host)
    expect(room.players.pluck(:name)).to match_array(%w[Host Guest])
  end

  it "only the host can restart" do
    expect { described_class.call(room: room, player: guest) }.to raise_error(Game::Error, /host/i)
  end

  it "refuses while a game is running" do
    room.update!(status: "voting")
    expect { described_class.call(room: room, player: host) }.to raise_error(Game::Error, /running/i)
  end
end
```

**Step 2: Run, see them fail**

Run: `bundle exec rspec spec/services/game/start_spec.rb spec/services/game/submit_bluff_spec.rb spec/services/game/submit_vote_spec.rb spec/services/game/play_again_spec.rb`
Expected: FAIL, `uninitialized constant Game::Start`

**Step 3: Code**

`app/services/game/start.rb`:

```ruby
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
```

`app/services/game/submit_bluff.rb`:

```ruby
module Game
  class SubmitBluff
    MAX_LENGTH = 60

    def self.call(room:, player:, text:)
      raise Game::Error, "Not the writing phase" unless room.writing?
      raise Game::Error, "You are watching this game. You can play the next one." if player.spectator?

      text = text.to_s.strip.squeeze(" ")
      raise Game::Error, "Type an answer first" if text.empty?
      raise Game::Error, "Keep it under #{MAX_LENGTH} characters" if text.length > MAX_LENGTH

      round = room.current_round
      norm = Game::Text.normalize(text)
      raise Game::Error, "Too close to the real answer. Try another." if norm == Game::Text.normalize(round.answer)
      if round.bluffs.where(normalized: norm).where.not(player_id: player.id).exists?
        raise Game::Error, "Someone already wrote that. Try another."
      end

      bluff = round.bluffs.find_or_initialize_by(player_id: player.id)
      bluff.update!(text: text, normalized: norm)
      Game::Advance.maybe_finish_phase(room)
      bluff
    end
  end
end
```

`app/services/game/submit_vote.rb`:

```ruby
module Game
  class SubmitVote
    def self.call(room:, player:, option_index:)
      raise Game::Error, "Not the voting phase" unless room.voting?
      raise Game::Error, "You are watching this game. You can play the next one." if player.spectator?

      round = room.current_round
      option = Game::Options.for(round)[option_index.to_i]
      raise Game::Error, "Pick an answer from the list" if option.nil? || option_index.to_i.negative?
      raise Game::Error, "That is your own bluff!" if option[:bluff]&.player_id == player.id
      raise Game::Error, "You already voted" if round.votes.exists?(player_id: player.id)

      vote = round.votes.create!(player: player, bluff: option[:bluff])
      Game::Advance.maybe_finish_phase(room)
      vote
    end
  end
end
```

`app/services/game/play_again.rb`:

```ruby
module Game
  class PlayAgain
    def self.call(room:, player:)
      raise Game::Error, "Only the host can restart" unless room.host?(player)
      raise Game::Error, "Game is still running" unless room.finished? || room.lobby?

      Room.transaction do
        room.rounds.destroy_all
        room.players.where(connected: false).destroy_all
        room.players.update_all(score: 0, spectator: false)
        room.update!(status: "lobby", current_round_index: 0, phase_token: nil, phase_ends_at: nil,
          last_activity_at: Time.current)
      end
    end
  end
end
```

**Step 4: Run, see them pass**

Run: `bundle exec rspec spec/services`
Expected: all pass, `0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: start game, bluffs, votes, play again"
```

---

### Task 9: Presence and host hand-over

When a player's socket closes we mark them offline. If the host goes offline, a job runs 30 seconds later and gives host to the next online player.

**Files:**
- Create: `app/services/game/presence.rb`, `app/jobs/host_migration_job.rb`
- Test: `spec/services/game/presence_spec.rb`

**Step 1: Failing test**

`spec/services/game/presence_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::Presence do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  it "marks a player online" do
    host.update!(connected: false)
    described_class.connected(host)
    expect(host.reload).to be_connected
  end

  it "marks a player offline and queues host hand-over for the host" do
    described_class.disconnected(host)
    expect(host.reload).not_to be_connected
    expect(HostMigrationJob).to have_been_enqueued.with(room.id, host.id)
  end

  it "does not queue hand-over for a guest" do
    described_class.disconnected(guest)
    expect(HostMigrationJob).not_to have_been_enqueued
  end

  it "ends the phase early if the leaver was the last one not done" do
    room.rounds.create!(position: 0, question: "Q", answer: "T")
    Game::Advance.enter(room, "writing")
    room.current_round.bluffs.create!(player: guest, text: "x", normalized: "x")
    described_class.disconnected(host)
    expect(room.reload).to be_voting
  end

  describe ".migrate_host" do
    it "gives host to the next online player" do
      host.update!(connected: false)
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(guest.id)
    end

    it "does nothing if the host came back" do
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(host.id)
    end

    it "does nothing if host already changed" do
      room.update!(host_player_id: guest.id)
      host.update!(connected: false)
      described_class.migrate_host(room, host.id)
      expect(room.reload.host_player_id).to eq(guest.id)
    end
  end
end
```

**Step 2: Run, see it fail**

Run: `bundle exec rspec spec/services/game/presence_spec.rb`
Expected: FAIL, `uninitialized constant Game::Presence`

**Step 3: Code**

`app/services/game/presence.rb`:

```ruby
module Game
  module Presence
    HOST_GRACE_SECONDS = 30

    def self.connected(player)
      player.update!(connected: true)
      player.room.update!(last_activity_at: Time.current)
    end

    def self.disconnected(player)
      player.update!(connected: false)
      room = player.room
      HostMigrationJob.set(wait: HOST_GRACE_SECONDS.seconds).perform_later(room.id, player.id) if room.host?(player)
      Game::Advance.maybe_finish_phase(room) if room.in_game?
    end

    def self.migrate_host(room, old_host_id)
      room.with_lock do
        return unless room.host_player_id == old_host_id
        old = room.players.find_by(id: old_host_id)
        return if old&.connected?
        new_host = room.players.where(connected: true).order(:id).first
        return if new_host.nil?
        room.update!(host_player_id: new_host.id)
      end
    end
  end
end
```

`app/jobs/host_migration_job.rb`:

```ruby
class HostMigrationJob < ApplicationJob
  queue_as :default

  def perform(room_id, old_host_id)
    room = Room.find_by(id: room_id)
    return if room.nil?
    Game::Presence.migrate_host(room, old_host_id)
    Game::Broadcast.call(room)
  end
end
```

**Step 4: Run, see it pass**

Run: `bundle exec rspec spec/services/game/presence_spec.rb`
Expected: `7 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: player presence and host hand-over"
```

---

### Task 10: State JSON and broadcast

`Game::State` builds the JSON every browser draws. It never includes who wrote which bluff during voting, so nobody can cheat by reading the network tab.

**Files:**
- Create: `app/services/game/state.rb`
- Modify: `app/services/game/broadcast.rb`, `app/channels/room_channel.rb` (created in Task 11, so Broadcast references `RoomChannel` lazily)
- Test: `spec/services/game/state_spec.rb`

**Step 1: Failing test**

`spec/services/game/state_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Game::State do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }
  let(:round) { room.rounds.create!(position: 0, question: "Q?", answer: "Truth") }

  it "describes the lobby" do
    s = described_class.call(room)
    expect(s[:code]).to eq(room.code)
    expect(s[:status]).to eq("lobby")
    expect(s[:host_id]).to eq(host.id)
    expect(s[:players].map { |p| p[:name] }).to eq(%w[Host Guest])
    expect(s[:packs].map { |p| p[:key] }).to include("general")
    expect(s[:round]).to be_nil
    expect(s[:reveal]).to be_nil
  end

  it "shows the question and who is done during writing" do
    round.bluffs.create!(player: host, text: "x", normalized: "x")
    Game::Advance.enter(room, "writing")
    s = described_class.call(room)
    expect(s[:round][:question]).to eq("Q?")
    expect(s[:round][:index]).to eq(0)
    expect(s[:round][:total]).to eq(1)
    expect(s[:round][:phase_ends_at]).to be_present
    expect(s[:players].find { |p| p[:id] == host.id }[:done]).to be true
    expect(s[:players].find { |p| p[:id] == guest.id }[:done]).to be false
    expect(s[:round]).not_to have_key(:options)
  end

  it "lists options during voting without authors or the truth flag" do
    round.bluffs.create!(player: host, text: "Fake", normalized: "fake")
    Game::Advance.enter(room, "voting")
    s = described_class.call(room)
    expect(s[:round][:options].map { |o| o[:text] }).to match_array(%w[Fake Truth])
    expect(s[:round][:options].first.keys).to match_array(%i[index text])
  end

  it "shows everything during reveal" do
    bluff = round.bluffs.create!(player: host, text: "Fake", normalized: "fake")
    round.votes.create!(player: guest, bluff: bluff)
    round.votes.create!(player: host, bluff: nil)
    Game::Advance.enter(room, "reveal")
    s = described_class.call(room)
    expect(s[:reveal][:answer]).to eq("Truth")
    fake = s[:reveal][:options].find { |o| o[:text] == "Fake" }
    expect(fake).to include(truth: false, author: "Host", voters: ["Guest"], points: 500)
    truth = s[:reveal][:options].find { |o| o[:truth] }
    expect(truth).to include(voters: ["Host"], points: 1000)
  end
end
```

**Step 2: Run, see it fail**

Run: `bundle exec rspec spec/services/game/state_spec.rb`
Expected: FAIL, `uninitialized constant Game::State`

**Step 3: Code**

`app/services/game/state.rb`:

```ruby
module Game
  class State
    def self.call(room) = new(room).to_h

    def initialize(room)
      @room = room
      @round = room.current_round if room.in_game?
    end

    def to_h
      {
        code: @room.code,
        status: @room.status,
        host_id: @room.host_player_id,
        settings: { pack: @room.pack, question_count: @room.question_count },
        packs: Game::Packs.summary,
        players: players,
        round: round_payload,
        reveal: reveal_payload,
        server_time: Time.current.iso8601(3)
      }
    end

    private

    def players
      @room.players.order(:id).map do |p|
        { id: p.id, name: p.name, score: p.score, connected: p.connected, spectator: p.spectator,
          done: done_ids.include?(p.id) }
      end
    end

    def done_ids
      @done_ids ||= if @round.nil? then []
      elsif @room.writing? then @round.bluffs.pluck(:player_id)
      elsif @room.voting? then @round.votes.pluck(:player_id)
      else []
      end
    end

    def round_payload
      return nil if @round.nil?
      h = { index: @room.current_round_index, total: @room.rounds.count, question: @round.question,
        phase_ends_at: @room.phase_ends_at&.iso8601(3) }
      h[:options] = Game::Options.for(@round).map.with_index { |o, i| { index: i, text: o[:text] } } if @room.voting?
      h
    end

    def reveal_payload
      return nil unless @room.reveal? && @round
      votes = @round.votes.includes(:player).to_a
      options = Game::Options.for(@round).map do |o|
        bluff = o[:bluff]
        voters = votes.select { |v| v.bluff_id == bluff&.id }.map { |v| v.player.name }
        per_vote = bluff ? Game::Score::FOOL_POINTS : Game::Score::TRUTH_POINTS
        { text: o[:text], truth: bluff.nil?, author: bluff&.player&.name, voters: voters,
          points: voters.size * per_vote }
      end
      { answer: @round.answer, options: options }
    end
  end
end
```

Replace `app/services/game/broadcast.rb`:

```ruby
module Game
  module Broadcast
    def self.call(room)
      room.reload
      RoomChannel.broadcast_to(room, Game::State.call(room))
    end
  end
end
```

**Step 4: Run, see it pass**

Run: `bundle exec rspec spec/services/game/state_spec.rb`
Expected: `4 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: room state JSON and broadcast"
```

---

### Task 11: Action Cable channel

The browser opens one channel per room with its player token. The server replies to that one player with `transmit` (hello, errors, bluff saved) and to the whole room with `broadcast_to`.

**Files:**
- Create: `app/channels/room_channel.rb`
- Test: `spec/channels/room_channel_spec.rb`

**Step 1: Failing test**

`spec/channels/room_channel_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RoomChannel, type: :channel do
  let!(:room_and_host) { Game::CreateRoom.call(name: "Host") }
  let(:room) { room_and_host.first }
  let(:host) { room_and_host.last }
  let!(:guest) { Game::JoinRoom.call(code: room.code, name: "Guest").last }

  it "subscribes with a good code and token, and sends hello plus state" do
    subscribe(code: room.code.downcase, token: host.token)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(room)
    expect(transmissions.first).to include("type" => "hello", "player_id" => host.id)
  end

  it "rejects a bad token" do
    subscribe(code: room.code, token: "nope")
    expect(subscription).to be_rejected
  end

  it "marks the player offline on unsubscribe" do
    subscribe(code: room.code, token: guest.token)
    unsubscribe
    expect(guest.reload).not_to be_connected
  end

  it "sends an error message back to only this player" do
    subscribe(code: room.code, token: guest.token)
    perform :start_game, pack: "general", question_count: 3
    expect(transmissions.last).to include("type" => "error", "message" => "Only the host can start")
  end

  it "starts the game and broadcasts" do
    subscribe(code: room.code, token: host.token)
    expect { perform :start_game, pack: "general", question_count: 3 }
      .to have_broadcasted_to(room).with(hash_including(status: "writing"))
  end

  it "replies bluff_ok with the text after a bluff" do
    room.rounds.create!(position: 0, question: "Q", answer: "T")
    Game::Advance.enter(room, "writing")
    subscribe(code: room.code, token: host.token)
    perform :submit_bluff, text: "Fake"
    expect(transmissions.last).to include("type" => "bluff_ok", "text" => "Fake")
  end
end
```

**Step 2: Run, see it fail**

Run: `bundle exec rspec spec/channels/room_channel_spec.rb`
Expected: FAIL, `uninitialized constant RoomChannel`

**Step 3: Code**

`app/channels/room_channel.rb`:

```ruby
class RoomChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find_by(code: params[:code].to_s.upcase)
    @player = @room&.players&.find_by(token: params[:token].to_s)
    return reject if @player.nil? || @room.closed?

    stream_for @room
    Game::Presence.connected(@player)
    transmit(hello)
    Game::Broadcast.call(@room)
  end

  def unsubscribed
    return if @player.nil?
    Game::Presence.disconnected(@player)
    Game::Broadcast.call(@room)
  end

  def start_game(data)
    run do
      Game::Start.call(room: room, player: player, pack: data["pack"], question_count: data["question_count"],
        custom_questions: data["custom_questions"])
    end
  end

  def submit_bluff(data)
    run do
      bluff = Game::SubmitBluff.call(room: room, player: player, text: data["text"])
      transmit(type: "bluff_ok", text: bluff.text)
    end
  end

  def submit_vote(data)
    run { Game::SubmitVote.call(room: room, player: player, option_index: data["index"]) }
  end

  def next_round
    run { Game::Advance.skip(room, player) }
  end

  def play_again
    run { Game::PlayAgain.call(room: room, player: player) }
  end

  # Backup for the timer job: a browser whose countdown hit zero asks the server to check.
  def tick
    run do
      r = room
      Game::Advance.on_timeout(r, r.phase_token) if r.phase_ends_at && r.phase_ends_at <= Time.current
    end
  end

  private

  def room = @room.reload
  def player = @player.reload

  def run
    yield
    Game::Broadcast.call(@room)
  rescue Game::Error => e
    transmit(type: "error", message: e.message)
  end

  def hello
    bluff = @room.in_game? ? @room.current_round&.bluffs&.find_by(player_id: @player.id) : nil
    { type: "hello", player_id: @player.id, my_bluff: bluff&.text }
  end
end
```

Check `app/channels/application_cable/connection.rb` and `channel.rb` exist (rails new makes them). No changes needed.

**Step 4: Run, see it pass**

Run: `bundle exec rspec spec/channels/room_channel_spec.rb`
Expected: `6 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: room channel"
```

---

### Task 12: HTTP routes and controllers

Two JSON endpoints to create and join, one page.

**Files:**
- Create: `app/controllers/pages_controller.rb`, `app/controllers/rooms_controller.rb`, `app/controllers/players_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/rooms_spec.rb`

**Step 1: Failing test**

`spec/requests/rooms_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Rooms and players" do
  it "creates a room" do
    post "/rooms", params: { name: "Nitish" }, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["code"]).to match(/\A[A-Z]{4}\z/)
    expect(body["token"]).to be_present
    expect(body["player_id"]).to be_present
  end

  it "returns the error message for a bad name" do
    post "/rooms", params: { name: "" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to match(/name/i)
  end

  it "joins a room" do
    room = Game::CreateRoom.call(name: "Host").first
    post "/players", params: { code: room.code, name: "Aman" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["code"]).to eq(room.code)
  end

  it "returns an error for a bad code" do
    post "/players", params: { code: "ZZZZ", name: "Aman" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "serves the page at / and /r/CODE" do
    get "/"
    expect(response).to have_http_status(:ok)
    get "/r/ABCD"
    expect(response).to have_http_status(:ok)
  end
end
```

**Step 2: Run, see it fail**

Run: `bundle exec rspec spec/requests/rooms_spec.rb`
Expected: FAIL, routing errors

**Step 3: Code**

`config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "pages#home"
  get "r/:code", to: "pages#home", as: :room_link
  post "rooms", to: "rooms#create"
  post "players", to: "players#create"
  get "up", to: "rails/health#show", as: :rails_health_check
end
```

`app/controllers/pages_controller.rb`:

```ruby
class PagesController < ApplicationController
  def home
    @prefill_code = params[:code].to_s.upcase.first(4)
  end
end
```

`app/controllers/rooms_controller.rb`:

```ruby
class RoomsController < ApplicationController
  def create
    room, player = Game::CreateRoom.call(name: params[:name])
    render json: { code: room.code, token: player.token, player_id: player.id }
  rescue Game::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
```

`app/controllers/players_controller.rb`:

```ruby
class PlayersController < ApplicationController
  def create
    room, player = Game::JoinRoom.call(code: params[:code], name: params[:name])
    render json: { code: room.code, token: player.token, player_id: player.id }
  rescue Game::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
```

Make an empty view for now so the page test passes: `app/views/pages/home.html.erb` with the text `Bluff Club`. Task 13 fills it.

**Step 4: Run, see it pass**

Run: `bundle exec rspec spec/requests/rooms_spec.rb`
Expected: `5 examples, 0 failures`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: create and join endpoints, home page"
```

---

### Task 13: The page (HTML)

One page, six screens. Only one screen is shown at a time. The JS in Task 14 switches them.

**Files:**
- Modify: `app/views/layouts/application.html.erb`, `app/views/pages/home.html.erb`, `config/importmap.rb`

**Step 1: Layout**

`app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>Bluff Club</title>
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <meta name="description" content="A party game. Write a fake answer, fool your friends, find the truth. Join with a room code, no login.">
    <meta name="theme-color" content="#14121f">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application" %>
    <%= javascript_importmap_tags %>
  </head>
  <body>
    <%= yield %>
  </body>
</html>
```

`config/importmap.rb`:

```ruby
pin "application"
pin "@rails/actioncable", to: "actioncable.esm.js"
```

**Step 2: Page**

`app/views/pages/home.html.erb`:

```erb
<div id="status-bar" class="status-bar" hidden>Reconnecting…</div>
<div id="toast" class="toast" hidden></div>

<main class="app" data-prefill-code="<%= @prefill_code %>">

  <!-- HOME -->
  <section id="screen-home" class="screen">
    <h1 class="logo">Bluff Club</h1>
    <p class="tagline">Write a fake answer. Fool your friends. Spot the truth.</p>
    <label class="field">
      <span>Your name</span>
      <input id="name-input" maxlength="16" autocomplete="nickname" placeholder="e.g. Nitish">
    </label>
    <button id="create-btn" class="btn primary">Create a room</button>
    <div class="divider">or join one</div>
    <label class="field">
      <span>Room code</span>
      <input id="code-input" maxlength="4" autocapitalize="characters" autocomplete="off" placeholder="ABCD">
    </label>
    <button id="join-btn" class="btn">Join room</button>
    <button id="how-btn" class="link">How to play</button>
  </section>

  <!-- LOBBY -->
  <section id="screen-lobby" class="screen" hidden>
    <p class="label">Room code</p>
    <h2 id="lobby-code" class="code"></h2>
    <button id="copy-btn" class="btn small">Copy invite link</button>
    <p class="hint">Friends open the link or type the code on <span id="site-host"></span></p>
    <h3>Players <span id="lobby-count"></span></h3>
    <ul id="lobby-players" class="players"></ul>
    <div id="host-settings" hidden>
      <label class="field">
        <span>Question pack</span>
        <select id="pack-select"></select>
      </label>
      <label class="field">
        <span>Questions</span>
        <select id="count-select">
          <option>3</option><option>5</option><option selected>6</option><option>8</option><option>10</option>
        </select>
      </label>
      <label class="field" id="custom-field" hidden>
        <span>Your questions, one per line: <code>Question? | Answer</code></span>
        <textarea id="custom-input" rows="5" placeholder="What was our first product? | HowNow"></textarea>
      </label>
      <button id="start-btn" class="btn primary">Start game</button>
    </div>
    <p id="lobby-wait" class="hint" hidden>Waiting for the host to start…</p>
  </section>

  <!-- WRITING -->
  <section id="screen-writing" class="screen" hidden>
    <div class="topbar"><span id="writing-round"></span><span id="writing-timer" class="timer"></span></div>
    <h2 id="writing-question" class="question"></h2>
    <div id="writing-form">
      <label class="field">
        <span>Write a fake answer that sounds real</span>
        <input id="bluff-input" maxlength="60" autocomplete="off">
      </label>
      <button id="bluff-btn" class="btn primary">Submit bluff</button>
    </div>
    <p id="writing-done" class="hint" hidden>Bluff sent. Waiting for the others…</p>
    <ul id="writing-players" class="players compact"></ul>
  </section>

  <!-- VOTING -->
  <section id="screen-voting" class="screen" hidden>
    <div class="topbar"><span id="voting-round"></span><span id="voting-timer" class="timer"></span></div>
    <h2 id="voting-question" class="question"></h2>
    <p class="hint">Tap the answer you think is true</p>
    <div id="options" class="options"></div>
    <p id="voting-done" class="hint" hidden>Vote locked. Waiting for the others…</p>
  </section>

  <!-- REVEAL -->
  <section id="screen-reveal" class="screen" hidden>
    <div class="topbar"><span id="reveal-round"></span><span id="reveal-timer" class="timer"></span></div>
    <h2 id="reveal-question" class="question"></h2>
    <div id="reveal-list" class="reveal"></div>
    <h3>Scores</h3>
    <ol id="reveal-scores" class="scores"></ol>
    <button id="next-btn" class="btn" hidden>Next question</button>
  </section>

  <!-- FINISHED -->
  <section id="screen-finished" class="screen" hidden>
    <h2>Final scores</h2>
    <ol id="final-scores" class="scores big"></ol>
    <button id="again-btn" class="btn primary" hidden>Play again</button>
    <p id="again-wait" class="hint" hidden>Waiting for the host to start a new game…</p>
    <button id="leave-btn" class="link">Leave room</button>
  </section>

  <!-- HOW TO PLAY -->
  <section id="screen-how" class="screen" hidden>
    <h2>How to play</h2>
    <ol class="how">
      <li>Everyone sees a trivia question.</li>
      <li>Each player writes a <b>fake</b> answer that sounds real.</li>
      <li>All fakes are mixed with the real answer.</li>
      <li>Pick the one you think is true.</li>
      <li><b>+1000</b> if you find the truth. <b>+500</b> for each friend who picks your fake.</li>
    </ol>
    <p class="hint">Best with 3 to 8 players. Works on any phone or laptop.</p>
    <button id="how-close" class="btn">Got it</button>
  </section>
</main>
```

**Step 3: Check it renders**

Run: `bundle exec rspec spec/requests/rooms_spec.rb`
Expected: still `5 examples, 0 failures`

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: page markup for all screens"
```

---

### Task 14: The JavaScript

One file. It keeps the last state from the server and redraws the screen from it. It saves the player token in `localStorage` under the room code, so a refresh brings the player back.

**Files:**
- Create: `app/javascript/application.js`

**Step 1: Code**

`app/javascript/application.js`:

```javascript
import { createConsumer } from "@rails/actioncable"

const $ = (id) => document.getElementById(id)
const SCREENS = ["home", "lobby", "writing", "voting", "reveal", "finished", "how"]

let consumer = null
let sub = null
let state = null
let me = { id: null, bluff: null }
let session = { code: null }
let offsetMs = 0
let tickSent = false
let lastScreen = "home"

// ---------- small helpers ----------

function show(name) {
  SCREENS.forEach((s) => { $(`screen-${s}`).hidden = s !== name })
  if (name !== "how") lastScreen = name
  window.scrollTo(0, 0)
}

let toastTimer = null
function toast(msg) {
  const el = $("toast")
  el.textContent = msg
  el.hidden = false
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { el.hidden = true }, 3000)
}

function setBusy(btn, busy) {
  btn.disabled = busy
  btn.classList.toggle("busy", busy)
}

function store(key, value) { try { localStorage.setItem(key, value) } catch (_) {} }
function load(key) { try { return localStorage.getItem(key) } catch (_) { return null } }
function forget(key) { try { localStorage.removeItem(key) } catch (_) {} }

async function post(url, body) {
  const token = document.querySelector("meta[name=csrf-token]")?.content
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
    body: JSON.stringify(body)
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data.error || "Something went wrong. Try again.")
  return data
}

function isHost() { return state && state.host_id === me.id }
function myPlayer() { return state?.players.find((p) => p.id === me.id) }

// ---------- connection ----------

function connect(code, token) {
  session = { code }
  consumer ||= createConsumer()
  if (sub) sub.unsubscribe()
  tickSent = false
  sub = consumer.subscriptions.create({ channel: "RoomChannel", code, token }, {
    received(data) {
      if (data.type === "hello") { me.id = data.player_id; me.bluff = data.my_bluff; return }
      if (data.type === "error") { toast(data.message); unlockButtons(); return }
      if (data.type === "bluff_ok") { me.bluff = data.text; return }
      state = data
      offsetMs = Date.parse(state.server_time) - Date.now()
      render()
    },
    rejected() {
      forget(`bluff:${code}`)
      toast("That seat is gone. Join the room again.")
      $("code-input").value = code
      show("home")
    },
    connected() { $("status-bar").hidden = true },
    disconnected() { $("status-bar").hidden = false }
  })
  store("bluff:last", code)
  history.replaceState(null, "", `/r/${code}`)
}

function act(action, data = {}) { if (sub) sub.perform(action, data) }

function unlockButtons() {
  ;["create-btn", "join-btn", "start-btn", "bluff-btn", "next-btn", "again-btn"].forEach((id) => setBusy($(id), false))
  document.querySelectorAll(".option").forEach((b) => { b.disabled = false })
}

// ---------- render ----------

function render() {
  if (!state) return
  unlockButtons()
  switch (state.status) {
    case "lobby": renderLobby(); break
    case "writing": renderWriting(); break
    case "voting": renderVoting(); break
    case "reveal": renderReveal(); break
    case "finished": renderFinished(); break
    default: show("home")
  }
  startTimer()
}

function playerItem(p, extra = "") {
  const li = document.createElement("li")
  li.className = `player ${p.connected ? "" : "offline"} ${p.spectator ? "spectator" : ""}`
  const tag = p.id === state.host_id ? " 👑" : ""
  const you = p.id === me.id ? " (you)" : ""
  li.innerHTML = `<span>${esc(p.name)}${tag}${you}</span><span class="meta">${extra}</span>`
  return li
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
}

function renderLobby() {
  show("lobby")
  $("lobby-code").textContent = state.code
  $("site-host").textContent = location.host
  const list = $("lobby-players")
  list.replaceChildren(...state.players.map((p) => playerItem(p, p.connected ? "" : "offline")))
  $("lobby-count").textContent = `(${state.players.length}/12)`
  const host = isHost()
  $("host-settings").hidden = !host
  $("lobby-wait").hidden = host
  const sel = $("pack-select")
  if (sel.options.length === 0) {
    state.packs.forEach((p) => sel.add(new Option(`${p.name} (${p.count})`, p.key)))
    sel.add(new Option("Custom: write your own", "custom"))
    sel.value = state.settings.pack
  }
  $("custom-field").hidden = sel.value !== "custom"
}

function roundLabel(r) { return `Question ${r.index + 1} of ${r.total}` }

function renderWriting() {
  show("writing")
  const r = state.round
  $("writing-round").textContent = roundLabel(r)
  $("writing-question").textContent = r.question
  const p = myPlayer()
  const done = p?.done || p?.spectator
  $("writing-form").hidden = done
  $("writing-done").hidden = !done
  if (p?.spectator) $("writing-done").textContent = "You are watching this round. You play from the next game."
  const list = $("writing-players")
  list.replaceChildren(...state.players.filter((x) => !x.spectator).map((x) => playerItem(x, x.done ? "✅" : "…")))
  if (!done && document.activeElement !== $("bluff-input")) $("bluff-input").focus()
}

function renderVoting() {
  show("voting")
  const r = state.round
  $("voting-round").textContent = roundLabel(r)
  $("voting-question").textContent = r.question
  const p = myPlayer()
  const done = p?.done || p?.spectator
  $("voting-done").hidden = !done
  const box = $("options")
  box.replaceChildren(...r.options.map((o) => {
    const b = document.createElement("button")
    b.className = "option"
    b.textContent = o.text
    const mine = me.bluff && o.text === me.bluff
    if (mine) { b.classList.add("mine"); b.textContent += "  (yours)" }
    b.disabled = done || mine
    b.onclick = () => { document.querySelectorAll(".option").forEach((x) => { x.disabled = true }); act("submit_vote", { index: o.index }) }
    return b
  }))
}

function scoreList(el) {
  const sorted = [...state.players].filter((p) => !p.spectator).sort((a, b) => b.score - a.score)
  el.replaceChildren(...sorted.map((p) => {
    const li = document.createElement("li")
    li.innerHTML = `<span>${esc(p.name)}${p.id === me.id ? " (you)" : ""}</span><b>${p.score}</b>`
    return li
  }))
}

function renderReveal() {
  show("reveal")
  const r = state.round
  $("reveal-round").textContent = roundLabel(r)
  $("reveal-question").textContent = r.question
  const list = $("reveal-list")
  list.replaceChildren(...state.reveal.options.map((o) => {
    const div = document.createElement("div")
    div.className = `reveal-row ${o.truth ? "truth" : ""}`
    const who = o.truth ? "The truth" : `${esc(o.author)}'s bluff`
    const voters = o.voters.length ? `Picked by ${o.voters.map(esc).join(", ")}` : "Nobody picked this"
    const pts = o.points ? `+${o.points}` : ""
    div.innerHTML = `<div class="reveal-text">${esc(o.text)}</div><div class="reveal-meta">${who} · ${voters}</div><div class="reveal-pts">${pts}</div>`
    return div
  }))
  scoreList($("reveal-scores"))
  $("next-btn").hidden = !isHost()
}

function renderFinished() {
  show("finished")
  scoreList($("final-scores"))
  $("again-btn").hidden = !isHost()
  $("again-wait").hidden = isHost()
}

// ---------- timer ----------

let timerHandle = null
function startTimer() {
  clearInterval(timerHandle)
  tickSent = false
  const ends = state.round?.phase_ends_at
  if (!ends) return
  const endMs = Date.parse(ends)
  const ids = { writing: "writing-timer", voting: "voting-timer", reveal: "reveal-timer" }
  const tick = () => {
    const left = Math.max(0, Math.ceil((endMs - (Date.now() + offsetMs)) / 1000))
    const el = $(ids[state.status])
    if (el) el.textContent = `${left}s`
    if (left === 0 && !tickSent) { tickSent = true; act("tick") }
  }
  tick()
  timerHandle = setInterval(tick, 250)
}

// ---------- buttons ----------

$("create-btn").onclick = async () => {
  setBusy($("create-btn"), true)
  try {
    const name = $("name-input").value
    const data = await post("/rooms", { name })
    store(`bluff:${data.code}`, data.token)
    store("bluff:name", name)
    connect(data.code, data.token)
  } catch (e) { toast(e.message); setBusy($("create-btn"), false) }
}

$("join-btn").onclick = async () => {
  setBusy($("join-btn"), true)
  try {
    const name = $("name-input").value
    const code = $("code-input").value.trim().toUpperCase()
    const saved = load(`bluff:${code}`)
    if (saved) { connect(code, saved); return }
    const data = await post("/players", { code, name })
    store(`bluff:${data.code}`, data.token)
    store("bluff:name", name)
    connect(data.code, data.token)
  } catch (e) { toast(e.message); setBusy($("join-btn"), false) }
}

$("copy-btn").onclick = async () => {
  const url = `${location.origin}/r/${state.code}`
  try { await navigator.clipboard.writeText(url); toast("Link copied") } catch (_) { prompt("Copy this link", url) }
}

$("pack-select").onchange = () => { $("custom-field").hidden = $("pack-select").value !== "custom" }

$("start-btn").onclick = () => {
  setBusy($("start-btn"), true)
  const pack = $("pack-select").value
  const custom_questions = $("custom-input").value.split("\n").map((line) => {
    const [question, answer] = line.split("|")
    return { question: (question || "").trim(), answer: (answer || "").trim() }
  }).filter((q) => q.question && q.answer)
  act("start_game", { pack, question_count: Number($("count-select").value), custom_questions })
}

$("bluff-btn").onclick = () => {
  setBusy($("bluff-btn"), true)
  act("submit_bluff", { text: $("bluff-input").value })
  $("bluff-input").value = ""
}
$("bluff-input").addEventListener("keydown", (e) => { if (e.key === "Enter") $("bluff-btn").click() })
$("code-input").addEventListener("keydown", (e) => { if (e.key === "Enter") $("join-btn").click() })
$("name-input").addEventListener("keydown", (e) => { if (e.key === "Enter") ($("code-input").value ? $("join-btn") : $("create-btn")).click() })

$("next-btn").onclick = () => { setBusy($("next-btn"), true); act("next_round") }
$("again-btn").onclick = () => { setBusy($("again-btn"), true); act("play_again") }
$("leave-btn").onclick = () => {
  if (sub) sub.unsubscribe()
  forget(`bluff:${session.code}`)
  state = null
  history.replaceState(null, "", "/")
  show("home")
}
$("how-btn").onclick = () => show("how")
$("how-close").onclick = () => show(lastScreen)

// ---------- boot ----------

;(function boot() {
  $("name-input").value = load("bluff:name") || ""
  const prefill = document.querySelector(".app").dataset.prefillCode
  if (prefill) {
    $("code-input").value = prefill
    const saved = load(`bluff:${prefill}`)
    if (saved) { connect(prefill, saved); return }
  }
  show("home")
})()
```

**Step 2: Check the importmap resolves**

Run: `bin/rails runner 'puts Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)'`
Expected: JSON with `application` and `@rails/actioncable` entries, no error.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: game client"
```

---

### Task 15: Styles

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Code**

`app/assets/stylesheets/application.css`:

```css
:root {
  --bg: #14121f;
  --card: #1f1c2e;
  --text: #f4f1ff;
  --muted: #a9a3c2;
  --accent: #ffd166;
  --accent-text: #1a1400;
  --good: #06d6a0;
  --bad: #ef476f;
  --radius: 14px;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--text); font: 17px/1.4 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
.app { max-width: 520px; margin: 0 auto; padding: 20px 16px 48px; }
.screen { display: flex; flex-direction: column; gap: 14px; }
h1, h2, h3 { margin: 0; }
.logo { font-size: 44px; text-align: center; color: var(--accent); letter-spacing: -1px; margin-top: 24px; }
.tagline { text-align: center; color: var(--muted); margin: 0 0 12px; }
.label { color: var(--muted); margin: 0; font-size: 14px; text-transform: uppercase; letter-spacing: 1px; }
.code { font-size: 56px; letter-spacing: 8px; text-align: center; color: var(--accent); font-family: ui-monospace, Menlo, monospace; }
.hint { color: var(--muted); margin: 0; font-size: 15px; }
.divider { text-align: center; color: var(--muted); font-size: 14px; }
.field { display: flex; flex-direction: column; gap: 6px; }
.field span { font-size: 14px; color: var(--muted); }
input, select, textarea { width: 100%; font: inherit; padding: 14px; border-radius: var(--radius); border: 2px solid #3a3552; background: var(--card); color: var(--text); }
input:focus, select:focus, textarea:focus { outline: none; border-color: var(--accent); }
#code-input { text-transform: uppercase; letter-spacing: 6px; font-family: ui-monospace, Menlo, monospace; font-size: 22px; }
.btn { font: inherit; font-weight: 700; padding: 16px; border-radius: var(--radius); border: 0; background: #3a3552; color: var(--text); cursor: pointer; min-height: 52px; }
.btn.primary { background: var(--accent); color: var(--accent-text); }
.btn.small { padding: 10px 14px; min-height: 0; font-size: 15px; align-self: center; }
.btn:disabled, .option:disabled { opacity: 0.55; cursor: default; }
.btn.busy { opacity: 0.7; }
.link { background: none; border: 0; color: var(--muted); font: inherit; text-decoration: underline; cursor: pointer; padding: 8px; }
.players { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px; }
.player { display: flex; justify-content: space-between; background: var(--card); padding: 10px 14px; border-radius: 10px; }
.player.offline { opacity: 0.5; }
.player.spectator { font-style: italic; }
.players.compact .player { padding: 6px 12px; font-size: 15px; }
.meta { color: var(--muted); }
.topbar { display: flex; justify-content: space-between; color: var(--muted); font-size: 15px; }
.timer { font-family: ui-monospace, Menlo, monospace; font-weight: 700; color: var(--accent); }
.question { font-size: 24px; line-height: 1.3; }
.options { display: flex; flex-direction: column; gap: 10px; }
.option { font: inherit; font-size: 18px; text-align: left; padding: 16px; border-radius: var(--radius); border: 2px solid #3a3552; background: var(--card); color: var(--text); cursor: pointer; min-height: 56px; }
.option:hover:not(:disabled) { border-color: var(--accent); }
.option.mine { border-style: dashed; }
.reveal { display: flex; flex-direction: column; gap: 10px; }
.reveal-row { background: var(--card); border-radius: var(--radius); padding: 12px 14px; display: grid; grid-template-columns: 1fr auto; gap: 2px 10px; border: 2px solid transparent; }
.reveal-row.truth { border-color: var(--good); }
.reveal-row.truth .reveal-text::before { content: "✔ "; color: var(--good); }
.reveal-text { font-size: 18px; font-weight: 700; }
.reveal-meta { color: var(--muted); font-size: 14px; grid-column: 1; }
.reveal-pts { grid-column: 2; grid-row: 1 / span 2; align-self: center; color: var(--accent); font-weight: 800; font-size: 20px; }
.scores { margin: 0; padding: 0 0 0 24px; display: flex; flex-direction: column; gap: 6px; }
.scores li { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #2d2940; }
.scores.big li:first-child { color: var(--accent); font-size: 22px; }
.how { padding-left: 22px; display: flex; flex-direction: column; gap: 8px; }
.status-bar { position: sticky; top: 0; background: var(--bad); color: #fff; text-align: center; padding: 8px; font-weight: 700; z-index: 10; }
.toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); background: #fff; color: #111; padding: 12px 18px; border-radius: 999px; font-weight: 700; z-index: 20; max-width: 90vw; text-align: center; }
```

**Step 2: Commit**

```bash
git add -A
git commit -m "feat: styles"
```

---

### Task 16: Play a full game locally

**Step 1: Start the server**

Run: `bin/rails s -p 3005`
(Port 3005 so it does not clash with the HowNow app on 3000.)

**Step 2: Test by hand**

Open `http://localhost:3005` in three browser tabs (one normal, two private windows so localStorage is separate). Then:

1. Tab 1: name "Host", Create a room. See the code.
2. Tab 2 and 3: name "A" and "B", join with the code. All three tabs show 3 players.
3. Tab 1: pick General, 3 questions, Start. All tabs show the question and a 60s timer.
4. Type bluffs in all tabs. The screen moves to voting as soon as the third bluff is in.
5. Vote in all tabs. Reveal shows the truth, who was fooled and points.
6. Host presses Next. After 3 questions, Final scores show.
7. Press Play again. Lobby again with scores at 0.
8. Refresh tab 2 during writing. It comes back to the same screen as the same player.
9. Close tab 1 (host), wait 35s. Tab 2 or 3 now shows the crown and host controls.
10. Open a 4th tab, join during a game. It shows the "watching" text. After Play again it plays.
11. Try: real answer as bluff, empty bluff, voting for your own bluff, wrong code, same name twice. Each shows a clear message.
12. Open `http://<your-laptop-ip>:3005` on your phone, same WiFi, and join. Check buttons are easy to tap.

For step 12 you need the dev server to accept other hosts. Add to `config/environments/development.rb`:

```ruby
  config.hosts << /.*/
```

Write down anything that broke. Fix it. Add a spec for every bug found (see the TDD agreement).

**Step 3: Full test run**

Run: `bundle exec rspec`
Expected: `0 failures`

**Step 4: Commit fixes**

```bash
git add -A
git commit -m "fix: issues found in manual play"
```

---

### Task 17: Production config and deploy

**Files:**
- Modify: `config/environments/production.rb`
- Create: `render.yaml`, `README.md`

**Step 1: Production settings**

In `config/environments/production.rb` add:

```ruby
  config.action_cable.allowed_request_origins = [ENV["APP_URL"], /https:\/\/.*\.onrender\.com/].compact
  config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?
```

**Step 2: Render blueprint**

`render.yaml`:

```yaml
services:
  - type: web
    name: bluff-club
    runtime: ruby
    plan: free
    buildCommand: "bundle install && bin/rails assets:precompile && bin/rails db:migrate"
    startCommand: "bundle exec puma -C config/puma.rb"
    healthCheckPath: /up
    envVars:
      - key: RAILS_ENV
        value: production
      - key: SOLID_QUEUE_IN_PUMA
        value: "true"
      - key: RAILS_MASTER_KEY
        sync: false
      - key: DATABASE_URL
        sync: false
      - key: APP_URL
        sync: false
```

**Step 3: README**

`README.md`:

```markdown
# Bluff Club

A party trivia game. Write a fake answer, fool your friends, find the truth.
Join with a 4 letter room code. No login, no install. Works on phones and laptops.

Built for the Handshake x OpenAI "Create a Multiplayer Game" challenge.

## Run locally

    rvm use 3.4.8
    bundle install
    bin/rails db:prepare
    bin/rails s -p 3005

Open http://localhost:3005 in two or more tabs.

## Tests

    bundle exec rspec

## Deploy (Render)

1. Create a free MySQL service on Aiven (aiven.io, free plan, no card). Copy the service URI.
   Change its start from `mysql://` to `mysql2://` and make sure it ends with `?ssl_mode=required`.
2. On Render, New > Blueprint, pick this repo. It reads `render.yaml`.
3. Set env vars: `RAILS_MASTER_KEY` (from `config/master.key`), `DATABASE_URL` (the Aiven URI from step 1), `APP_URL` (your Render URL, e.g. https://bluff-club.onrender.com).
4. Deploy.

## How it works

- One Rails 8 app. Action Cable sends the full room state to every player after each change.
- Game rules are in `app/services/game/`. Phases: lobby, writing, voting, reveal, finished.
- Timers are Active Job jobs run by Solid Queue inside the web process.
```

**Step 4: Push to GitHub**

Nitish does these once:

1. Add the SSH key `~/.ssh/id_ed25519_nitish313.pub` to the `nitish313` GitHub account.
2. Create an empty repo `nitish313/bluff-club` on GitHub.

Then:

```bash
cd ~/projects/bluff-club
git remote add origin git@github-nitish313:nitish313/bluff-club.git
git push -u origin main
```

Expected: `ssh -T git@github-nitish313` says `Hi nitish313!` and the push succeeds.

**Step 5: Deploy on Render**

Nitish does these in the browser (needs his logins):

1. aiven.io: sign up, create a free MySQL service named `bluff-club`, copy the service URI.
2. render.com: New > Blueprint > pick `nitish313/bluff-club`. Fill in the three env vars.
3. Wait for the build. Open the URL. Play one game from a phone and a laptop.

Expected: the game works at `https://bluff-club.onrender.com` (or similar).

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: production config, Render blueprint, README"
git push
```

---

### Task 18: Submission kit

**Files:**
- Create: `docs/submission.md`, `docs/cover.png`

**Step 1: Description text**

`docs/submission.md`:

```markdown
# Handshake submission

**Title:** Bluff Club - a party trivia game where you fool your friends

**Link:** https://bluff-club.onrender.com

**Description (under 500 characters):**

Bluff Club is a live party game for 2 to 12 players. One person creates a room and shares a 4 letter code. Everyone joins from their phone, no login. Each round shows a trivia question. You write a fake answer that sounds real, then everyone votes for the truth. Points for spotting the truth and for fooling friends. Hosts can add their own questions, so it works as a team icebreaker or a class quiz. Built with Rails and Action Cable, all screens stay in sync.
```

**Step 2: Cover image**

Make a 1200x630 PNG. Simplest: open the lobby screen in the browser at 1200px wide, take a screenshot, save as `docs/cover.png`. Or write a small HTML page with the logo and tagline and screenshot that.

**Step 3: Submit**

Nitish opens the mission in Handshake, uploads the title, cover image, description and link. Deadline: 30 Oct 2026, 11:59 PM PT.

**Step 4: Commit**

```bash
git add -A
git commit -m "docs: submission kit"
git push
```

---

## Optional Task 19: OpenAI question packs

Only after Tasks 1 to 18 are done and the game is live.

Host types a topic in the lobby. Server calls the OpenAI API and gets 8 questions with short answers. Needs `OPENAI_API_KEY` env var. Falls back to bundled packs if the key is missing. Add a spec that stubs the HTTP call. Use the `ruby-openai` gem or plain `Net::HTTP` to `POST https://api.openai.com/v1/chat/completions` with a prompt that asks for JSON `[{question, answer}]`.
