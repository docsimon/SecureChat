/**
 * Mock chat server — for UI development only.
 *
 *   npm init -y && npm i ws
 *   node mock-server.mjs
 *
 * Then open http://localhost:8080 for the control panel, and point the app at
 * ws://localhost:8080/ws?as=<userId>
 *
 * Deliberately the OPPOSITE of the production relay: it persists state to disk,
 * knows message contents, and has no auth. That is the point — you are testing
 * the UI, and state that survives a restart is what makes that bearable.
 *
 * The wire protocol shape matches the eventual real one, so the client's
 * message model and state machine port across unchanged.
 */

import { WebSocketServer } from "ws";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const PORT = Number(process.env.PORT ?? 8080);
const STATE_FILE = "./.mockstate.json";

/* ------------------------------------------------------------------ */
/* State                                                               */
/* ------------------------------------------------------------------ */

const blank = () => ({
  users: [],          // { id, name, colour, bot, online }
  conversations: [],  // { id, memberIds: [] }
  messages: [],       // { id, conversationId, senderId, payload, sentAt }
  chaos: { latencyMs: 0, dropRate: 0 },
});

let state = existsSync(STATE_FILE)
  ? JSON.parse(readFileSync(STATE_FILE, "utf8"))
  : blank();

const persist = () => writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));

const user = (id) => state.users.find((u) => u.id === id);
const convo = (id) => state.conversations.find((c) => c.id === id);

/* ------------------------------------------------------------------ */
/* Seed content — deliberately adversarial for layout testing          */
/* ------------------------------------------------------------------ */

const SAMPLES = [
  "hey",
  "ok",
  "Sounds good — I'll take a look this evening and let you know what I find.",
  "Supercalifragilisticexpialidocious" + "notaword".repeat(12),
  "🎉🎉🎉",
  "👍",
  "مرحبا، كيف حالك اليوم؟",
  "שלום, מה שלומך?",
  "Line one\nLine two\nLine three\n\nAnd a gap above this one.",
  "https://example.com/a/very/long/path/that/should/wrap/or/truncate?with=query&params=true",
  "This is a much longer message intended to exercise multi-line bubble layout, wrapping behaviour, and the way timestamps position themselves relative to text that runs well past a single line. It should also reveal whether your bubble max-width is doing what you think it is.",
  "   leading and trailing whitespace   ",
  "a",
  "Can you send that over when you get a sec?",
  "done ✅",
];

const pick = (a) => a[Math.floor(Math.random() * a.length)];

/**
 * Seeds messages spread across several days so date separators, grouping,
 * and unread counts all get exercised.
 */
function seedMessages(conversationId, count) {
  const c = convo(conversationId);
  if (!c) return 0;
  const now = Date.now();
  const span = 5 * 24 * 60 * 60 * 1000;
  const made = [];
  for (let i = 0; i < count; i++) {
    made.push({
      id: randomUUID(),
      conversationId,
      senderId: pick(c.memberIds),
      payload: { type: "text", text: pick(SAMPLES) },
      sentAt: now - span + Math.floor((span * i) / count),
    });
  }
  state.messages.push(...made);
  state.messages.sort((a, b) => a.sentAt - b.sentAt);
  persist();
  return made.length;
}

/* ------------------------------------------------------------------ */
/* Sockets                                                             */
/* ------------------------------------------------------------------ */

/** @type {Map<string, Set<any>>} userId -> sockets */
const sockets = new Map();

function socketsFor(userId) {
  let s = sockets.get(userId);
  if (!s) { s = new Set(); sockets.set(userId, s); }
  return s;
}

function send(ws, obj) {
  if (ws.readyState !== ws.OPEN) return;
  const { latencyMs, dropRate } = state.chaos;
  if (dropRate > 0 && Math.random() < dropRate) return;
  const frame = JSON.stringify(obj);
  if (latencyMs > 0) setTimeout(() => ws.readyState === ws.OPEN && ws.send(frame), latencyMs);
  else ws.send(frame);
}

function sendToUser(userId, obj) {
  let n = 0;
  for (const ws of socketsFor(userId)) { send(ws, obj); n++; }
  return n;
}

function deliver(message) {
  const c = convo(message.conversationId);
  if (!c) return 0;
  let delivered = 0;
  for (const memberId of c.memberIds) {
    if (memberId === message.senderId) continue;
    delivered += sendToUser(memberId, { t: "message", message });
  }
  return delivered;
}

function broadcastPresence(userId) {
  const online = socketsFor(userId).size > 0;
  const u = user(userId);
  if (u) u.online = online;
  for (const c of state.conversations) {
    if (!c.memberIds.includes(userId)) continue;
    for (const m of c.memberIds) {
      if (m !== userId) sendToUser(m, { t: "presence", userId, online });
    }
  }
}

/** Records a message, persists it, delivers it. Returns the stored message. */
function postMessage(conversationId, senderId, payload) {
  const message = {
    id: randomUUID(),
    conversationId,
    senderId,
    payload,
    sentAt: Date.now(),
  };
  state.messages.push(message);
  persist();
  deliver(message);
  return message;
}

/* ------------------------------------------------------------------ */
/* Bots — so the chat room has something alive in it                   */
/* ------------------------------------------------------------------ */

function maybeBotReply(message) {
  const c = convo(message.conversationId);
  if (!c) return;
  for (const memberId of c.memberIds) {
    const u = user(memberId);
    if (!u?.bot || memberId === message.senderId) continue;

    // Typing indicator first, then the reply — exercises the real sequence.
    setTimeout(() => sendToUser(message.senderId, {
      t: "typing", conversationId: c.id, userId: u.id, isTyping: true,
    }), 400);

    setTimeout(() => {
      sendToUser(message.senderId, {
        t: "typing", conversationId: c.id, userId: u.id, isTyping: false,
      });
      const reply = postMessage(c.id, u.id, { type: "text", text: pick(SAMPLES) });
      sendToUser(message.senderId, { t: "message", message: reply });
    }, 1800);
  }
}

/* ------------------------------------------------------------------ */
/* HTTP control API + panel                                            */
/* ------------------------------------------------------------------ */

const json = (res, code, body) => {
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
  res.end(JSON.stringify(body));
};

function readBody(req) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (d) => (raw += d));
    req.on("end", () => { try { resolve(JSON.parse(raw || "{}")); } catch { resolve({}); } });
  });
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    return res.end();
  }

  if (url.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return res.end(PANEL);
  }

  if (url.pathname === "/state") return json(res, 200, state);

  const body = req.method === "POST" ? await readBody(req) : {};

  switch (url.pathname) {
    case "/users/create": {
      const u = {
        id: randomUUID(),
        name: body.name || "User " + (state.users.length + 1),
        colour: body.colour || "#" + Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, "0"),
        bot: !!body.bot,
        online: false,
      };
      state.users.push(u);
      persist();
      return json(res, 200, u);
    }

    case "/conversations/create": {
      const memberIds = body.memberIds || [];
      if (memberIds.length < 2) return json(res, 400, { error: "need 2 members" });
      const c = { id: body.id || randomUUID(), memberIds };
      state.conversations.push(c);
      persist();
      for (const m of memberIds) sendToUser(m, { t: "conversation", conversation: c });
      return json(res, 200, c);
    }

    case "/seed": {
      const n = seedMessages(body.conversationId, Number(body.count ?? 40));
      return json(res, 200, { seeded: n });
    }

    case "/say": {
      const c = convo(body.conversationId);
      if (!c) return json(res, 404, { error: "no such conversation" });
      const message = postMessage(body.conversationId, body.senderId, {
        type: "text",
        text: body.text ?? pick(SAMPLES),
      });
      return json(res, 200, message);
    }

    case "/typing": {
      const c = convo(body.conversationId);
      if (!c) return json(res, 404, { error: "no such conversation" });
      for (const m of c.memberIds) {
        if (m !== body.userId) {
          sendToUser(m, {
            t: "typing", conversationId: c.id, userId: body.userId, isTyping: !!body.isTyping,
          });
        }
      }
      return json(res, 200, { ok: true });
    }

    case "/disconnect": {
      // Abrupt, no close frame — what a lost network actually looks like.
      let n = 0;
      for (const ws of socketsFor(body.userId)) { ws.terminate(); n++; }
      return json(res, 200, { terminated: n });
    }

    case "/chaos": {
      state.chaos = {
        latencyMs: Number(body.latencyMs ?? 0),
        dropRate: Number(body.dropRate ?? 0),
      };
      persist();
      return json(res, 200, state.chaos);
    }

    case "/reset": {
      state = blank();
      persist();
      for (const set of sockets.values()) for (const ws of set) ws.terminate();
      return json(res, 200, { ok: true });
    }

    default:
      return json(res, 404, { error: "not found" });
  }
});

/* ------------------------------------------------------------------ */
/* WebSocket                                                           */
/* ------------------------------------------------------------------ */

const wss = new WebSocketServer({ server, path: "/ws" });

// ws silently destroys upgrades on the wrong path, which looks identical to a
// crash from the client side. Log every attempt so mistakes are visible.
server.on("upgrade", (req) => {
  const u = new URL(req.url, `http://localhost:${PORT}`);
  if (u.pathname !== "/ws") {
    console.log(`✗ upgrade rejected: path "${u.pathname}" — did you mean /ws ?`);
  } else {
    console.log(`→ upgrade ${u.pathname}?${u.searchParams.toString()}`);
  }
});

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const userId = url.searchParams.get("as");

  if (!user(userId)) {
    console.log(`✗ rejected: as="${userId}" is not a known user`);
    console.log(`  known ids: ${state.users.map((u) => u.id).join(", ") || "(none — create one first)"}`);
    // Close code carries the reason; the client sees it in the close handler
    // instead of an unexplained disconnect.
    return ws.close(4004, "unknown_user");
  }

  console.log(`✓ connected: ${user(userId).name}`);
  ws.userId = userId;
  socketsFor(userId).add(ws);
  broadcastPresence(userId);

  const myConvos = state.conversations.filter((c) => c.memberIds.includes(userId));
  send(ws, {
    t: "ready",
    userId,
    users: state.users,
    conversations: myConvos,
    messages: state.messages.filter((m) => myConvos.some((c) => c.id === m.conversationId)),
  });

  ws.on("message", (raw) => {
    let m;
    try { m = JSON.parse(raw.toString()); } catch { return; }

    switch (m.t) {
      case "send": {
        const message = postMessage(m.conversationId, userId, m.payload);
        // `ref` is the client's local id — echo it so optimistic UI reconciles.
        send(ws, {
          t: "ack",
          ref: m.ref ?? null,
          messageId: message.id,
          sentAt: message.sentAt,
          delivered: convo(m.conversationId)?.memberIds
            .filter((x) => x !== userId)
            .reduce((n, x) => n + socketsFor(x).size, 0) ?? 0,
        });
        maybeBotReply(message);
        break;
      }

      case "typing": {
        const c = convo(m.conversationId);
        if (!c) break;
        for (const other of c.memberIds) {
          if (other !== userId) {
            sendToUser(other, {
              t: "typing", conversationId: c.id, userId, isTyping: !!m.isTyping,
            });
          }
        }
        break;
      }

      case "read":
        for (const other of convo(m.conversationId)?.memberIds ?? []) {
          if (other !== userId) {
            sendToUser(other, { t: "read", conversationId: m.conversationId, userId, upTo: m.upTo });
          }
        }
        break;
    }
  });

  ws.on("close", () => {
    socketsFor(userId).delete(ws);
    broadcastPresence(userId);
  });
});

/* ------------------------------------------------------------------ */

const PANEL = `<!doctype html><meta charset="utf-8">
<title>Mock chat control</title>
<style>
 body{font:14px system-ui;margin:0;padding:20px;background:#f6f7f9;color:#111}
 h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:#666;margin:24px 0 8px}
 .card{background:#fff;border:1px solid #e2e5ea;border-radius:10px;padding:14px;margin-bottom:12px}
 button{font:inherit;padding:6px 12px;border:1px solid #cbd0d8;background:#fff;border-radius:7px;cursor:pointer}
 button:hover{background:#f0f2f5}
 button.primary{background:#1d6ef5;color:#fff;border-color:#1d6ef5}
 input,select{font:inherit;padding:6px 9px;border:1px solid #cbd0d8;border-radius:7px}
 .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:8px}
 .pill{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:99px;background:#eef1f5;font-size:13px}
 .dot{width:8px;height:8px;border-radius:99px;background:#c3c9d2}
 .dot.on{background:#22c55e}
 code{background:#eef1f5;padding:2px 5px;border-radius:4px;font-size:12px}
</style>
<h1 style="font-size:20px;margin:0 0 4px">Mock chat control</h1>
<div style="color:#666;margin-bottom:20px">Connect the app to <code>ws://localhost:${PORT}/ws?as=USER_ID</code></div>

<h2>Users</h2>
<div class="card">
  <div class="row">
    <input id="uname" placeholder="Name">
    <label class="pill"><input type="checkbox" id="ubot"> auto-replying bot</label>
    <button class="primary" onclick="createUser()">Add user</button>
  </div>
  <div id="users"></div>
</div>

<h2>Conversations</h2>
<div class="card">
  <div class="row">
    <select id="m1"></select><span>and</span><select id="m2"></select>
    <button class="primary" onclick="createConvo()">Create</button>
  </div>
  <div id="convos"></div>
</div>

<h2>Send</h2>
<div class="card">
  <div class="row">
    <select id="sconvo"></select>
    <span>as</span><select id="ssender"></select>
  </div>
  <div class="row">
    <input id="stext" placeholder="Message (blank = random sample)" style="flex:1;min-width:260px">
    <button class="primary" onclick="say()">Send</button>
    <button onclick="typing(true)">Typing on</button>
    <button onclick="typing(false)">off</button>
  </div>
  <div class="row">
    <input id="scount" type="number" value="40" style="width:80px">
    <button onclick="seed()">Seed messages</button>
    <span style="color:#666">spread over 5 days, includes emoji, RTL, long words, multiline</span>
  </div>
</div>

<h2>Break things</h2>
<div class="card">
  <div class="row">
    <select id="dcuser"></select>
    <button onclick="disconnect()">Kill socket (no close frame)</button>
  </div>
  <div class="row">
    <span>Latency</span><input id="clat" type="number" value="0" style="width:80px"> ms
    <span>Drop rate</span><input id="cdrop" type="number" value="0" step="0.1" style="width:80px">
    <button onclick="chaos()">Apply</button>
  </div>
  <div class="row"><button onclick="reset()">Reset everything</button></div>
</div>

<script>
var S = {users:[],conversations:[],messages:[]};
function post(p, b){ return fetch(p,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b||{})}).then(function(r){return r.json()}).then(load) }
function load(){ return fetch('/state').then(function(r){return r.json()}).then(function(s){ S=s; render() }) }
function opts(sel, items, label){
  var v = sel.value;
  sel.innerHTML = items.map(function(i){ return '<option value="'+i.id+'">'+label(i)+'</option>' }).join('');
  if(v) sel.value = v;
}
function render(){
  document.getElementById('users').innerHTML = S.users.map(function(u){
    return '<span class="pill" style="margin:3px 4px 0 0"><span class="dot'+(u.online?' on':'')+'"></span>'
      + u.name + (u.bot?' 🤖':'') + ' <code>'+u.id.slice(0,8)+'</code></span>'
  }).join('') || '<span style="color:#888">No users yet</span>';

  document.getElementById('convos').innerHTML = S.conversations.map(function(c){
    var names = c.memberIds.map(function(id){ var u=S.users.find(function(x){return x.id===id}); return u?u.name:'?' }).join(' ↔ ');
    var n = S.messages.filter(function(m){return m.conversationId===c.id}).length;
    return '<div style="margin:4px 0">'+names+' — '+n+' messages <code>'+c.id.slice(0,8)+'</code></div>'
  }).join('') || '<span style="color:#888">No conversations yet</span>';

  ['m1','m2','ssender','dcuser'].forEach(function(id){
    opts(document.getElementById(id), S.users, function(u){return u.name});
  });
  opts(document.getElementById('sconvo'), S.conversations, function(c){
    return c.memberIds.map(function(id){ var u=S.users.find(function(x){return x.id===id}); return u?u.name:'?' }).join(' ↔ ');
  });
}
function createUser(){
  post('/users/create',{name:document.getElementById('uname').value,bot:document.getElementById('ubot').checked});
  document.getElementById('uname').value='';
}
function createConvo(){
  var a=document.getElementById('m1').value, b=document.getElementById('m2').value;
  if(a===b) return alert('Pick two different users');
  post('/conversations/create',{memberIds:[a,b]});
}
function say(){
  post('/say',{conversationId:document.getElementById('sconvo').value,senderId:document.getElementById('ssender').value,text:document.getElementById('stext').value||undefined});
  document.getElementById('stext').value='';
}
function typing(on){ post('/typing',{conversationId:document.getElementById('sconvo').value,userId:document.getElementById('ssender').value,isTyping:on}) }
function seed(){ post('/seed',{conversationId:document.getElementById('sconvo').value,count:Number(document.getElementById('scount').value)}) }
function disconnect(){ post('/disconnect',{userId:document.getElementById('dcuser').value}) }
function chaos(){ post('/chaos',{latencyMs:Number(document.getElementById('clat').value),dropRate:Number(document.getElementById('cdrop').value)}) }
function reset(){ if(confirm('Wipe all mock data?')) post('/reset') }
load(); setInterval(load, 2000);
</script>`;

server.listen(PORT, "0.0.0.0", () => {
  console.log(`control panel  http://localhost:${PORT}`);
  console.log(`websocket      ws://localhost:${PORT}/ws?as=<userId>`);
  console.log(`state file     ${STATE_FILE}  (delete it to start clean)`);
});
