/**
 * Guest echo server, matched to the app's Message model.
 *
 *   npm i ws
 *   node guest-echo-server.mjs
 *
 * Web UI:    http://localhost:8080
 * WebSocket: ws://localhost:8080
 *
 * Receives a Message, looks up the guest registered for its `chatID`, and
 * replies as that guest: new `id`, guest's `guestID`, guest's `isOwner`,
 * guest's canned `content`. `chatID` and `ttl` pass through unchanged.
 * The reply is sent as a BINARY frame (Data), not text.
 */

import { WebSocketServer } from "ws";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const PORT = Number(process.env.PORT ?? 8080);
const STATE_FILE = "./.guests.json";

/** chatID (uppercased) -> Guest. One guest per chat. */
let guests = existsSync(STATE_FILE)
  ? new Map(Object.entries(JSON.parse(readFileSync(STATE_FILE, "utf8"))))
  : new Map();

const persist = () =>
  writeFileSync(STATE_FILE, JSON.stringify(Object.fromEntries(guests), null, 2));

// Swift emits uppercase UUID strings; randomUUID() emits lowercase.
// Normalise on the way in so lookups can't miss on case alone, and
// uppercase on the way out so the app decodes what it expects.
const UP = (s) => String(s ?? "").toUpperCase();
const newUUID = () => randomUUID().toUpperCase();

/**
 * Produces a reply timestamp in whatever format the client sent.
 *
 * Swift's default JSONEncoder strategy (.deferredToDate) emits seconds since
 * the 2001 reference date, NOT the Unix epoch — so generating our own
 * timestamp would land 31 years out. Mirroring the incoming format means this
 * works whichever strategy the app ends up using.
 */
function replyDate(incoming) {
  if (typeof incoming === "number") return incoming + 1;   // same epoch, 1s later
  if (typeof incoming === "string") return new Date().toISOString();
  return new Date().toISOString();
}

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

  if (url.pathname === "/guests") return json(res, 200, [...guests.values()]);

  if (url.pathname === "/guests/save" && req.method === "POST") {
    const b = await readBody(req);
    const chatID = UP(b.chatID) || newUUID();
    const guest = {
      guestID: UP(b.guestID) || newUUID(),
      label: b.label || "Guest",          // display only; not sent to the app
      isOwner: !!b.isOwner,
      chatID,
      content: b.content || "Hello from the server",
    };
    guests.set(chatID, guest);            // one guest per chat — overwrites
    persist();
    console.log(`+ guest "${guest.label}" for chat ${chatID}`);
    return json(res, 200, guest);
  }

  if (url.pathname === "/guests/delete" && req.method === "POST") {
    const b = await readBody(req);
    guests.delete(UP(b.chatID));
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
      console.log(`  echo (non-JSON): ${raw}`);
      return ws.send(data);
    }

    const chatID = UP(msg.chatID);
    const guest = guests.get(chatID);

    if (!guest) {
      console.log(`  ✗ no guest for chat ${chatID || "(missing chatID)"} — echoing unchanged`);
      console.log(`    known chats: ${[...guests.keys()].join(", ") || "(none)"}`);
      return ws.send(data);
    }

    // Spread first so any field added later survives untouched.
    const reply = {
      ...msg,
      id: newUUID(),                  // app replaces this before saving anyway
      chatID,                         // uppercased, otherwise unchanged
      guestID: guest.guestID,
      isOwner: guest.isOwner,
      content: guest.content,
      date: replyDate(msg.date),
    };

    console.log(`  ↩ as ${guest.label}: "${guest.content}"  (ttl ${reply.ttl})`);

    // Binary frame → arrives as .data in URLSessionWebSocketTask.receive
    ws.send(Buffer.from(JSON.stringify(reply), "utf8"), { binary: true });
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
<div class="sub">One guest per chat. Send a Message whose <code>chatID</code> matches and the server replies as that guest.</div>

<div class="card">
  <div class="two">
    <div><label>Chat ID</label><input id="chatID" placeholder="paste from the app"></div>
    <div><label>Guest ID</label><input id="guestID" placeholder="blank = generate"></div>
  </div>
  <label>Label <span class="muted">(this panel only — not sent)</span></label><input id="label" placeholder="Alice">
  <label>Reply content</label><input id="content" placeholder="Hello from the server">
  <div class="check"><input type="checkbox" id="isOwner"><label style="margin:0">isOwner</label></div>
  <div class="muted" style="margin-top:6px">Tick this to check your app really does force inbound messages to false.</div>
  <button class="primary" onclick="save()">Save guest</button>
</div>

<div id="list"></div>

<script>
function load(){
  fetch('/guests').then(function(r){return r.json()}).then(function(gs){
    document.getElementById('list').innerHTML = gs.length ? gs.map(function(g){
      return '<div class="g"><div>'
        + '<b>'+g.label+'</b>' + (g.isOwner?' <span class="muted">(isOwner: true)</span>':'')
        + '<div class="muted" style="margin:5px 0">replies: "'+g.content+'"</div>'
        + '<div class="muted">chat <code>'+g.chatID+'</code></div>'
        + '<div class="muted">guestID <code>'+g.guestID+'</code></div>'
        + '</div><button onclick="del(\\''+g.chatID+'\\')">Delete</button></div>'
    }).join('') : '<div class="muted">No guests yet.</div>';
  });
}
function save(){
  var b = {
    chatID: document.getElementById('chatID').value.trim(),
    guestID: document.getElementById('guestID').value.trim(),
    label: document.getElementById('label').value.trim(),
    content: document.getElementById('content').value.trim(),
    isOwner: document.getElementById('isOwner').checked
  };
  fetch('/guests/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)})
    .then(function(r){return r.json()}).then(function(){
      ['guestID','label','content'].forEach(function(f){ document.getElementById(f).value='' });
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
