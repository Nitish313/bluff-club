# Bluff Club - Design

Date: 2026-10-27
For: Handshake x OpenAI "Create a Multiplayer Game" contest.
Deadline: 30 Oct 2026, 11:59 PM PT (31 Oct, 12:29 PM IST).

## What the contest needs

- A live game at a public link.
- Any group joins with a room code. No login. No app install.
- Works on phones and laptops.
- All players see the same thing at the same time.
- Can play again with a fresh round.
- Submit: title, cover image, description, link.
- Judged on 4 equal parts: execution, creativity, usefulness, polish.

## The game

Bluff Trivia. Players write fake answers and try to fool each other.

### One round

1. Everyone sees a question. Example: "What year was the first iPhone sold?"
2. Each player types a fake answer. They try to make it look real.
3. The game mixes all fake answers with the true answer.
4. Each player picks the answer they think is true.
5. The game shows the true answer and who picked what.
6. Points: +1000 if you picked the true answer. +500 for each player who picked your fake answer.
7. Next question. After all questions, final scores. Host can press "Play again".

### Extra idea (makes it useful, not only fun)

The host can type their own questions before the game. Example for an office team:
"What was our company's first product?" So it works for team meetings and classes.

Later, if we have an OpenAI key: host types a topic, the server asks OpenAI to write
8 questions. We build this only after the main game works.

### Limits

- 2 to 12 players per room.
- Reason: the vote screen shows all fake answers plus the true one. 13 answers still
  fits on a phone. More is too long.

## Screens

| Screen | What it shows |
|---|---|
| Home | Enter your name. "Create room" or "Join" with a 4 letter code. |
| Lobby | Room code and share link. Host picks question pack and number of questions. Host presses Start. |
| Write | The question and a text box. 60 second timer. |
| Vote | List of answers to tap. 30 second timer. You cannot pick your own fake. |
| Reveal | True answer, who picked what, points. 8 seconds. |
| Final | Scores. "Play again" button. |

## Tech

- Ruby 3.4 and Rails 8.
- MySQL database (MySQL 8 is already on this machine). Stores rooms, players, questions, answers, votes.
- Same database type in dev, test and production.
- Action Cable for live updates. Solid Cable (uses the DB, no Redis needed).
- Solid Queue for timers. A job runs when a phase time is up.
- The server decides everything. After each change it sends the full room state
  to every player in the room. The browser only draws what it gets.
- Front end: plain HTML, CSS and JS served by Rails. No build tool. Phone first.
- Game rules live in plain Ruby service classes. No network code inside. Easy to test.

## Problem cases we handle

- Player refreshes or phone sleeps: browser keeps a player token. They come back to
  the same seat and score.
- Host leaves: after 30 seconds the next player becomes host.
- Player leaves mid round: the round goes on without them.
- Player does not answer in time: they skip that step.
- Someone joins during a game: they watch, and play from the next game.
- Wrong code, same name twice, room full: clear error on the join screen.
- Fake answer same as the true answer: rejected, try again.
- Room idle for 2 hours: marked closed.

## Hosting

- Code: GitHub, personal account `nitish313`, repo `bluff-club`.
- App: Render free plan, deploys from GitHub.
- Database: free MySQL on Aiven (1 GB, no card needed). Render has no free MySQL.

## Testing

- RSpec unit tests for the rules: scoring, phase changes, bluff checks, limits.
- Request specs for join and create.
- Manual: many browser tabs plus a phone, full game, before deploy.

## Also delivered

- Submission description text.
- Cover image.
