/**
 * Pairing prototype — auth + relay in one process.
 *
 *   npm i ws
 *   node pairing-server.mjs
 *
 * Web panel:  http://localhost:8080
 * WebSocket:  ws://localhost:8080/relay?as=<userID>&chat=<chatID>
 *
 * NO auth, NO encryption. This exists to validate the pairing FLOW only.
 *
 * The two halves are kept deliberately separate in the code below, because
 * they have different jobs and eventually become different processes:
 *
 *   AUTH  — durable. Knows phones, users, push tokens, chat membership.
 *   RELAY — ephemeral. Knows only which sockets are open. Forwards bytes.
 *
 * Push notifications are logged to the console instead of sent. B polls
 * GET /invites to discover them, which is the same flow APNs would trigger.
 */

import { WebSocketServer } from "ws";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const PORT = Number(process.env.PORT ?? 8080);
const STATE_FILE = "./.pairing.json";

const UP = (s) => String(s ?? "").toUpperCase();
const newUUID = () => randomUUID().toUpperCase();

// Phone numbers arrive in whatever format the contact list gave them.
// Normalising to digits-only means "+44 7700 900123" and "07700900123"
// don't become two different users.
const normPhone = (s) => String(s ?? "").replace(/[^\d+]/g, "");

/* ================================================================== */
/* AUTH SERVER STATE — durable                                        */
/* ================================================================== */

const blank = () => ({
  users: [],      // { userID, phone, displayName, pushToken }
  invites: [],    // { inviteID, chatID, fromUserID, toUserID, status, createdAt }
  chats: [],      // { chatID, memberIDs: [], createdAt }
});

let db = existsSync(STATE_FILE)
  ? JSON.parse(readFileSync(STATE_FILE, "utf8"))
  : blank();

const persist = () => writeFileSync(STATE_FILE, JSON.stringify(db, null, 2));

const userByID = (id) => db.users.find((u) => u.userID === UP(id));
const userByPhone = (p) => db.users.find((u) => u.phone === normPhone(p));
const chatByID = (id) => db.chats.find((c) => c.chatID === UP(id));

/** Stands in for APNs. Same trigger point, no certificates required. */
function sendPush(userID, payload) {
  const u = userByID(userID);
  console.log(`  📲 PUSH → ${u?.displayName ?? userID}: ${JSON.stringify(payload)}`);
  if (!u?.pushToken) console.log(`     (no push token registered — B will poll instead)`);
}

/* ================================================================== */
/* HTTP                                                               */
/* ================================================================== */

const json = (res, code, body) => {
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
  res.end(JSON.stringify(body));
};

const readBody = (req) =>
  new Promise((resolve) => {
    let raw = "";
    req.on("data", (d) => (raw += d));
    req.on("end", () => { try { resolve(JSON.parse(raw || "{}")); } catch { resolve({}); } });
  });

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const q = url.searchParams;

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
    return res.end(PAGE);
  }

  const body = req.method === "POST" ? await readBody(req) : {};

  switch (url.pathname) {

    /* ---------- AUTH: registration ---------- */

    case "/register": {
      const phone = normPhone(body.phone);
      if (!phone) return json(res, 400, { error: "phone required" });

      // Re-registering the same phone returns the existing user, so the
      // app can call this idempotently on launch.
      const existing = userByPhone(phone);
      if (existing) {
        existing.pushToken = body.pushToken ?? existing.pushToken;
        persist();
        console.log(`↺ re-registered ${existing.displayName} (${phone})`);
        return json(res, 200, existing);
      }

      const user = {
        userID: UP(body.userID) || newUUID(),
        phone,
        displayName: body.displayName || phone,
        pushToken: body.pushToken ?? null,
      };
      db.users.push(user);
      persist();
      console.log(`+ registered ${user.displayName} (${phone}) → ${user.userID}`);
      return json(res, 200, user);
    }

    /* ---------- AUTH: lookup ---------- */

    case "/lookup": {
      const u = userByPhone(q.get("phone"));
      if (!u) {
        // The unregistered path. Currently a plain 404 — this is where the
        // SMS-invite fallback will go.
        console.log(`  ✗ lookup miss: ${q.get("phone")}`);
        return json(res, 404, { error: "not_registered" });
      }
      return json(res, 200, { userID: u.userID, displayName: u.displayName });
    }

    /* ---------- AUTH: invite ---------- */

    case "/invite": {
      const from = userByID(body.fromUserID);
      const to = userByID(body.toUserID);
      if (!from || !to) return json(res, 404, { error: "unknown user" });

      const invite = {
        inviteID: newUUID(),
        chatID: UP(body.chatID) || newUUID(),   // A generates this locally
        fromUserID: from.userID,
        fromDisplayName: from.displayName,
        toUserID: to.userID,
        status: "pending",
        createdAt: Date.now(),
      };
      db.invites.push(invite);
      persist();

      console.log(`✉ invite ${from.displayName} → ${to.displayName}  chat ${invite.chatID}`);
      sendPush(to.userID, {
        type: "chat_invite",
        inviteID: invite.inviteID,
        chatID: invite.chatID,
        from: from.displayName,
        // The deeplink B's app would open from the notification.
        deeplink: `securechat://invite/${invite.inviteID}`,
      });

      return json(res, 200, invite);
    }

    case "/invites": {
      // B polls this. With real APNs the push would carry the inviteID and
      // this becomes a fetch-by-id instead.
      const mine = db.invites.filter(
        (i) => i.toUserID === UP(q.get("userID")) && i.status === "pending"
      );
      return json(res, 200, mine);
    }

    case "/invite/accept": {
      const inv = db.invites.find((i) => i.inviteID === UP(body.inviteID));
      if (!inv) return json(res, 404, { error: "unknown invite" });
      if (inv.status !== "pending") return json(res, 409, { error: `already ${inv.status}` });

      inv.status = "accepted";

      // Membership is recorded on AUTH, not on the relay. The relay stays
      // ignorant of who belongs to what.
      let chat = chatByID(inv.chatID);
      if (!chat) {
        chat = { chatID: inv.chatID, memberIDs: [], createdAt: Date.now() };
        db.chats.push(chat);
      }
      for (const id of [inv.fromUserID, inv.toUserID]) {
        if (!chat.memberIDs.includes(id)) chat.memberIDs.push(id);
      }
      persist();

      console.log(`✓ accepted — chat ${chat.chatID} now has ${chat.memberIDs.length} members`);
      sendPush(inv.fromUserID, {
        type: "invite_accepted",
        chatID: chat.chatID,
        by: userByID(inv.toUserID)?.displayName,
      });

      return json(res, 200, chat);
    }

    case "/invite/decline": {
      const inv = db.invites.find((i) => i.inviteID === UP(body.inviteID));
      if (!inv) return json(res, 404, { error: "unknown invite" });
      inv.status = "declined";
      persist();
      console.log(`✗ declined invite ${inv.inviteID}`);
      sendPush(inv.fromUserID, { type: "invite_declined", chatID: inv.chatID });
      return json(res, 200, inv);
    }

    /* ---------- AUTH: chat list ---------- */

    case "/chats": {
      const userID = UP(q.get("userID"));
      const mine = db.chats
        .filter((c) => c.memberIDs.includes(userID))
        .map((c) => ({
          ...c,
          members: c.memberIDs.map((id) => {
            const u = userByID(id);
            return { userID: id, displayName: u?.displayName ?? "?" };
          }),
        }));
      return json(res, 200, mine);
    }

    /* ---------- panel helpers ---------- */

    case "/state":
      return json(res, 200, { ...db, connected: [...connections.keys()] });

    case "/reset":
      db = blank();
      persist();
      for (const set of connections.values()) for (const ws of set) ws.terminate();
      console.log("— reset");
      return json(res, 200, { ok: true });

    default:
      return json(res, 404, { error: "not found" });
  }
});

/* ================================================================== */
/* RELAY — no identity, no membership, no persistence                 */
/* ================================================================== */

/** chatID -> Set<ws>. In memory only; gone when the process dies. */
const rooms = new Map();

/** userID -> Set<ws>, panel display only. */
const connections = new Map();

const setFor = (map, key) => {
  let s = map.get(key);
  if (!s) { s = new Set(); map.set(key, s); }
  return s;
};

const wss = new WebSocketServer({ server, path: "/relay" });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const userID = UP(url.searchParams.get("as"));
  const chatID = UP(url.searchParams.get("chat"));

  if (!userID || !chatID) {
    console.log(`✗ relay: missing as= or chat=`);
    return ws.close(4000, "missing_params");
  }

  // NOTE: the relay does NOT check membership. It pairs whoever shows up with
  // the same chatID. Membership lives on auth and, in production, in the
  // clients' key agreement. Keeping the relay dumb is the point.
  ws.userID = userID;
  ws.chatID = chatID;
  setFor(rooms, chatID).add(ws);
  setFor(connections, userID).add(ws);

  const peers = setFor(rooms, chatID).size - 1;
  console.log(`→ relay: ${userByID(userID)?.displayName ?? userID} joined chat ${chatID} (${peers} peer(s) present)`);

  ws.on("message", (data, isBinary) => {
    let forwarded = 0;
    for (const peer of setFor(rooms, chatID)) {
      if (peer === ws || peer.readyState !== peer.OPEN) continue;
      peer.send(data, { binary: isBinary });
      forwarded++;
    }
    console.log(`  ↔ forwarded to ${forwarded} peer(s) in ${chatID}`);
  });

  ws.on("close", () => {
    const room = setFor(rooms, chatID);
    room.delete(ws);
    if (room.size === 0) rooms.delete(chatID);   // room evaporates
    setFor(connections, userID).delete(ws);
    if (setFor(connections, userID).size === 0) connections.delete(userID);
    console.log(`← relay: ${userID} left ${chatID}`);
  });

  ws.on("error", () => ws.terminate());
});

/* ================================================================== */

const PAGE = `<!doctype html><meta charset="utf-8">
<title>Pairing prototype</title>
<style>
 body{font:14px system-ui;max-width:920px;margin:30px auto;padding:0 20px;color:#111}
 h1{font-size:19px;margin:0 0 2px}
 h2{font-size:12px;text-transform:uppercase;letter-spacing:.07em;color:#777;margin:22px 0 8px}
 .sub{color:#666;margin-bottom:8px}
 .card{border:1px solid #e2e5ea;border-radius:10px;padding:14px;margin-bottom:12px;background:#fafbfc}
 input,select{font:inherit;padding:6px 9px;border:1px solid #cbd0d8;border-radius:7px}
 button{font:inherit;padding:6px 13px;border-radius:7px;border:1px solid #cbd0d8;background:#fff;cursor:pointer}
 button:hover{background:#f0f2f5}
 button.p{background:#1d6ef5;color:#fff;border-color:#1d6ef5}
 .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:8px}
 code{background:#eef1f5;padding:2px 5px;border-radius:4px;font-size:12px}
 .item{border:1px solid #e2e5ea;border-radius:8px;padding:10px;margin-bottom:7px;background:#fff;display:flex;justify-content:space-between;gap:10px;align-items:center}
 .muted{color:#777;font-size:12px}
 .dot{width:8px;height:8px;border-radius:99px;background:#c3c9d2;display:inline-block;margin-right:5px}
 .dot.on{background:#22c55e}
 .tag{font-size:11px;padding:2px 7px;border-radius:99px;background:#eef1f5}
</style>

<h1>Pairing prototype</h1>
<div class="sub">Auth + relay. No auth checks, no encryption — flow validation only.</div>
<div class="muted" style="margin-bottom:20px">Relay: <code>ws://localhost:${PORT}/relay?as=USER_ID&chat=CHAT_ID</code></div>

<h2>1 · Register</h2>
<div class="card">
  <div class="row">
    <input id="rphone" placeholder="Phone e.g. +447700900001">
    <input id="rname" placeholder="Display name">
    <button class="p" onclick="register()">Register</button>
  </div>
  <div id="users"></div>
</div>

<h2>2 · Look up &amp; invite</h2>
<div class="card">
  <div class="row">
    <select id="ifrom"></select>
    <span>invites phone</span>
    <input id="iphone" placeholder="+447700900002">
    <button onclick="lookup()">Look up</button>
    <button class="p" onclick="invite()">Look up &amp; invite</button>
  </div>
  <div id="lookupResult" class="muted"></div>
</div>

<h2>3 · Pending invites</h2>
<div class="card"><div id="invites"></div></div>

<h2>4 · Chats</h2>
<div class="card"><div id="chats"></div></div>

<div class="row" style="margin-top:20px"><button onclick="reset()">Reset everything</button></div>

<script>
var S={users:[],invites:[],chats:[],connected:[]};
function api(p,b){return fetch(p,b?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}:undefined).then(function(r){return r.json().then(function(j){return {ok:r.ok,body:j}})})}
function load(){return api('/state').then(function(r){S=r.body;render()})}

function render(){
  document.getElementById('users').innerHTML = S.users.length ? S.users.map(function(u){
    var on = S.connected.indexOf(u.userID)>=0;
    return '<div class="item"><div><span class="dot'+(on?' on':'')+'"></span><b>'+u.displayName+'</b> '
      +'<span class="muted">'+u.phone+'</span><div class="muted">'+u.userID+'</div></div></div>'
  }).join('') : '<div class="muted">No users yet.</div>';

  var sel=document.getElementById('ifrom'), keep=sel.value;
  sel.innerHTML=S.users.map(function(u){return '<option value="'+u.userID+'">'+u.displayName+'</option>'}).join('');
  if(keep) sel.value=keep;

  var pend=S.invites.filter(function(i){return i.status==='pending'});
  document.getElementById('invites').innerHTML = pend.length ? pend.map(function(i){
    var to=S.users.find(function(u){return u.userID===i.toUserID});
    return '<div class="item"><div><b>'+i.fromDisplayName+'</b> → <b>'+(to?to.displayName:'?')+'</b>'
      +'<div class="muted">chat <code>'+i.chatID+'</code></div></div>'
      +'<div><button class="p" onclick="accept(\\''+i.inviteID+'\\')">Accept</button> '
      +'<button onclick="decline(\\''+i.inviteID+'\\')">Decline</button></div></div>'
  }).join('') : '<div class="muted">No pending invites.</div>';

  document.getElementById('chats').innerHTML = S.chats.length ? S.chats.map(function(c){
    var names=c.memberIDs.map(function(id){var u=S.users.find(function(x){return x.userID===id});return u?u.displayName:'?'}).join(' ↔ ');
    return '<div class="item"><div><b>'+names+'</b><div class="muted">chat <code>'+c.chatID+'</code></div></div></div>'
  }).join('') : '<div class="muted">No chats yet.</div>';
}

function register(){
  api('/register',{phone:document.getElementById('rphone').value,displayName:document.getElementById('rname').value,pushToken:'mock-token'})
    .then(function(){document.getElementById('rphone').value='';document.getElementById('rname').value='';load()});
}
function lookup(){
  var p=encodeURIComponent(document.getElementById('iphone').value);
  api('/lookup?phone='+p).then(function(r){
    document.getElementById('lookupResult').innerHTML = r.ok
      ? '✓ '+r.body.displayName+' <code>'+r.body.userID+'</code>'
      : '✗ not registered — this is the fallback path to build next';
  });
}
function invite(){
  var p=encodeURIComponent(document.getElementById('iphone').value);
  api('/lookup?phone='+p).then(function(r){
    if(!r.ok){document.getElementById('lookupResult').innerHTML='✗ not registered — cannot invite yet';return}
    document.getElementById('lookupResult').innerHTML='✓ found '+r.body.displayName+', inviting…';
    return api('/invite',{fromUserID:document.getElementById('ifrom').value,toUserID:r.body.userID}).then(load);
  });
}
function accept(id){api('/invite/accept',{inviteID:id}).then(load)}
function decline(id){api('/invite/decline',{inviteID:id}).then(load)}
function reset(){if(confirm('Wipe everything?'))api('/reset',{}).then(load)}

load(); setInterval(load,2000);
</script>`;

server.listen(PORT, () => {
  console.log(`panel      http://localhost:${PORT}`);
  console.log(`relay      ws://localhost:${PORT}/relay?as=<userID>&chat=<chatID>`);
  console.log(`state      ${STATE_FILE}`);
});
