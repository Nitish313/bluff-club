# How Bluff Club works (technical flow)

Short walkthrough of what happens inside the Rails app, from page load to final scores.
File paths are relative to the repo root.

## 1. Page load

- Browser opens `/`. `PagesController#home` renders one HTML page (`app/views/pages/home.html.erb`)
  that holds all 7 screens: home, lobby, writing, voting, reveal, finished, how-to-play.
  All are hidden except Home.
- `app/javascript/application.js` is the only JS file. It never decides game rules.
  It receives the room state from the server and draws the right screen.

## 2. Create or join a room (normal HTTP)

- Create: JS sends `POST /rooms` with the player name. `RoomsController` calls `Game::CreateRoom`.
  It makes a `Room` row with a 4 letter code and a `Player` row for the host.
- Join: JS sends `POST /players` with code and name. `Game::JoinRoom` checks:
  room exists, room not closed, name not already used, fewer than 12 players.
  If a game is already running, the new player is marked `spectator` and plays from the next game.
- Both return JSON `{code, token, player_id}`.
- JS saves the token in localStorage under `bluff:<CODE>`. The token is the player's identity.
  There is no login.

## 3. Live connection (Action Cable)

- JS opens a WebSocket and subscribes to `RoomChannel` (`app/channels/room_channel.rb`)
  with the room code and the token.
- `RoomChannel#subscribed` finds the player by token, marks them `connected`,
  and calls `Game::Broadcast`.
- `Game::Broadcast` builds the full room state with `Game::State` and sends it to every
  player in the room using `broadcast_to`. The browser never asks for state.
  It only receives it and redraws.
- The server also sends a private `hello` message to that one player with their id and
  their own bluff. So a page refresh brings them back to the same seat with the same score.

## 4. Game actions

- Every button in the browser calls one channel action:
  `start_game`, `submit_bluff`, `submit_vote`, `next_round`, `play_again`.
- Each action calls one service class in `app/services/game/`.
  Example: `submit_bluff` → `Game::SubmitBluff`.
- The service checks the rules (right phase, text is not the true answer, text is not a copy of
  another player's bluff), saves the row, then broadcasts the new state.
- If a rule fails, the service raises `Game::Error`. The channel catches it and sends
  `{type: "error", message: "..."}` to only that player. The browser shows a toast.

## 5. Phases and timers

- `Game::Advance` moves the room through the phases:
  lobby → writing (60s) → voting (30s) → reveal (10s) → next round, or finished.
- On each phase change it sets `phase_ends_at` and a new random `phase_token` on the room,
  then enqueues `PhaseTimeoutJob` with that token. Jobs run with Solid Queue inside Puma.
- When the job fires it compares its token with the room's token. If the room already moved on,
  the tokens differ and the job does nothing. This stops an old timer from breaking a newer phase.
- Writing never ends early. When every active player (connected, not spectator) has answered,
  the state gets `all_done: true` and the host sees a "Start voting" button. Pressing it calls
  `Game::Advance.skip`, which refuses unless everyone has answered. Otherwise the 60s timer ends it.
- Voting does end early: when every active player has voted, `maybe_finish_phase` moves to reveal.
- On the last round the reveal button says "See final scores" instead of "Next question".
- The browser also shows a countdown. When it hits 0 it sends `tick` as a backup,
  in case the job is late.

## 6. Scoring

- On voting → reveal, `Game::Score` runs once per round.
  - Voted for the truth: +1000.
  - Each player fooled by your bluff: +500 to you.
- Scores are saved on `players.score`.
- `Game::State` adds a `reveal` block (true answer, who wrote each option, who voted for it)
  only during reveal. During voting the options list has no authors, so the browser cannot cheat.
- Option order is shuffled with a fixed seed per round, so every player sees the same order.

## 7. Leaving and coming back

- Tab closed → `RoomChannel#unsubscribed` → `Game::Presence` marks the player disconnected.
  If they were the host, `HostMigrationJob` runs after 30s and gives host to the next
  connected player.
- Page refresh → JS reads the token from localStorage → same seat and score.
- `CloseIdleRoomsJob` runs every hour (`config/recurring.yml`) and marks rooms with no activity
  for 2 hours as closed.

## 8. Tables

```
rooms    → players
         → rounds → bluffs
                  → votes  (vote.bluff_id is NULL when the vote was for the truth)
```

Solid Cable and Solid Queue keep their own tables in the same MySQL database,
so no Redis is needed.

## 9. Config that matters

| File | What it does |
|---|---|
| `config/cable.yml` | dev: `async`, test: `test`, prod: `solid_cable` |
| `config/puma.rb` | starts Solid Queue inside Puma when `SOLID_QUEUE_IN_PUMA=true` |
| `config/recurring.yml` | hourly `CloseIdleRoomsJob` in production |
| `config/environments/production.rb` | allowed WebSocket origins from `APP_URL` |
| `config/packs/*.yml` | built-in question packs |
| `render.yaml` | Render build and start commands, env var list |
