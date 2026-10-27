# Bluff Club

A party trivia game. Write a fake answer, fool your friends, find the truth.
Join with a 4 letter room code. No login, no install. Works on phones and laptops.

Built for the Handshake x OpenAI "Create a Multiplayer Game" challenge.

## How a round works

1. Everyone sees a trivia question.
2. Each player writes a fake answer that sounds real.
3. All fakes are mixed with the real answer.
4. Everyone picks the one they think is true.
5. +1000 if you find the truth. +500 for each friend who picks your fake.

The host can pick a built-in pack or type their own questions. 2 to 12 players.

## Run locally

    rvm use 3.4.8
    bundle install
    export MYSQL_PASSWORD=<your local MySQL root password>
    bin/rails db:prepare
    bin/rails s -p 3005

Open http://localhost:3005 in two or more browser tabs (use a private window for the second player).

## Tests

    bundle exec rspec

## Deploy (Render + Aiven)

1. Create a free MySQL service on Aiven (aiven.io, free plan, no card). Copy the service URI.
   Change its start from `mysql://` to `mysql2://` and make sure it ends with `?ssl_mode=required`.
2. On Render, New > Blueprint, pick this repo. It reads `render.yaml`.
3. Set env vars: `RAILS_MASTER_KEY` (from `config/master.key`), `DATABASE_URL` (the Aiven URI from step 1),
   `APP_URL` (your Render URL, e.g. https://bluff-club.onrender.com).
4. Deploy.

## How it works

- One Rails 8 app. Action Cable sends the full room state to every player after each change.
- Game rules are in `app/services/game/`. Phases: lobby, writing, voting, reveal, finished.
- Timers are Active Job jobs run by Solid Queue inside the web process.
- Rooms idle for 2 hours are closed by an hourly job.
