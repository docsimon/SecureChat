/**
 * Zero-knowledge WebSocket relay.
 *
 * Invariants this file exists to enforce:
 *   1. Nothing touches disk. Ever.
 *   2. Rooms live only while a socket holds them open.
 *   3. The relay never parses, inspects, or logs `payload`.
 *   4. No identity claim is accepted without a signature over a server nonce.
 *   5. A room holds at most ROOM_CAPACITY peers (default 2) — a third
 *      connection is refused, not silently admitted.
 *
 *   npm init -y && npm i ws
 *   node relay-server.mjs
 *
 * Env:
 *   PORT=8080
 *   ROOM_CAPACITY=2
 *   VERBOSE=1            log connection lifecycle (NEVER enable in production)
 *   CHAOS_KILL_MS=15000  randomly sever a connection, to test client recovery
 */

import { WebSocketServer } from "ws";
import { createPublicKey, randomBytes, verify, createHash } from "node:crypto";

const PORT = Number(process.env.PORT ?? 8080);
const ROOM_CAPACITY = Number(process.env.ROOM_CAPACITY ?? 2);
const VERBOSE = !!process.env.VERBOSE;
const CHAOS_KILL_MS = Number(process.env.CHAOS_KILL_MS ?? 0);

const AUTH_CONTEXT = "securechat-relay-auth-v1|";
const AUTH_TIMEOUT_MS = 10_000;
const HEARTBEAT_MS = 20_000;
const MAX_PAYLOAD_BYTES = 128 * 1024;
const RATE_CAPACITY = 60; // burst
const RATE_REFILL_PER_SEC = 30;

const log = (...a) => VERBOSE && console.log(...a);

/* ------------------------------------------------------------------ */
/* Identity: a UUID is only meaningful if it is derived from a key      */
/* ------------------------------------------------------------------ */

// SPKI DER prefixes let us accept raw public keys without a dependency.
const SPKI_ED25519 = Buffer.from("302a300506032b6570032100", "hex"); // + 32 bytes
const SPKI_P256 = Buffer.from(
  "3059301306072a8648ce3d020106082a8648ce3d030107034200",
  "hex",
); // + 65 bytes (uncompressed point, leading 0x04)

function importPublicKey(alg, raw) {
  if (alg === "Ed25519") {
    if (raw.length !== 32) throw new Error("bad Ed25519 key length");
    return createPublicKey({
      key: Buffer.concat([SPKI_ED25519, raw]),
      format: "der",
      type: "spki",
    });
  }
  if (alg === "P-256") {
    if (raw.length !== 65 || raw[0] !== 0x04) throw new Error("bad P-256 point");
    return createPublicKey({
      key: Buffer.concat([SPKI_P256, raw]),
      format: "der",
      type: "spki",
    });
  }
  throw new Error("unsupported alg");
}

function verifySignature(alg, key, message, signature) {
  if (alg === "Ed25519") return verify(null, message, key, signature);
  // CryptoKit's P256 `rawRepresentation` is a fixed-width r||s pair, not DER.
  return verify("sha256", message, { key, dsaEncoding: "ieee-p1363" }, signature);
}

/**
 * userId = UUID derived from the public key.
 * Keeps the client's UUID mental model, but the UUID is now unforgeable:
 * you cannot claim it without holding the private key.
 */
function deriveUserId(rawPubkey) {
  const h = createHash("sha256").update(rawPubkey).digest();
  const b = Buffer.from(h.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x80; // RFC 9562 version 8 (custom)
  b[8] = (b[8] & 0x3f) | 0x80; // variant
  const hex = b.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/* ------------------------------------------------------------------ */
/* Rooms: in-memory only, garbage collected when the last peer leaves   */
/* ------------------------------------------------------------------ */

/** @type {Map<string, Set<any>>} */
const rooms = new Map();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function fail(ws, code, message, close = false) {
  send(ws, { t: "error", code, message });
  if (close) ws.close(4000, code);
}

function leaveRoom(ws) {
  const id = ws.roomId;
  if (!id) return;
  ws.roomId = null;
  const peers = rooms.get(id);
  if (!peers) return;
  peers.delete(ws);
  for (const p of peers) send(p, { t: "peer-leave", room: id, userId: ws.userId });
  if (peers.size === 0) {
    rooms.delete(id); // the room ceases to exist. No tombstone, no record.
    log("room evaporated");
  }
}

/* ------------------------------------------------------------------ */

const wss = new WebSocketServer({
  host: "0.0.0.0",
  port: PORT,
  maxPayload: MAX_PAYLOAD_BYTES,
  // Compression is off deliberately: compressing attacker-influenced data
  // alongside secret data is the CRIME/BREACH shape. Payloads are ciphertext
  // and will not compress anyway.
  perMessageDeflate: false,
});

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.authed = false;
  ws.userId = null;
  ws.roomId = null;
  ws.nonce = randomBytes(32);
  ws.tokens = RATE_CAPACITY;
  ws.lastRefill = Date.now();

  ws.on("pong", () => { ws.isAlive = true; });

  const authTimer = setTimeout(() => {
    if (!ws.authed) fail(ws, "auth_timeout", "No auth frame", true);
  }, AUTH_TIMEOUT_MS);

  send(ws, { t: "challenge", v: 1, nonce: ws.nonce.toString("base64") });

  ws.on("message", (raw) => {
    // Token bucket, applied before any parsing.
    const now = Date.now();
    ws.tokens = Math.min(
      RATE_CAPACITY,
      ws.tokens + ((now - ws.lastRefill) / 1000) * RATE_REFILL_PER_SEC,
    );
    ws.lastRefill = now;
    if (ws.tokens < 1) return fail(ws, "rate_limited", "Slow down", true);
    ws.tokens -= 1;

    let m;
    try {
      m = JSON.parse(raw.toString());
    } catch {
      return fail(ws, "bad_json", "Frame was not valid JSON");
    }
    if (typeof m?.t !== "string") return fail(ws, "bad_frame", "Missing type");

    /* ---- handshake ---- */
    if (m.t === "auth") {
      if (ws.authed) return fail(ws, "already_authed", "Already authenticated");
      try {
        const raw = Buffer.from(String(m.pk ?? ""), "base64");
        const sig = Buffer.from(String(m.sig ?? ""), "base64");
        const key = importPublicKey(m.alg, raw);
        // Domain-separated and bound to this connection's nonce, so a captured
        // signature cannot be replayed onto another connection or protocol.
        const signed = Buffer.from(AUTH_CONTEXT + ws.nonce.toString("base64"), "utf8");
        if (!verifySignature(m.alg, key, signed, sig)) throw new Error("bad signature");

        ws.authed = true;
        ws.userId = deriveUserId(raw);
        ws.nonce = null;
        clearTimeout(authTimer);
        send(ws, { t: "ready", userId: ws.userId, capacity: ROOM_CAPACITY });
        log("authed");
      } catch {
        // Deliberately uninformative: do not help an attacker probe key formats.
        return fail(ws, "auth_failed", "Authentication failed", true);
      }
      return;
    }

    if (!ws.authed) return fail(ws, "unauthenticated", "Authenticate first", true);

    /* ---- authenticated frames ---- */
    switch (m.t) {
      case "open": {
        const id = String(m.room ?? "");
        if (!UUID_RE.test(id)) return fail(ws, "bad_room", "Room must be a UUID");
        if (ws.roomId === id) return;
        leaveRoom(ws);

        let peers = rooms.get(id);
        if (!peers) { peers = new Set(); rooms.set(id, peers); }
        if (peers.size >= ROOM_CAPACITY) {
          if (peers.size === 0) rooms.delete(id);
          return fail(ws, "room_full", "Room is at capacity");
        }

        const existing = [...peers].map((p) => p.userId);
        peers.add(ws);
        ws.roomId = id;
        send(ws, { t: "room", room: id, peers: existing });
        for (const p of peers) {
          if (p !== ws) send(p, { t: "peer-join", room: id, userId: ws.userId });
        }
        log("room opened");
        break;
      }

      case "msg": {
        if (!ws.roomId || ws.roomId !== m.room) {
          return fail(ws, "not_in_room", "Open the room first");
        }
        // `payload` is opaque. It is length-checked and forwarded verbatim.
        // It is never parsed, never inspected, never retained.
        if (typeof m.payload !== "string" || m.payload.length === 0) {
          return fail(ws, "bad_payload", "payload must be a non-empty string");
        }
        const peers = rooms.get(ws.roomId);
        let delivered = 0;
        for (const p of peers) {
          if (p === ws) continue;
          send(p, { t: "msg", room: ws.roomId, from: ws.userId, payload: m.payload });
          delivered += 1;
        }
        // Truthful delivery signal: the client must be able to tell
        // "handed to a peer socket" from "dropped on the floor".
        send(ws, { t: "ack", ref: m.ref ?? null, delivered });
        break;
      }

      case "close":
        leaveRoom(ws);
        break;

      default:
        fail(ws, "unknown_type", `Unhandled type: ${m.t}`);
    }
  });

  ws.on("close", () => { clearTimeout(authTimer); leaveRoom(ws); });
  ws.on("error", () => ws.terminate());
});

// Reap half-open sockets. A peer that vanished with the Wi-Fi never sends a
// close frame, and under this design a stale peer means messages silently
// disappear — so detection has to be aggressive.
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_MS).unref();

if (CHAOS_KILL_MS > 0) {
  setInterval(() => {
    const all = [...wss.clients];
    if (!all.length) return;
    all[Math.floor(Math.random() * all.length)].terminate(); // no close frame
  }, CHAOS_KILL_MS).unref();
}

console.log(`relay listening on :${PORT}  capacity=${ROOM_CAPACITY}  verbose=${VERBOSE}`);
