// ============================================================================
// OpenMoney Sync v2 — Cloudflare Durable Object (UserSyncRoom)
// SQLite-backed Durable Object + WebSocket Hibernation (Compatível com Free Plan)
// ============================================================================

export class UserSyncRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sql = state.storage.sql;
    this._initSchema();
  }

  _initSchema() {
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS meta (
        k TEXT PRIMARY KEY,
        v TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS records (
        coll TEXT NOT NULL,
        id TEXT NOT NULL,
        encrypted_data TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        seq INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (coll, id)
      );
      CREATE INDEX IF NOT EXISTS idx_records_seq ON records(seq);
      CREATE TABLE IF NOT EXISTS ops (
        op_id TEXT PRIMARY KEY,
        seq INTEGER NOT NULL,
        created_at TEXT NOT NULL
      );
    `);
  }

  _getSeq() {
    const row = this.sql.exec(`SELECT v FROM meta WHERE k = 'seq'`).toArray()[0];
    return row ? Number(row.v) : 0;
  }

  _setSeq(seq) {
    this.sql.exec(
      `INSERT INTO meta (k, v) VALUES ('seq', ?1)
       ON CONFLICT(k) DO UPDATE SET v = excluded.v`,
      String(seq)
    );
  }

  async fetch(request) {
    const url = new URL(request.url);
    const upgradeHeader = request.headers.get("Upgrade") || "";

    // 1. WebSocket Upgrade com Hibernação Nativa (0ms broadcast)
    if (upgradeHeader.toLowerCase() === "websocket") {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.state.acceptWebSocket(server);
      const currentSeq = this._getSeq();
      try {
        server.send(
          JSON.stringify({
            type: "hello",
            seq: currentSeq,
          })
        );
      } catch (_) {}
      return new Response(null, { status: 101, webSocket: client });
    }

    // 2. Broadcast de notificação disparado pela Pages Function (/api/sync)
    if (url.pathname.endsWith("/notify") && request.method === "POST") {
      try {
        const body = await request.json();
        this._setSeq(Number(body.seq || this._getSeq()));
        this._broadcast(
          JSON.stringify({
            type: "sync",
            seq: body.seq,
            opId: body.opId || null,
            reset: Boolean(body.reset),
            changes: Array.isArray(body.changes) ? body.changes : [],
          })
        );
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    return new Response(
      JSON.stringify({ ok: true, seq: this._getSeq() }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  async webSocketMessage(ws, message) {
    try {
      const data = typeof message === "string" ? JSON.parse(message) : null;
      if (!data) return;
      if (data.type === "ping") {
        ws.send(
          JSON.stringify({
            type: "pong",
            seq: this._getSeq(),
          })
        );
      }
    } catch (_) {}
  }

  async webSocketClose(ws, code, reason, wasClean) {
    try {
      ws.close(code, "Connection closed");
    } catch (_) {}
  }

  async webSocketError(ws, error) {
    try {
      ws.close(1011, "WebSocket error");
    } catch (_) {}
  }

  _broadcast(payloadStr, excludeWs = null) {
    const sockets = this.state.getWebSockets();
    for (const sock of sockets) {
      if (excludeWs && sock === excludeWs) continue;
      try {
        sock.send(payloadStr);
      } catch (_) {
        try {
          sock.close(1011, "Stale socket");
        } catch (__) {}
      }
    }
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const userId = request.headers.get("X-OpenMoney-User-Id") || url.searchParams.get("userId");
    if (!userId) {
      return new Response(JSON.stringify({ error: "Missing userId" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    const id = env.SYNC.idFromName(userId);
    const stub = env.SYNC.get(id);
    return stub.fetch(request);
  },
};
