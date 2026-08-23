/**
 * Pairing prototype — auth + relay in one process, with OTP verification.
 *
 *   npm i ws
 *   node pairing-server.mjs
 *
 * Web panel:  http://localhost:8080     ← the OTP code is shown here
 * WebSocket:  ws://localhost:8080/relay?as=<userID>&chat=<chatID>
 *
 * NO real auth, NO encryption. Flow validation only.
 *
 * AUTH  — durable. Phones, users, OTPs, invites, chat membership.
 * RELAY — ephemeral. Knows only which sockets are open. Forwards bytes.
 */

import { WebSocketServer } from "ws";
import { createServer } from "node:http";
import { randomUUID, randomInt } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const PORT = Number(process.env.PORT ?? 8080);
const STATE_FILE = "./.pairing.json";

const OTP_TTL_MS = 5 * 60 * 1000;   // code expires after 5 minutes
const OTP_MAX_ATTEMPTS = 3;         // wrong guesses before the code is burned
const RESEND_COOLDOWN_MS = 30_000;  // minimum gap between sends

const UP = (s) => String(s ?? "").toUpperCase();
const newUUID = () => randomUUID().toUpperCase();
const newOTP = () => String(randomInt(0, 1_000_000)).padStart(6, "0");

// "+44 7700 900123" and "07700900123" must not become two users.
const normPhone = (s) => String(s ?? "").replace(/[^\d+]/g, "");

/* ================================================================== */
/* AUTH STATE                                                         */
/* ================================================================== */

const blank = () => ({
  users: [],      // see shape below
  invites: [],
  chats: [],
});

/*
 User:
 {
   userID, phone, displayName, pushToken,
   status: "pending_verification" | "verified",
   registeredAt: null | epochMs,          ← set on successful verification
   otp: null | { code, expiresAt, attempts, sentAt }
 }
*/

let db = existsSync(STATE_FILE)
  ? JSON.parse(readFileSync(STATE_FILE, "utf8"))
  : blank();

const persist = () => writeFileSync(STATE_FILE, JSON.stringify(db, null, 2));

const userByID = (id) => db.users.find((u) => u.userID === UP(id));
const userByPhone = (p) => db.users.find((u) => u.phone === normPhone(p));
const verifiedByPhone = (p) => {
  const u = userByPhone(p);
  return u && u.status === "verified" ? u : null;
};
const chatByID = (id) => db.chats.find((c) => c.chatID === UP(id));

/** Public shape — never leak the OTP object to the client. */
const publicUser = (u) => ({
  userID: u.userID,
  phone: u.phone,
  displayName: u.displayName,
  status: u.status,
  registeredAt: u.registeredAt,
});

/** Issues a fresh OTP. In production this is where the SMS goes out. */
function issueOTP(user) {
  const code = newOTP();
  user.otp = { code, expiresAt: Date.now() + OTP_TTL_MS, attempts: 0, sentAt: Date.now() };
  persist();
  console.log(`  🔑 OTP for ${user.phone}: ${code}   (expires in ${OTP_TTL_MS / 60000} min)`);
  return user.otp;
}

/** Stands in for APNs. */
function sendPush(userID, payload) {
  const u = userByID(userID);
  console.log(`  📲 PUSH → ${u?.displayName ?? userID}: ${JSON.stringify(payload)}`);
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
  const path = url.pathname;

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PUT",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    return res.end();
  }

  if (path === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return res.end(PAGE);
  }

  const body = (req.method === "POST" || req.method === "PUT") ? await readBody(req) : {};

  /* ---------- PUT /users/:userID/phone ---------- */
  // PUT because it replaces a single value and is idempotent: sending the
  // same number twice leaves the same state. Side effect: issues a new OTP
  // and drops the user back to pending_verification.
  const phoneMatch = path.match(/^\/users\/([^/]+)\/phone$/);
  if (phoneMatch && req.method === "PUT") {
    const user = userByID(decodeURIComponent(phoneMatch[1]));
    if (!user) return json(res, 404, { error: "unknown_user" });

    const phone = normPhone(body.phone);
    if (!phone) return json(res, 400, { error: "phone_required" });

    const owner = verifiedByPhone(phone);
    if (owner && owner.userID !== user.userID) {
      return json(res, 409, { error: "phone_taken" });
    }

    // Same number → no state change, but re-issue so a lost SMS is recoverable.
    const changed = user.phone !== phone;
    user.phone = phone;
    if (changed) {
      user.status = "pending_verification";
      user.registeredAt = null;
    }
    const otp = issueOTP(user);
    persist();

    console.log(`↻ phone updated for ${user.userID} → ${phone}`);
    return json(res, 200, {
      ...publicUser(user),
      otpExpiresAt: otp.expiresAt,
      attemptsRemaining: OTP_MAX_ATTEMPTS,
    });
  }

  switch (path) {

    /* ---------- POST /register ---------- */
    // Step 1. Stores the details, issues an OTP, returns a PENDING user.
    // Idempotent on phone: re-registering re-issues rather than duplicating.
    case "/register": {
      if (req.method !== "POST") return json(res, 405, { error: "method_not_allowed" });

      const phone = normPhone(body.phone);
      if (!phone) return json(res, 400, { error: "phone_required" });

      let user = userByPhone(phone);

      if (user) {
        // Re-registration of a known number. Real apps allow this (new device,
        // reinstall). Production would gate it behind a registration lock PIN.
        if (body.userID) user.userID = UP(body.userID);
        if (body.displayName) user.displayName = body.displayName;
        if (body.pushToken) user.pushToken = body.pushToken;
        user.status = "pending_verification";
        user.registeredAt = null;
        console.log(`↺ re-registering ${phone}`);
      } else {
        user = {
          userID: UP(body.userID) || newUUID(),
          phone,
          displayName: body.displayName || phone,
          pushToken: body.pushToken ?? null,
          status: "pending_verification",
          registeredAt: null,
          otp: null,
        };
        db.users.push(user);
        console.log(`+ registering ${user.displayName} (${phone}) → ${user.userID}`);
      }

      const otp = issueOTP(user);
      persist();

      return json(res, 200, {
        ...publicUser(user),
        otpExpiresAt: otp.expiresAt,
        attemptsRemaining: OTP_MAX_ATTEMPTS,
      });
    }

    /* ---------- POST /register/verify ---------- */
    // Step 2. POST because it has side effects (consumes an attempt,
    // transitions state) — it is an action, not a resource replacement.
    case "/register/verify": {
      if (req.method !== "POST") return json(res, 405, { error: "method_not_allowed" });

      const user = userByID(body.userID);
      if (!user) return json(res, 404, { error: "unknown_user" });

      if (user.status === "verified" && !user.otp) {
        // Already done — a retry after a dropped response. Treat as success.
        return json(res, 200, publicUser(user));
      }
      if (!user.otp) return json(res, 409, { error: "no_pending_verification" });

      if (Date.now() > user.otp.expiresAt) {
        user.otp = null;
        persist();
        return json(res, 410, { error: "code_expired" });
      }

      if (user.otp.attempts >= OTP_MAX_ATTEMPTS) {
        user.otp = null;
        persist();
        return json(res, 429, { error: "too_many_attempts" });
      }

      const code = String(body.code ?? "").trim();
      if (code !== user.otp.code) {
        user.otp.attempts += 1;
        const left = OTP_MAX_ATTEMPTS - user.otp.attempts;
        if (left <= 0) user.otp = null;
        persist();
        console.log(`  ✗ wrong OTP for ${user.phone} (${left} left)`);
        return json(res, 401, { error: "invalid_code", attemptsRemaining: Math.max(0, left) });
      }

      user.status = "verified";
      user.registeredAt = Date.now();     // ← client sets its registration date from this
      user.otp = null;
      persist();

      console.log(`✓ verified ${user.displayName} (${user.phone})`);
      return json(res, 200, publicUser(user));
    }

    /* ---------- POST /register/resend ---------- */
    case "/register/resend": {
      if (req.method !== "POST") return json(res, 405, { error: "method_not_allowed" });

      const user = userByID(body.userID);
      if (!user) return json(res, 404, { error: "unknown_user" });
      if (user.status === "verified") return json(res, 409, { error: "already_verified_cippa" });

      const since = user.otp ? Date.now() - user.otp.sentAt : Infinity;
      if (since < RESEND_COOLDOWN_MS) {
        return json(res, 429, {
          error: "resend_too_soon",
          retryAfterMs: RESEND_COOLDOWN_MS - since,
        });
      }

      const otp = issueOTP(user);
      return json(res, 200, {
        ...publicUser(user),
        otpExpiresAt: otp.expiresAt,
        attemptsRemaining: OTP_MAX_ATTEMPTS,
      });
    }

    /* ---------- GET /lookup ---------- */
    // Only verified users are discoverable. A pending user does not exist
    // as far as the rest of the system is concerned.
    case "/lookup": {
      const u = verifiedByPhone(q.get("phone"));
      if (!u) {
        console.log(`  ✗ lookup miss: ${q.get("phone")}`);
        return json(res, 404, { error: "not_registered" });
      }
      return json(res, 200, { userID: u.userID, displayName: u.displayName });
    }

    /* ---------- POST /invite ---------- */
    case "/invite": {
      const from = userByID(body.fromUserID);
      const to = userByID(body.toUserID);
      if (!from || !to) return json(res, 404, { error: "unknown_user" });
      if (from.status !== "verified") return json(res, 403, { error: "sender_not_verified" });
      if (to.status !== "verified") return json(res, 403, { error: "recipient_not_verified" });

      const invite = {
        inviteID: newUUID(),
        chatID: UP(body.chatID) || newUUID(),
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
        deeplink: `securechat://invite/${invite.inviteID}`,
      });

      return json(res, 200, invite);
    }

    case "/invites": {
      const mine = db.invites.filter(
        (i) => i.toUserID === UP(q.get("userID")) && i.status === "pending"
      );
      return json(res, 200, mine);
    }

    case "/invite/accept": {
      const inv = db.invites.find((i) => i.inviteID === UP(body.inviteID));
      if (!inv) return json(res, 404, { error: "unknown_invite" });
      if (inv.status !== "pending") return json(res, 409, { error: `already_${inv.status}` });

      inv.status = "accepted";

      let chat = chatByID(inv.chatID);
      if (!chat) {
        chat = { chatID: inv.chatID, memberIDs: [], createdAt: Date.now() };
        db.chats.push(chat);
      }
      for (const id of [inv.fromUserID, inv.toUserID]) {
        if (!chat.memberIDs.includes(id)) chat.memberIDs.push(id);
      }
      persist();

      console.log(`✓ accepted — chat ${chat.chatID} has ${chat.memberIDs.length} members`);
      sendPush(inv.fromUserID, {
        type: "invite_accepted",
        chatID: chat.chatID,
        by: userByID(inv.toUserID)?.displayName,
      });
      return json(res, 200, chat);
    }

    case "/invite/decline": {
      const inv = db.invites.find((i) => i.inviteID === UP(body.inviteID));
      if (!inv) return json(res, 404, { error: "unknown_invite" });
      inv.status = "declined";
      persist();
      sendPush(inv.fromUserID, { type: "invite_declined", chatID: inv.chatID });
      return json(res, 200, inv);
    }

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

    /* ---------- panel ---------- */

    case "/state":
      // Includes OTP codes — panel only. A real server never exposes this.
      return json(res, 200, { ...db, connected: [...connections.keys()] });

    case "/reset":
      db = blank();
      persist();
      for (const set of connections.values()) for (const ws of set) ws.terminate();
      console.log("— reset");
      return json(res, 200, { ok: true });

    default:
      return json(res, 404, { error: "not_found" });
  }
});

/* ================================================================== */
/* RELAY                                                              */
/* ================================================================== */

const rooms = new Map();        // chatID -> Set<ws>
const connections = new Map();  // userID -> Set<ws>, panel display only

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

  // The relay does NOT check membership or verification. It pairs whoever
  // shows up with the same chatID. Membership lives on auth, and in
  // production lives in the clients' key agreement.
  ws.userID = userID;
  ws.chatID = chatID;
  setFor(rooms, chatID).add(ws);
  setFor(connections, userID).add(ws);

  console.log(`→ relay: ${userByID(userID)?.displayName ?? userID} joined ${chatID} (${setFor(rooms, chatID).size - 1} peer(s))`);

  ws.on("message", (data, isBinary) => {
    let n = 0;
    for (const peer of setFor(rooms, chatID)) {
      if (peer === ws || peer.readyState !== peer.OPEN) continue;
      peer.send(data, { binary: isBinary });
      n++;
    }
    console.log(`  ↔ forwarded to ${n} peer(s) in ${chatID}`);
  });

  ws.on("close", () => {
    const room = setFor(rooms, chatID);
    room.delete(ws);
    if (room.size === 0) rooms.delete(chatID);
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
 .otp{font:700 24px ui-monospace,Menlo,monospace;letter-spacing:.16em;color:#b45309;background:#fef3c7;
      border:1px solid #fcd34d;border-radius:8px;padding:6px 12px;display:inline-block}
 .badge{font-size:11px;padding:2px 8px;border-radius:99px;background:#eef1f5;color:#555}
 .badge.ok{background:#dcfce7;color:#166534}
 .badge.pend{background:#fef3c7;color:#92400e}
</style>

<h1>Pairing prototype</h1>
<div class="sub">Auth + relay. No real auth, no encryption — flow validation only.</div>
<div class="muted" style="margin-bottom:20px">Relay: <code>ws://localhost:${PORT}/relay?as=USER_ID&chat=CHAT_ID</code></div>

<h2>1 · Register</h2>
<div class="card">
  <div class="row">
    <input id="rphone" placeholder="Phone e.g. +447700900001">
    <input id="rname" placeholder="Display name">
    <button class="p" onclick="register()">Register</button>
  </div>
  <div class="muted">The OTP appears below. Send it from the app to <code>POST /register/verify</code>.</div>
</div>

<h2>2 · Users</h2>
<div class="card"><div id="users"></div></div>

<h2>3 · Look up &amp; invite</h2>
<div class="card">
  <div class="row">
    <select id="ifrom"></select>
    <span>invites</span>
    <input id="iphone" placeholder="+447700900002">
    <button onclick="lookup()">Look up</button>
    <button class="p" onclick="invite()">Look up &amp; invite</button>
  </div>
  <div id="lookupResult" class="muted"></div>
</div>

<h2>4 · Pending invites</h2>
<div class="card"><div id="invites"></div></div>

<h2>5 · Chats</h2>
<div class="card"><div id="chats"></div></div>

<div class="row" style="margin-top:20px"><button onclick="reset()">Reset everything</button></div>

<script>
var S={users:[],invites:[],chats:[],connected:[]};
function api(p,b,m){
  var o = b!==undefined ? {method:m||'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)} : undefined;
  return fetch(p,o).then(function(r){return r.json().then(function(j){return {ok:r.ok,status:r.status,body:j}})});
}
function load(){return api('/state').then(function(r){S=r.body;render()})}

function render(){
  document.getElementById('users').innerHTML = S.users.length ? S.users.map(function(u){
    var on = S.connected.indexOf(u.userID)>=0;
    var verified = u.status==='verified';
    var h = '<div class="item"><div><span class="dot'+(on?' on':'')+'"></span><b>'+u.displayName+'</b> '
      + '<span class="badge '+(verified?'ok':'pend')+'">'+(verified?'verified':'pending')+'</span>'
      + '<div class="muted">'+u.phone+'</div>'
      + '<div class="muted">'+u.userID+'</div>';
    if(u.registeredAt) h += '<div class="muted">registered '+new Date(u.registeredAt).toLocaleString()+'</div>';
    h += '</div><div style="text-align:right">';
    if(u.otp){
      var left = Math.max(0, Math.round((u.otp.expiresAt-Date.now())/1000));
      h += '<div class="otp">'+u.otp.code+'</div>'
        + '<div class="muted" style="margin-top:4px">expires in '+left+'s · '+(3-u.otp.attempts)+' attempts left</div>'
        + '<div style="margin-top:6px"><button onclick="resend(\\''+u.userID+'\\')">Resend</button></div>';
    }
    h += '</div></div>';
    return h;
  }).join('') : '<div class="muted">No users yet.</div>';

  var sel=document.getElementById('ifrom'), keep=sel.value;
  var verified = S.users.filter(function(u){return u.status==='verified'});
  sel.innerHTML=verified.map(function(u){return '<option value="'+u.userID+'">'+u.displayName+'</option>'}).join('');
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
function resend(id){ api('/register/resend',{userID:id}).then(function(r){ if(!r.ok) alert(r.body.error); load() }) }
function lookup(){
  api('/lookup?phone='+encodeURIComponent(document.getElementById('iphone').value)).then(function(r){
    document.getElementById('lookupResult').innerHTML = r.ok
      ? '✓ '+r.body.displayName+' <code>'+r.body.userID+'</code>'
      : '✗ not registered (or not yet verified)';
  });
}
function invite(){
  api('/lookup?phone='+encodeURIComponent(document.getElementById('iphone').value)).then(function(r){
    if(!r.ok){document.getElementById('lookupResult').innerHTML='✗ not registered — cannot invite';return}
    return api('/invite',{fromUserID:document.getElementById('ifrom').value,toUserID:r.body.userID}).then(load);
  });
}
function accept(id){api('/invite/accept',{inviteID:id}).then(load)}
function decline(id){api('/invite/decline',{inviteID:id}).then(load)}
function reset(){if(confirm('Wipe everything?'))api('/reset',{}).then(load)}

load(); setInterval(load,1000);
</script>`;

server.listen(PORT, () => {
  console.log(`panel      http://localhost:${PORT}`);
  console.log(`relay      ws://localhost:${PORT}/relay?as=<userID>&chat=<chatID>`);
  console.log(`state      ${STATE_FILE}`);
});
