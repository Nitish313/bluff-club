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
let timerHandle = null
let toastTimer = null

// ---------- small helpers ----------

function show(name) {
  SCREENS.forEach((s) => { $(`screen-${s}`).hidden = s !== name })
  if (name !== "how") lastScreen = name
  window.scrollTo(0, 0)
}

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

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
}

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
    state.packs.forEach((p) => sel.add(new Option(`${p.name} (${p.count} questions)`, p.key)))
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
  $("writing-done").textContent = p?.spectator
    ? "You are watching this game. You play from the next one."
    : "Bluff sent. Waiting for the others…"
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
  $("voting-done").textContent = p?.spectator
    ? "You are watching this game. You play from the next one."
    : "Vote locked. Waiting for the others…"
  const box = $("options")
  box.replaceChildren(...r.options.map((o) => {
    const b = document.createElement("button")
    b.className = "option"
    b.textContent = o.text
    const mine = me.bluff && o.text === me.bluff
    if (mine) { b.classList.add("mine"); b.textContent += "  (yours)" }
    b.disabled = done || mine
    b.onclick = () => {
      document.querySelectorAll(".option").forEach((x) => { x.disabled = true })
      act("submit_vote", { index: o.index })
    }
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
    const pts = !o.points ? "" : (o.truth ? `+${o.points / o.voters.length} each` : `+${o.points} to ${esc(o.author)}`)
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
$("name-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter") ($("code-input").value ? $("join-btn") : $("create-btn")).click()
})

$("next-btn").onclick = () => { setBusy($("next-btn"), true); act("next_round") }
$("again-btn").onclick = () => { setBusy($("again-btn"), true); act("play_again") }
$("leave-btn").onclick = () => {
  if (sub) sub.unsubscribe()
  sub = null
  forget(`bluff:${session.code}`)
  state = null
  history.replaceState(null, "", "/")
  show("home")
}
$("how-btn").onclick = () => show("how")
$("how-btn-lobby").onclick = () => show("how")
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
