// ============================================================================
// OpenMoney Cloud — Cloudflare Pages Function (/api/*)
// Isolamento estrito por usuário + PBKDF2 (100k iter) + JWT (HMAC-SHA256)
// + Criptografia em repouso por usuário (AES-256-GCM com chave HKDF por user_id)
// ============================================================================

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let schemaInitialized = false;

async function ensureSchema(db) {
  if (schemaInitialized || !db) return;
  await db.batch([
    db.prepare(`
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        created_at TEXT NOT NULL,
        last_login_at TEXT
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_databases (
        user_id TEXT PRIMARY KEY,
        schema_version INTEGER NOT NULL DEFAULT 7,
        revision INTEGER NOT NULL DEFAULT 1,
        payload TEXT NOT NULL,
        preferences TEXT NOT NULL DEFAULT '{}',
        updated_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_database_backups (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        backup_date TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (user_id, backup_date)
      )
    `),
  ]);
  schemaInitialized = true;
}

function corsHeaders(origin) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  };
}

function jsonResponse(data, status = 200, origin = "*") {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders(origin),
  });
}

function bytesToBase64(bytes) {
  const CHUNK_SIZE = 0x8000; // 32768
  let binary = "";
  const len = bytes.byteLength;
  for (let i = 0; i < len; i += CHUNK_SIZE) {
    const chunk = bytes.subarray(i, Math.min(i + CHUNK_SIZE, len));
    binary += String.fromCharCode.apply(null, chunk);
  }
  return btoa(binary);
}

function base64ToBytes(b64) {
  const binary = atob(b64);
  const len = binary.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// Compressão Gzip nativa (Web Streams) para manter payloads em <10% do tamanho
async function compressGzip(text) {
  const cs = new CompressionStream("gzip");
  const writer = cs.writable.getWriter();
  writer.write(encoder.encode(text));
  writer.close();
  const buffer = await new Response(cs.readable).arrayBuffer();
  return new Uint8Array(buffer);
}

// Descompressão Gzip nativa (Web Streams)
async function decompressGzip(bytes) {
  const ds = new DecompressionStream("gzip");
  const writer = ds.writable.getWriter();
  writer.write(bytes);
  writer.close();
  const buffer = await new Response(ds.readable).arrayBuffer();
  return decoder.decode(buffer);
}

function base64UrlEncode(strOrBytes) {
  const bytes =
    typeof strOrBytes === "string" ? encoder.encode(strOrBytes) : strOrBytes;
  return bytesToBase64(bytes)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64UrlDecodeToBytes(b64url) {
  let b64 = b64url.replace(/-/g, "+").replace(/_/g, "/");
  while (b64.length % 4 !== 0) {
    b64 += "=";
  }
  return base64ToBytes(b64);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hashPasswordPBKDF2(password, saltB64) {
  const salt = base64ToBytes(saltB64);
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    { name: "PBKDF2" },
    false,
    ["deriveBits"]
  );
  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt,
      iterations: 100000,
      hash: "SHA-256",
    },
    keyMaterial,
    256
  );
  return bytesToBase64(new Uint8Array(derivedBits));
}

function getMasterSecret(env) {
  return (
    env.MASTER_SECRET ||
    env.JWT_SECRET ||
    "openmoney-cloudflare-default-master-key-change-in-dashboard-v1"
  );
}

async function signJwt(payload, env) {
  const secret = getMasterSecret(env);
  const header = { alg: "HS256", typ: "JWT" };
  const nowSec = Math.floor(Date.now() / 1000);
  const fullPayload = {
    ...payload,
    iat: nowSec,
    exp: nowSec + 60 * 60 * 24 * 30, // 30 dias
  };
  const signingInput = `${base64UrlEncode(
    JSON.stringify(header)
  )}.${base64UrlEncode(JSON.stringify(fullPayload))}`;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(signingInput)
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
}

async function verifyJwt(token, env) {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const [h, p, s] = parts;
    const signingInput = `${h}.${p}`;
    const secret = getMasterSecret(env);
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"]
    );
    const sigBytes = base64UrlDecodeToBytes(s);
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      sigBytes,
      encoder.encode(signingInput)
    );
    if (!valid) return null;
    const payload = JSON.parse(decoder.decode(base64UrlDecodeToBytes(p)));
    const nowSec = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < nowSec) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

// Deriva uma chave AES-256-GCM exclusiva para o user_id usando HKDF-SHA256
async function deriveUserAesKey(userId, env) {
  const master = getMasterSecret(env);
  const baseKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(master),
    "HKDF",
    false,
    ["deriveKey"]
  );
  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: encoder.encode(`openmoney-salt-${userId}`),
      info: encoder.encode("openmoney-user-db-aes256gcm-v1"),
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
}

async function encryptUserPayload(plainText, userId, env) {
  const key = await deriveUserAesKey(userId, env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  // Comprime com Gzip antes de cifrar: reduz 1MB para ~50KB, acelerando a criptografia e economizando CPU/D1
  const compressedBytes = await compressGzip(plainText);
  const cipherBuffer = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    compressedBytes
  );
  return `enc:v2:${bytesToBase64(iv)}:${bytesToBase64(
    new Uint8Array(cipherBuffer)
  )}`;
}

async function decryptUserPayload(storedText, userId, env) {
  if (!storedText) {
    return storedText;
  }

  // Formato v2: AES-256-GCM com compressão Gzip
  if (storedText.startsWith("enc:v2:")) {
    const parts = storedText.split(":");
    if (parts.length !== 4) {
      throw new Error("Invalid encrypted payload format v2");
    }
    const iv = base64ToBytes(parts[2]);
    const cipherBytes = base64ToBytes(parts[3]);
    const key = await deriveUserAesKey(userId, env);
    const plainBuffer = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      cipherBytes
    );
    return await decompressGzip(new Uint8Array(plainBuffer));
  }

  // Formato v1 legado (sem gzip)
  if (storedText.startsWith("enc:v1:")) {
    const parts = storedText.split(":");
    if (parts.length !== 4) {
      throw new Error("Invalid encrypted payload format v1");
    }
    const iv = base64ToBytes(parts[2]);
    const cipherBytes = base64ToBytes(parts[3]);
    const key = await deriveUserAesKey(userId, env);
    const plainBuffer = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      cipherBytes
    );
    return decoder.decode(plainBuffer);
  }

  return storedText;
}

function defaultOpenMoneyV7Payload() {
  return {
    v: 7,
    accounts: [
      {
        id: "a1",
        name: "Conta Corrente",
        type: "Corrente",
        opening: 0,
      },
    ],
    cats: [
      { name: "Alimentação:Supermercado", type: "D" },
      { name: "Alimentação:Restaurante", type: "D" },
      { name: "Moradia:Aluguel/Condomínio", type: "D" },
      { name: "Moradia:Energia/Água/Internet", type: "D" },
      { name: "Transporte:Combustível", type: "D" },
      { name: "Saúde:Farmácia/Médico", type: "D" },
      { name: "Lazer:Assinaturas/Viagens", type: "D" },
      { name: "Salário:Proventos", type: "R" },
      { name: "Investimentos:Rendimentos", type: "R" },
    ],
    txs: [],
    recs: [],
    budgets: {},
  };
}

async function authenticateRequest(request, env) {
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return null;
  const token = auth.slice(7).trim();
  if (!token) return null;
  return verifyJwt(token, env);
}

export async function onRequest(context) {
  const { request, env } = context;
  const origin = request.headers.get("Origin") || "*";

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  try {
    if (!env.DB) {
      return jsonResponse(
        {
          error:
            "Banco Cloudflare D1 (binding 'DB') ainda não vinculado no projeto Cloudflare Pages.",
        },
        503,
        origin
      );
    }

    try {
      await ensureSchema(env.DB);
    } catch (e) {
      return jsonResponse(
        { error: `Erro ao inicializar schema D1: ${e.message}` },
        500,
        origin
      );
    }

  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");

  // ==========================================================================
  // 1. POST /api/auth/register
  // ==========================================================================
  if (path === "/api/auth/register" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return jsonResponse({ error: "JSON inválido." }, 400, origin);
    }

    const email = String(body.email || "")
      .trim()
      .toLowerCase();
    const name = String(body.name || "").trim();
    const password = String(body.password || "");
    const inviteCode = String(body.inviteCode || "").trim();

    const requiredInvite = String(env.INVITE_CODE || "").trim();
    if (requiredInvite && inviteCode !== requiredInvite) {
      return jsonResponse(
        { error: "Código de convite inválido ou não autorizado." },
        403,
        origin
      );
    }

    if (!email || !email.includes("@")) {
      return jsonResponse({ error: "E-mail inválido." }, 400, origin);
    }
    if (password.length < 8) {
      return jsonResponse(
        { error: "A senha deve ter no mínimo 8 caracteres." },
        400,
        origin
      );
    }

    // Limite preventivo de segurança para manter folga no plano gratuito (padrão 60 usuários)
    const maxUsers = Number(env.MAX_USERS || 60);
    const countRow = await env.DB.prepare(
      "SELECT COUNT(*) as total FROM users"
    ).first();
    if (countRow && Number(countRow.total) >= maxUsers) {
      return jsonResponse(
        {
          error: `Limite máximo de usuários atingido (${maxUsers}). Contate o administrador.`,
        },
        403,
        origin
      );
    }

    const existing = await env.DB.prepare(
      "SELECT id FROM users WHERE email = ?1"
    )
      .bind(email)
      .first();
    if (existing) {
      return jsonResponse(
        { error: "Este endereço de e-mail já está cadastrado." },
        409,
        origin
      );
    }

    const userId = crypto.randomUUID();
    const saltBytes = crypto.getRandomValues(new Uint8Array(16));
    const saltB64 = bytesToBase64(saltBytes);
    const passwordHash = await hashPasswordPBKDF2(password, saltB64);
    const nowIso = new Date().toISOString();

    const initialObj =
      body.initialPayload && typeof body.initialPayload === "object"
        ? body.initialPayload
        : defaultOpenMoneyV7Payload();
    const encryptedPayload = await encryptUserPayload(
      JSON.stringify(initialObj),
      userId,
      env
    );

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO users (id, email, name, password_hash, password_salt, failed_attempts, created_at, last_login_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?6)`
      ).bind(userId, email, name, passwordHash, saltB64, nowIso),
      env.DB.prepare(
        `INSERT INTO user_databases (user_id, schema_version, revision, payload, preferences, updated_at)
         VALUES (?1, 7, 1, ?2, '{}', ?3)`
      ).bind(userId, encryptedPayload, nowIso),
    ]);

    const token = await signJwt({ sub: userId, email, name }, env);
    return jsonResponse(
      {
        token,
        revision: 1,
        user: { id: userId, email, name },
      },
      201,
      origin
    );
  }

  // ==========================================================================
  // 2. POST /api/auth/login
  // ==========================================================================
  if (path === "/api/auth/login" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return jsonResponse({ error: "JSON inválido." }, 400, origin);
    }

    const email = String(body.email || "")
      .trim()
      .toLowerCase();
    const password = String(body.password || "");

    const user = await env.DB.prepare(
      "SELECT id, email, name, password_hash, password_salt, failed_attempts, locked_until FROM users WHERE email = ?1"
    )
      .bind(email)
      .first();

    if (!user) {
      return jsonResponse(
        { error: "E-mail ou senha incorretos." },
        401,
        origin
      );
    }

    if (user.locked_until) {
      const lockDate = new Date(user.locked_until);
      if (lockDate > new Date()) {
        return jsonResponse(
          {
            error:
              "Conta temporariamente bloqueada por excesso de tentativas. Tente novamente em 15 minutos.",
          },
          429,
          origin
        );
      }
    }

    const computedHash = await hashPasswordPBKDF2(password, user.password_salt);
    if (!timingSafeEqual(computedHash, user.password_hash)) {
      const attempts = Number(user.failed_attempts || 0) + 1;
      const lockedUntil =
          attempts >= 5
            ? new Date(Date.now() + 15 * 60 * 1000).toISOString()
            : null;
      await env.DB.prepare(
        "UPDATE users SET failed_attempts = ?1, locked_until = ?2 WHERE id = ?3"
      )
        .bind(attempts, lockedUntil, user.id)
        .run();
      return jsonResponse(
        { error: "E-mail ou senha incorretos." },
        401,
        origin
      );
    }

    const nowIso = new Date().toISOString();
    await env.DB.prepare(
      "UPDATE users SET failed_attempts = 0, locked_until = NULL, last_login_at = ?1 WHERE id = ?2"
    )
      .bind(nowIso, user.id)
      .run();

    const dbRow = await env.DB.prepare(
      "SELECT revision FROM user_databases WHERE user_id = ?1"
    )
      .bind(user.id)
      .first();

    const token = await signJwt(
      { sub: user.id, email: user.email, name: user.name },
      env
    );

    return jsonResponse(
      {
        token,
        revision: dbRow ? Number(dbRow.revision) : 1,
        user: { id: user.id, email: user.email, name: user.name },
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // Todas as rotas abaixo exigem Token JWT válido (Isolamento por user_id)
  // ==========================================================================
  const claims = await authenticateRequest(request, env);
  if (!claims || !claims.sub) {
    return jsonResponse(
      { error: "Sessão expirada ou não autenticada." },
      401,
      origin
    );
  }
  const userId = String(claims.sub);

  // ==========================================================================
  // 3. POST /api/auth/change-password
  // ==========================================================================
  if (path === "/api/auth/change-password" && request.method === "POST") {
    const body = await request.json();
    const currentPassword = String(body.currentPassword || "");
    const newPassword = String(body.newPassword || "");

    if (newPassword.length < 8) {
      return jsonResponse(
        { error: "A nova senha deve ter pelo menos 8 caracteres." },
        400,
        origin
      );
    }

    const user = await env.DB.prepare(
      "SELECT password_hash, password_salt FROM users WHERE id = ?1"
    )
      .bind(userId)
      .first();
    if (!user) {
      return jsonResponse({ error: "Usuário não encontrado." }, 404, origin);
    }

    const currentHash = await hashPasswordPBKDF2(
      currentPassword,
      user.password_salt
    );
    if (!timingSafeEqual(currentHash, user.password_hash)) {
      return jsonResponse({ error: "A senha atual está incorreta." }, 401, origin);
    }

    const newSalt = bytesToBase64(crypto.getRandomValues(new Uint8Array(16)));
    const newHash = await hashPasswordPBKDF2(newPassword, newSalt);

    await env.DB.prepare(
      "UPDATE users SET password_hash = ?1, password_salt = ?2 WHERE id = ?3"
    )
      .bind(newHash, newSalt, userId)
      .run();

    return jsonResponse({ ok: true }, 200, origin);
  }

  // ==========================================================================
  // 4. GET /api/db (Leitura isolada e descriptografada do openmoney.json)
  // ==========================================================================
  if (path === "/api/db" && request.method === "GET") {
    const row = await env.DB.prepare(
      "SELECT schema_version, revision, payload, preferences, updated_at FROM user_databases WHERE user_id = ?1"
    )
      .bind(userId)
      .first();

    if (!row) {
      const initial = defaultOpenMoneyV7Payload();
      return jsonResponse(
        {
          schemaVersion: 7,
          revision: 1,
          payload: initial,
          preferences: {},
          updatedAt: new Date().toISOString(),
        },
        200,
        origin
      );
    }

    const decryptedStr = await decryptUserPayload(row.payload, userId, env);
    let parsedPayload = {};
    try {
      parsedPayload = JSON.parse(decryptedStr);
    } catch (_) {
      parsedPayload = defaultOpenMoneyV7Payload();
    }

    let parsedPrefs = {};
    try {
      parsedPrefs = JSON.parse(row.preferences || "{}");
    } catch (_) {}

    return jsonResponse(
      {
        schemaVersion: Number(row.schema_version || 7),
        revision: Number(row.revision || 1),
        payload: parsedPayload,
        preferences: parsedPrefs,
        updatedAt: row.updated_at,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 5. PUT /api/db (Gravação criptografada AES-256-GCM + Backup Diário Automático)
  // ==========================================================================
  if (path === "/api/db" && request.method === "PUT") {
    const body = await request.json();
    const payloadObj = body.payload;
    const prefsObj = body.preferences || {};

    if (!payloadObj || typeof payloadObj !== "object") {
      return jsonResponse(
        { error: "Payload openmoney.json inválido." },
        400,
        origin
      );
    }

    const current = await env.DB.prepare(
      "SELECT revision FROM user_databases WHERE user_id = ?1"
    )
      .bind(userId)
      .first();

    const currentRev = current ? Number(current.revision || 1) : 0;
    const nextRev = currentRev + 1;
    const nowIso = new Date().toISOString();
    const todayDate = nowIso.slice(0, 10); // YYYY-MM-DD

    const plainJsonStr = JSON.stringify(payloadObj);
    const sizeBytes = encoder.encode(plainJsonStr).byteLength;
    const encryptedPayload = await encryptUserPayload(
      plainJsonStr,
      userId,
      env
    );
    const prefsStr = JSON.stringify(prefsObj);

    await env.DB.prepare(
      `INSERT INTO user_databases (user_id, schema_version, revision, payload, preferences, updated_at)
       VALUES (?1, 7, ?2, ?3, ?4, ?5)
       ON CONFLICT(user_id) DO UPDATE SET
         schema_version = 7,
         revision = excluded.revision,
         payload = excluded.payload,
         preferences = excluded.preferences,
         updated_at = excluded.updated_at`
    )
      .bind(userId, nextRev, encryptedPayload, prefsStr, nowIso)
      .run();

    // Garante 1 snapshot diário na nuvem por usuário e retém os últimos 15 dias (não bloqueia resposta em caso de falha)
    const backupId = `${userId}_${todayDate}`;
    try {
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO user_database_backups (id, user_id, backup_date, revision, size_bytes, payload, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
           ON CONFLICT(user_id, backup_date) DO UPDATE SET
             revision = excluded.revision,
             size_bytes = excluded.size_bytes,
             payload = excluded.payload,
             created_at = excluded.created_at`
        ).bind(
          backupId,
          userId,
          todayDate,
          nextRev,
          sizeBytes,
          encryptedPayload,
          nowIso
        ),
        env.DB.prepare(
          `DELETE FROM user_database_backups
           WHERE user_id = ?1 AND backup_date < date('now', '-15 days')`
        ).bind(userId),
      ]);
    } catch (bErr) {
      console.warn("Falha não-bloqueante ao registrar snapshot diário:", bErr);
    }

    return jsonResponse(
      {
        ok: true,
        revision: nextRev,
        updatedAt: nowIso,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 6. GET /api/backups (Lista os snapshots diários do próprio usuário)
  // ==========================================================================
  if (path === "/api/backups" && request.method === "GET") {
    const res = await env.DB.prepare(
      `SELECT id, backup_date, revision, size_bytes, created_at
       FROM user_database_backups
       WHERE user_id = ?1
       ORDER BY backup_date DESC
       LIMIT 15`
    )
      .bind(userId)
      .all();

    return jsonResponse(
      { backups: (res && res.results) || [] },
      200,
      origin
    );
  }

  // ==========================================================================
  // 7. POST /api/backups/restore (Restaura um backup diário do próprio usuário)
  // ==========================================================================
  if (path === "/api/backups/restore" && request.method === "POST") {
    const body = await request.json();
    const backupId = String(body.backupId || "");

    const backupRow = await env.DB.prepare(
      `SELECT payload FROM user_database_backups WHERE id = ?1 AND user_id = ?2`
    )
      .bind(backupId, userId)
      .first();

    if (!backupRow) {
      return jsonResponse(
        { error: "Backup não encontrado para este usuário." },
        404,
        origin
      );
    }

    const current = await env.DB.prepare(
      "SELECT revision FROM user_databases WHERE user_id = ?1"
    )
      .bind(userId)
      .first();
    const nextRev = (current ? Number(current.revision || 1) : 1) + 1;
    const nowIso = new Date().toISOString();

    await env.DB.prepare(
      `UPDATE user_databases SET revision = ?1, payload = ?2, updated_at = ?3 WHERE user_id = ?4`
    )
      .bind(nextRev, backupRow.payload, nowIso, userId)
      .run();

    const decryptedStr = await decryptUserPayload(
      backupRow.payload,
      userId,
      env
    );
    return jsonResponse(
      {
        ok: true,
        revision: nextRev,
        payload: JSON.parse(decryptedStr),
      },
      200,
      origin
    );
  }

    return jsonResponse({ error: "Rota não encontrada." }, 404, origin);
  } catch (err) {
    console.error("Erro interno no Pages Function:", err);
    return jsonResponse(
      {
        error: `Erro interno no servidor: ${
          err && err.message ? err.message : String(err)
        }`,
      },
      500,
      origin
    );
  }
}
