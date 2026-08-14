/**
 * Echo server with guests.
 *
 *   npm i ws
 *   node guest-echo-server.mjs
 *
 * Web UI:    http://localhost:8080
 * WebSocket: ws://localhost:8080
 *
 * Behaviour: receives a JSON message, reads `chatID`, finds the guest
 * registered for that chat, and echoes the message back with `id`, `username`,
 * `text` and `isOwner` replaced by the guest's values. Every other field is
 * passed through untouched, so the server does not need to know your schema.
 */

import { WebSocketServer } from "ws";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const PORT = Number(process.env.PORT ?? 8080);
const STATE_FILE = "./.guests.json";

/** chatID (lowercased) -> Guest. One guest per chat. */
let guests = existsSync(STATE_FILE)
  ? new Map(Object.entries(JSON.parse(readFileSync(STATE_FILE, "utf8"))))
  : new Map();

const persist = () =>
  writeFileSync(STATE_FILE, JSON.stringify(Object.fromEntries(guests), null, 2));

// UUIDs are case-insensitive; Swift emits uppercase, JS lowercase.
// Normalising here avoids a lookup miss that looks exactly like "no guest".
const norm = (s) => String(s ?? "").toLowerCase();

/* ------------------------------------------------------------------ */
/* HTTP                                                                */
/* ------------------------------------------------------------------ */

const json = (res, code, body) => {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
};

const readBody = (req) =>
  new Promise((resolve) => {
    let raw = "";
    req.on("data", (d) => (raw += d));
    req.on("end", () => {
      try { resolve(JSON.parse(raw || "{}")); } catch { resolve({}); }
    });
  });

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return res.end(PAGE);
  }

  if (url.pathname === "/guests") {
    return json(res, 200, [...guests.values()]);
  }

  if (url.pathname === "/guests/save" && req.method === "POST") {
    const b = await readBody(req);
    const chatID = norm(b.chatID) || randomUUID();
    const guest = {
      id: norm(b.id) || randomUUID(),
      username: b.username || "Guest",
      isOwner: !!b.isOwner,
      chatID,
      text: b.text || "Hello from the server",
    };
    guests.set(chatID, guest);   // one guest per chat — overwrites
    persist();
    console.log(`+ guest "${guest.username}" for chat ${chatID}`);
    return json(res, 200, guest);
  }

  if (url.pathname === "/guests/delete" && req.method === "POST") {
    const b = await readBody(req);
    guests.delete(norm(b.chatID));
    persist();
    return json(res, 200, { ok: true });
  }

  json(res, 404, { error: "not found" });
});

/* ------------------------------------------------------------------ */
/* WebSocket                                                           */
/* ------------------------------------------------------------------ */

const wss = new WebSocketServer({ server });

wss.on("connection", (ws) => {
  console.log("→ connected");

  ws.on("message", (data) => {
    const raw = data.toString();

    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      // Not JSON — fall back to a plain echo so the socket stays useful.
      console.log(`  echo (non-JSON): ${raw}`);
      return ws.send(raw);
    }

    const chatID = norm(msg.chatID);
    const guest = guests.get(chatID);

    if (!guest) {
      console.log(`  ✗ no guest for chat ${chatID || "(missing chatID)"} — echoing unchanged`);
      console.log(`    known chats: ${[...guests.keys()].join(", ") || "(none)"}`);
      return ws.send(raw);
    }

    // Spread first so unknown fields survive; then override the four.
    const reply = {
      ...msg,
      id: guest.id,
      username: guest.username,
      isOwner: guest.isOwner,
      text: guest.text,
    };

    console.log(`  ↩ replying as "${guest.username}": ${guest.text}`);
    ws.send(JSON.stringify(reply));
  });

  ws.on("close", (code) => console.log(`← disconnected (${code})`));
  ws.on("error", (err) => console.log(`! ${err.message}`));
});

/* ------------------------------------------------------------------ */

const PAGE = `<!doctype html><meta charset="utf-8">
<title>Guests</title>
<style>
 body{font:14px system-ui;max-width:760px;margin:40px auto;padding:0 20px;color:#111}
 h1{font-size:19px;margin:0 0 4px}
 .sub{color:#666;margin-bottom:24px}
 .card{border:1px solid #e2e5ea;border-radius:10px;padding:16px;margin-bottom:20px;background:#fafbfc}
 label{display:block;font-size:12px;color:#555;margin:10px 0 3px}
 input{width:100%;box-sizing:border-box;font:inherit;padding:7px 9px;border:1px solid #cbd0d8;border-radius:7px}
 .two{display:grid;grid-template-columns:1fr 1fr;gap:12px}
 button{font:inherit;padding:8px 15px;border-radius:7px;border:1px solid #cbd0d8;background:#fff;cursor:pointer}
 button.primary{background:#1d6ef5;color:#fff;border-color:#1d6ef5;margin-top:16px}
 .g{border:1px solid #e2e5ea;border-radius:9px;padding:12px;margin-bottom:9px;display:flex;justify-content:space-between;gap:12px;align-items:flex-start}
 code{background:#eef1f5;padding:2px 5px;border-radius:4px;font-size:12px}
 .muted{color:#777;font-size:12px}
 .check{display:flex;align-items:center;gap:7px;margin-top:14px}
 .check input{width:auto}
</style>

<h1>Guests</h1>
<div class="sub">One guest per chat. Send a message with a matching <code>chatID</code> and the server replies as that guest.</div>

<div class="card">
  <div class="two">
    <div><label>Chat ID</label><input id="chatID" placeholder="paste from the app"></div>
    <div><label>Guest ID</label><input id="id" placeholder="blank = generate"></div>
  </div>
  <label>Username</label><input id="username" placeholder="Alice">
  <label>Auto-reply text</label><input id="text" placeholder="Hello from the server">
  <div class="check"><input type="checkbox" id="isOwner"><label style="margin:0">isOwner</label></div>
  <div class="muted" style="margin-top:6px">Set this true to check your app really does force inbound messages to false.</div>
  <button class="primary" onclick="save()">Save guest</button>
</div>

<div id="list"></div>

<script>
function load(){
  fetch('/guests').then(function(r){return r.json()}).then(function(gs){
    document.getElementById('list').innerHTML = gs.length ? gs.map(function(g){
      return '<div class="g"><div>'
        + '<b>'+g.username+'</b>' + (g.isOwner?' <span class="muted">(isOwner)</span>':'')
        + '<div class="muted" style="margin:5px 0">replies: "'+g.text+'"</div>'
        + '<div class="muted">chat <code>'+g.chatID+'</code></div>'
        + '<div class="muted">id <code>'+g.id+'</code></div>'
        + '</div><button onclick="del(\\''+g.chatID+'\\')">Delete</button></div>'
    }).join('') : '<div class="muted">No guests yet.</div>';
  });
}
function save(){
  var b = {
    chatID: document.getElementById('chatID').value.trim(),
    id: document.getElementById('id').value.trim(),
    username: document.getElementById('username').value.trim(),
    text: document.getElementById('text').value.trim(),
    isOwner: document.getElementById('isOwner').checked
  };
  fetch('/guests/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)})
    .then(function(r){return r.json()}).then(function(){ 
      ['id','username','text'].forEach(function(f){ document.getElementById(f).value='' });
      load();
    });
}
function del(chatID){
  fetch('/guests/delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({chatID:chatID})})
    .then(load);
}
load();
</script>`;

server.listen(PORT, () => {
  console.log(`web UI     http://localhost:${PORT}`);
  console.log(`websocket  ws://localhost:${PORT}`);
  console.log(`guests     ${STATE_FILE}`);
});
