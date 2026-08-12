/**
 * WebSocket echo server. Sends back exactly what it receives.
 *
 *   npm i ws
 *   node echo-server.mjs
 *
 * Connect to: ws://localhost:8080
 */

import { WebSocketServer } from "ws";

const PORT = Number(process.env.PORT ?? 8080);

const wss = new WebSocketServer({ port: PORT });

wss.on("connection", (ws) => {
  console.log("→ connected");

  ws.on("message", (data, isBinary) => {
    console.log(isBinary ? `  echo ${data.length} bytes` : `  echo ${data}`);
    ws.send(data, { binary: isBinary });
  });

  ws.on("close", (code) => console.log(`← disconnected (${code})`));
  ws.on("error", (err) => console.log(`! ${err.message}`));
});

console.log(`ws://localhost:${PORT}`);
