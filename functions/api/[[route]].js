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
      CREATE TABLE IF NOT EXISTS user_database_chunks (
        user_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        chunk_data TEXT NOT NULL,
        PRIMARY KEY (user_id, chunk_index)
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
    db.prepare(`
      CREATE TABLE IF NOT EXISTS password_reset_tokens (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        email TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        used INTEGER NOT NULL DEFAULT 0
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS email_verification_tokens (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        email TEXT NOT NULL,
        type TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        pending_payload TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        used INTEGER NOT NULL DEFAULT 0
      )
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS idx_email_verification_tokens
      ON email_verification_tokens (email, type, used)
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_sync_meta (
        user_id TEXT PRIMARY KEY,
        seq INTEGER NOT NULL DEFAULT 1,
        base_seq INTEGER NOT NULL DEFAULT 1,
        snapshot_seq INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_sync_records (
        user_id TEXT NOT NULL,
        coll TEXT NOT NULL,
        record_id TEXT NOT NULL,
        encrypted_data TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        seq INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, coll, record_id)
      )
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS idx_user_sync_records_seq
      ON user_sync_records (user_id, seq)
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_sync_ops (
        user_id TEXT NOT NULL,
        op_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (user_id, op_id)
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_audit_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        target_id TEXT,
        summary TEXT NOT NULL,
        details TEXT,
        created_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS idx_audit_user_created
      ON user_audit_logs (user_id, created_at DESC)
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_ai_usage (
        user_id TEXT NOT NULL,
        usage_date TEXT NOT NULL,
        request_count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, usage_date)
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_api_tokens (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        token_hash TEXT NOT NULL,
        token_prefix TEXT NOT NULL,
        permissions TEXT NOT NULL DEFAULT 'read_write',
        last_used_at TEXT,
        created_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS idx_api_tokens_hash
      ON user_api_tokens (token_hash)
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS idx_api_tokens_user
      ON user_api_tokens (user_id)
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS oauth_codes (
        code TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        client_id TEXT NOT NULL,
        redirect_uri TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'read_write',
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS idx_oauth_codes_expires
      ON oauth_codes (expires_at)
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS mcp_debug_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        method TEXT NOT NULL,
        path TEXT NOT NULL,
        status INTEGER NOT NULL,
        user_agent TEXT,
        note TEXT
      )
    `),
  ]);
  try {
    await db.prepare("ALTER TABLE password_reset_tokens ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0").run();
  } catch (_) {}
  try {
    await db.prepare("ALTER TABLE email_verification_tokens ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0").run();
  } catch (_) {}
  schemaInitialized = true;
}

function isAllowedOrigin(origin) {
  if (!origin) return false;
  if (
    origin === "https://openmoney.app.br" ||
    origin === "https://www.openmoney.app.br"
  ) {
    return true;
  }
  if (
    /^https:\/\/[a-z0-9-]+\.openmoney-new\.pages\.dev$/.test(origin) ||
    /^https:\/\/[a-z0-9-]+\.openmoney\.pages\.dev$/.test(origin) ||
    origin === "https://openmoney-new.pages.dev" ||
    origin === "https://openmoney.pages.dev"
  ) {
    return true;
  }
  if (
    /^http:\/\/localhost(:\d+)?$/.test(origin) ||
    /^http:\/\/127\.0\.0\.1(:\d+)?$/.test(origin)
  ) {
    return true;
  }
  return false;
}

function corsHeaders(origin, allowAll = false) {
  let allowed = "https://openmoney.app.br";
  if (allowAll) {
    allowed = origin || "*";
  } else if (isAllowedOrigin(origin)) {
    allowed = origin;
  }
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers":
      "Content-Type, Authorization, MCP-Protocol-Version, Mcp-Session-Id, Accept, X-OpenMoney-Compression, X-OpenMoney-Raw-Size, X-OpenMoney-Prefs, X-OpenMoney-Base-Revision, X-OpenMoney-Force, X-OpenMoney-Compact-Seq, X-OpenMoney-Tz-Offset, X-OpenMoney-AI-Key, X-OpenMoney-AI-Provider",
    "Access-Control-Expose-Headers":
      "Content-Type, WWW-Authenticate, MCP-Protocol-Version, Mcp-Session-Id, X-OpenMoney-Compression, X-OpenMoney-Revision, X-OpenMoney-Sync-Seq, X-OpenMoney-Snapshot-Seq, X-OpenMoney-Updated-At, X-OpenMoney-Prefs, X-OpenMoney-Self-Healed",
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
}

function jsonResponse(data, status = 200, origin = "*", allowAll = false) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders(origin, allowAll),
  });
}

function bytesToBase64(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (typeof u8.toBase64 === "function") {
    return u8.toBase64();
  }
  const CHUNK_SIZE = 0x8000; // 32768
  let binary = "";
  const len = u8.byteLength;
  for (let i = 0; i < len; i += CHUNK_SIZE) {
    const chunk = u8.subarray(i, Math.min(i + CHUNK_SIZE, len));
    binary += String.fromCharCode.apply(null, chunk);
  }
  return btoa(binary);
}

function base64ToBytes(b64) {
  if (typeof Uint8Array.fromBase64 === "function") {
    return Uint8Array.fromBase64(b64);
  }
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

async function sha256Hex(str) {
  const buf = await crypto.subtle.digest("SHA-256", encoder.encode(str));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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
  const secret = (env && (env.MASTER_SECRET || env.JWT_SECRET)) || "";
  if (!secret || typeof secret !== "string" || secret.trim().length === 0) {
    throw new Error(
      "Configuração de segurança pendente: variável MASTER_SECRET não configurada no Cloudflare Pages."
    );
  }
  return secret.trim();
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

function generateSixDigitCode() {
  const array = new Uint32Array(1);
  crypto.getRandomValues(array);
  const code = 100000 + (array[0] % 900000);
  return String(code);
}

async function hashResetCode(code, email, secret) {
  const data = encoder.encode(`${code}:${email.toLowerCase()}:${secret}`);
  const hashBuf = await crypto.subtle.digest("SHA-256", data);
  return bytesToBase64(new Uint8Array(hashBuf));
}

function escapeHtml(str) {
  return String(str || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// Tabela CRC32 pré-calculada para ZIP
const CRC32_TABLE = new Uint32Array(256);
for (let i = 0; i < 256; i++) {
  let c = i;
  for (let j = 0; j < 8; j++) {
    c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  }
  CRC32_TABLE[i] = c;
}

function calculateCrc32(bytes) {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    crc = CRC32_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function createSingleFileZip(filename, fileBytes) {
  const nameBytes = encoder.encode(filename);
  const crc = calculateCrc32(fileBytes);
  const size = fileBytes.length;

  const now = new Date();
  const dosTime = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
  const dosDate = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();

  const localHeader = new Uint8Array(30 + nameBytes.length);
  const lv = new DataView(localHeader.buffer);
  lv.setUint32(0, 0x04034b50, true);
  lv.setUint16(4, 20, true);
  lv.setUint16(6, 0, true);
  lv.setUint16(8, 0, true);
  lv.setUint16(10, dosTime, true);
  lv.setUint16(12, dosDate, true);
  lv.setUint32(14, crc, true);
  lv.setUint32(18, size, true);
  lv.setUint32(22, size, true);
  lv.setUint16(26, nameBytes.length, true);
  lv.setUint16(28, 0, true);
  localHeader.set(nameBytes, 30);

  const cdHeader = new Uint8Array(46 + nameBytes.length);
  const cv = new DataView(cdHeader.buffer);
  cv.setUint32(0, 0x02014b50, true);
  cv.setUint16(4, 20, true);
  cv.setUint16(6, 20, true);
  cv.setUint16(8, 0, true);
  cv.setUint16(10, 0, true);
  cv.setUint16(12, dosTime, true);
  cv.setUint16(14, dosDate, true);
  cv.setUint32(16, crc, true);
  cv.setUint32(20, size, true);
  cv.setUint32(24, size, true);
  cv.setUint16(28, nameBytes.length, true);
  cv.setUint16(30, 0, true);
  cv.setUint16(32, 0, true);
  cv.setUint16(34, 0, true);
  cv.setUint16(36, 0, true);
  cv.setUint32(38, 0, true);
  cv.setUint32(42, 0, true);
  cdHeader.set(nameBytes, 46);

  const eocd = new Uint8Array(22);
  const ev = new DataView(eocd.buffer);
  ev.setUint32(0, 0x06054b50, true);
  ev.setUint16(4, 0, true);
  ev.setUint16(6, 0, true);
  ev.setUint16(8, 1, true);
  ev.setUint16(10, 1, true);
  ev.setUint32(12, cdHeader.length, true);
  ev.setUint32(16, localHeader.length + size, true);
  ev.setUint16(20, 0, true);

  const totalZipLen = localHeader.length + size + cdHeader.length + eocd.length;
  const zip = new Uint8Array(totalZipLen);
  let offset = 0;
  zip.set(localHeader, offset); offset += localHeader.length;
  zip.set(fileBytes, offset); offset += size;
  zip.set(cdHeader, offset); offset += cdHeader.length;
  zip.set(eocd, offset);
  return zip;
}

async function sendResendEmail({ env, to, subject, htmlText, attachments }) {
  const apiKey = (env.RESEND_API_KEY || "").trim();
  if (!apiKey) {
    throw new Error(
      "Serviço de e-mail não configurado no servidor. Configure a variável RESEND_API_KEY no painel da Cloudflare."
    );
  }
  const from =
    (env.RESEND_FROM_EMAIL || "").trim() ||
    "OpenMoney <seguranca@openmoney.app.br>";

  const emailPayload = {
    from,
    to: [to],
    subject,
    html: htmlText,
  };
  if (Array.isArray(attachments) && attachments.length > 0) {
    emailPayload.attachments = attachments;
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(emailPayload),
  });

  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    const msg = errData?.message || res.statusText || `HTTP ${res.status}`;
    throw new Error(`Falha no envio via Resend: ${msg}`);
  }

  return await res.json().catch(() => ({}));
}

function buildRegistrationEmailHtml({ code, email, name }) {
  const greeting = name ? `Olá, <strong>${escapeHtml(name)}</strong>!` : `Olá!`;
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Confirmação de Cadastro - OpenMoney</title>
</head>
<body style="margin:0;padding:24px;background-color:#0b1120;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f8fafc;">
  <table width="100%" border="0" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table width="100%" style="max-width:520px;background-color:#1e293b;border-radius:14px;border:1px solid #334155;padding:32px 28px;text-align:left;" border="0" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <h1 style="margin:0;font-size:22px;color:#38bdf8;font-weight:800;letter-spacing:-0.5px;">OpenMoney Cloud</h1>
              <p style="margin:4px 0 0;font-size:12px;color:#94a3b8;">Sincronização & Gestão Financeira Segura</p>
            </td>
          </tr>
          <tr>
            <td style="font-size:14px;line-height:1.6;color:#cbd5e1;">
              <p style="margin:0 0 14px;">${greeting}</p>
              <p style="margin:0 0 14px;">Para concluir a criação da sua conta com o e-mail <strong>${escapeHtml(email)}</strong>, informe o código de verificação abaixo no aplicativo:</p>
              <div style="background-color:#0f172a;border:1px solid #38bdf8;border-radius:10px;padding:18px;text-align:center;margin-bottom:20px;">
                <span style="font-size:32px;font-weight:800;letter-spacing:8px;color:#38bdf8;font-family:monospace;">${code}</span>
              </div>
              <p style="margin:0 0 10px;font-size:13px;color:#94a3b8;">⏱️ Este código expira em <strong>15 minutos</strong>.</p>
              <p style="margin:0;font-size:12.5px;color:#64748b;">Se você não solicitou este cadastro, nenhuma conta foi criada e você pode ignorar esta mensagem.</p>
            </td>
          </tr>
          <tr>
            <td style="padding-top:24px;border-top:1px solid #334155;font-size:11.5px;color:#64748b;text-align:center;">
              OpenMoney • Criptografia AES-256-GCM + PBKDF2 • openmoney.app.br
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function buildChangeEmailHtml({ code, currentEmail, newEmail, name }) {
  const greeting = name ? `Olá, <strong>${escapeHtml(name)}</strong>!` : `Olá!`;
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Confirmação de Novo E-mail - OpenMoney</title>
</head>
<body style="margin:0;padding:24px;background-color:#0b1120;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f8fafc;">
  <table width="100%" border="0" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table width="100%" style="max-width:520px;background-color:#1e293b;border-radius:14px;border:1px solid #334155;padding:32px 28px;text-align:left;" border="0" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <h1 style="margin:0;font-size:22px;color:#38bdf8;font-weight:800;letter-spacing:-0.5px;">OpenMoney Cloud</h1>
              <p style="margin:4px 0 0;font-size:12px;color:#94a3b8;">Sincronização & Gestão Financeira Segura</p>
            </td>
          </tr>
          <tr>
            <td style="font-size:14px;line-height:1.6;color:#cbd5e1;">
              <p style="margin:0 0 14px;">${greeting}</p>
              <p style="margin:0 0 14px;">Recebemos uma solicitação para alterar o e-mail da sua conta de <strong>${escapeHtml(currentEmail)}</strong> para <strong>${escapeHtml(newEmail)}</strong>.</p>
              <p style="margin:0 0 20px;">Utilize o código de verificação abaixo no aplicativo para confirmar o novo endereço:</p>
              <div style="background-color:#0f172a;border:1px solid #38bdf8;border-radius:10px;padding:18px;text-align:center;margin-bottom:20px;">
                <span style="font-size:32px;font-weight:800;letter-spacing:8px;color:#38bdf8;font-family:monospace;">${code}</span>
              </div>
              <p style="margin:0 0 10px;font-size:13px;color:#94a3b8;">⏱️ Este código expira em <strong>15 minutos</strong>.</p>
              <p style="margin:0;font-size:12.5px;color:#64748b;">Se você não solicitou esta alteração, recomendamos alterar a senha da sua conta imediatamente.</p>
            </td>
          </tr>
          <tr>
            <td style="padding-top:24px;border-top:1px solid #334155;font-size:11.5px;color:#64748b;text-align:center;">
              OpenMoney • Criptografia AES-256-GCM + PBKDF2 • openmoney.app.br
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function buildAccountDeletionEmailHtml({ name, email, mode, hasBackupAttachment }) {
  const greeting = name ? `Olá, <strong>${escapeHtml(name)}</strong>!` : `Olá!`;
  const isFullAccount = mode === "full_account";
  const title = isFullAccount ? "Exclusão Definitiva da Conta" : "Exclusão da Base de Dados na Nuvem";
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>${title} - OpenMoney</title>
</head>
<body style="margin:0;padding:24px;background-color:#0b1120;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f8fafc;">
  <table width="100%" border="0" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table width="100%" style="max-width:520px;background-color:#1e293b;border-radius:14px;border:1px solid #e11d48;padding:32px 28px;text-align:left;" border="0" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <h1 style="margin:0;font-size:22px;color:#fb7185;font-weight:800;letter-spacing:-0.5px;">OpenMoney Cloud</h1>
              <p style="margin:4px 0 0;font-size:12px;color:#94a3b8;">Confirmação de Exclusão de Dados</p>
            </td>
          </tr>
          <tr>
            <td style="font-size:14px;line-height:1.6;color:#cbd5e1;">
              <p style="margin:0 0 14px;">${greeting}</p>
              <p style="margin:0 0 14px;">Confirmamos que a seguinte ação irreversível foi concluída para a conta <strong>${escapeHtml(email)}</strong>:</p>
              <div style="background-color:#4c0519;border:1px solid #f43f5e;border-radius:10px;padding:14px;margin-bottom:18px;color:#ffe4e6;font-weight:600;font-size:13.5px;">
                ⚠️ ${isFullAccount ? "Exclusão definitiva e permanente da conta, login, base e todos os backups da nuvem." : "Exclusão permanente de todos os lançamentos e backups da nuvem (conta reiniciada com base limpa)."}
              </div>
              ${hasBackupAttachment ? `
              <p style="margin:0 0 12px;"><strong>Cópia de Segurança em Anexo:</strong></p>
              <p style="margin:0 0 12px;">Para sua total proteção e para que você não perca seu histórico financeiro, anexamos a este e-mail o arquivo compactado <strong>openmoney-backup-pre-exclusao.zip</strong> contendo toda a sua base em formato <code>openmoney.json</code> imediatamente antes da exclusão.</p>
              <p style="margin:0 0 14px;font-size:12px;color:#94a3b8;">Você pode descompactar e abrir esse arquivo localmente no aplicativo OpenMoney sempre que desejar.</p>
              ` : `
              <p style="margin:0 0 14px;font-size:12px;color:#94a3b8;">Não havia dados armazenados para anexar cópia de segurança.</p>
              `}
              <p style="margin:18px 0 0;font-size:11px;color:#64748b;">Ação solicitada pelo usuário e confirmada via aplicativo OpenMoney.</p>
            </td>
          </tr>
          <tr>
            <td style="padding-top:24px;border-top:1px solid #334155;font-size:11.5px;color:#64748b;text-align:center;">
              OpenMoney • Segurança e Privacidade Financeira • openmoney.app.br
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function buildPasswordResetEmailHtml({ code, email, name }) {
  const greeting = name ? `Olá, <strong>${escapeHtml(name)}</strong>!` : `Olá!`;
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Recuperação de Senha - OpenMoney</title>
</head>
<body style="margin:0;padding:24px;background-color:#0b1120;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f8fafc;">
  <table width="100%" border="0" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table width="100%" style="max-width:520px;background-color:#1e293b;border-radius:14px;border:1px solid #334155;padding:32px 28px;text-align:left;" border="0" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <h1 style="margin:0;font-size:22px;color:#38bdf8;font-weight:800;letter-spacing:-0.5px;">OpenMoney Cloud</h1>
              <p style="margin:4px 0 0;font-size:12px;color:#94a3b8;">Sincronização & Gestão Financeira Segura</p>
            </td>
          </tr>
          <tr>
            <td style="font-size:14px;line-height:1.6;color:#cbd5e1;">
              <p style="margin:0 0 14px;">${greeting}</p>
              <p style="margin:0 0 14px;">Recebemos uma solicitação para redefinir a senha da sua conta <strong>${escapeHtml(email)}</strong>.</p>
              <p style="margin:0 0 20px;">Utilize o código de verificação abaixo no aplicativo para criar sua nova senha:</p>
              <div style="background-color:#0f172a;border:1px solid #38bdf8;border-radius:10px;padding:18px;text-align:center;margin-bottom:20px;">
                <span style="font-size:32px;font-weight:800;letter-spacing:8px;color:#38bdf8;font-family:monospace;">${code}</span>
              </div>
              <p style="margin:0 0 10px;font-size:13px;color:#94a3b8;">⏱️ Este código expira em <strong>15 minutos</strong>.</p>
              <p style="margin:0;font-size:12.5px;color:#64748b;">Se você não solicitou a recuperação, nenhuma alteração foi realizada e você pode ignorar este e-mail com segurança.</p>
            </td>
          </tr>
          <tr>
            <td style="padding-top:24px;border-top:1px solid #334155;font-size:11.5px;color:#64748b;text-align:center;">
              OpenMoney • Criptografia AES-256-GCM + PBKDF2 • openmoney.app.br
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
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

async function encryptCompressedBytes(compressedBytes, userId, env) {
  const key = await deriveUserAesKey(userId, env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipherBuffer = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    compressedBytes
  );
  return `enc:v2:${bytesToBase64(iv)}:${bytesToBase64(
    new Uint8Array(cipherBuffer)
  )}`;
}

async function encryptUserPayload(plainText, userId, env) {
  const compressedBytes = await compressGzip(plainText);
  return encryptCompressedBytes(compressedBytes, userId, env);
}

// Descriptografa e retorna diretamente os bytes Gzip (0ms de CPU de descompressão/JSON no Worker)
async function decryptUserPayloadToGzipBytes(storedText, userId, env) {
  if (!storedText) {
    return compressGzip(JSON.stringify(defaultOpenMoneyV7Payload()));
  }
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
    return new Uint8Array(plainBuffer);
  }
  const plainStr = await decryptUserPayload(storedText, userId, env);
  return compressGzip(plainStr);
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

const MAX_D1_CHUNK_CHARS = 380000; // ~380 KB por query SQL (limite D1 = 1 MB)

function parseChunkRange(rawPayload) {
  if (!rawPayload || typeof rawPayload !== "string") return null;
  if (rawPayload.startsWith("chunked:v3:")) {
    const parts = rawPayload.split(":");
    const batchSlot = Number(parts[2] || 0);
    const count = Number(parts[3] || 0);
    if (batchSlot > 0 && count > 0) {
      return { start: batchSlot, end: batchSlot + count };
    }
  } else if (rawPayload.startsWith("chunked:v2:")) {
    const parts = rawPayload.split(":");
    const count = Number(parts[2] || 0);
    if (count > 0) {
      return { start: 0, end: count };
    }
  }
  return null;
}

async function cleanupOrphanedChunksForUser(db, userId) {
  try {
    const ranges = [];
    const mainRow = await db
      .prepare(`SELECT payload FROM user_databases WHERE user_id = ?1`)
      .bind(userId)
      .first();
    if (mainRow && mainRow.payload) {
      const r = parseChunkRange(mainRow.payload);
      if (r) ranges.push(r);
    }

    const backupRows = await db
      .prepare(`SELECT payload FROM user_database_backups WHERE user_id = ?1`)
      .bind(userId)
      .all();
    for (const b of (backupRows && backupRows.results) || []) {
      const r = parseChunkRange(b.payload);
      if (r) ranges.push(r);
    }

    const chunkRows = await db
      .prepare(`SELECT chunk_index FROM user_database_chunks WHERE user_id = ?1`)
      .bind(userId)
      .all();
    const allChunks = (chunkRows && chunkRows.results) || [];
    const toDelete = [];
    for (const c of allChunks) {
      const idx = Number(c.chunk_index);
      const isReferenced = ranges.some((r) => idx >= r.start && idx < r.end);
      if (!isReferenced) {
        toDelete.push(idx);
      }
    }

    const BATCH_SIZE = 50;
    for (let i = 0; i < toDelete.length; i += BATCH_SIZE) {
      const slice = toDelete.slice(i, i + BATCH_SIZE);
      await db.batch(
        slice.map((idx) =>
          db
            .prepare(
              `DELETE FROM user_database_chunks WHERE user_id = ?1 AND chunk_index = ?2`
            )
            .bind(userId, idx)
        )
      );
    }
  } catch (e) {
    console.warn("Aviso ao limpar chunks órfãos:", e);
  }
}

const MAX_DAILY_AUTO_BACKUPS = 4;
const MIN_BACKUP_INTERVAL_MINUTES = 180;
const MIN_PERIOD_CHANGE_INTERVAL_MINUTES = 30;
const CLOUD_BACKUP_RETENTION_DAYS = 15;
const CLOUD_BACKUP_MIN_KEEP = 28;

function extractTzOffsetMinutes(request, url) {
  const raw =
    (url && url.searchParams ? url.searchParams.get("tzOffset") : null) ??
    (request && request.headers ? request.headers.get("X-OpenMoney-Tz-Offset") : null);
  if (raw !== null && raw !== undefined && raw !== "") {
    const parsed = parseInt(String(raw), 10);
    if (!Number.isNaN(parsed) && parsed >= -720 && parsed <= 840) {
      return parsed;
    }
  }
  return -180; // Padrão América/São Paulo (UTC-3)
}

function formatClientLocalTime(nowIso, tzOffsetMinutes = -180) {
  const offsetMin = Number.isFinite(Number(tzOffsetMinutes))
    ? Math.max(-720, Math.min(840, Number(tzOffsetMinutes)))
    : -180;
  const parsedMs = nowIso ? Date.parse(nowIso) : Date.now();
  const utcMs = Number.isFinite(parsedMs) ? parsedMs : Date.now();
  const localDate = new Date(utcMs + offsetMin * 60000);

  const year = String(localDate.getUTCFullYear()).padStart(4, "0");
  const month = String(localDate.getUTCMonth() + 1).padStart(2, "0");
  const day = String(localDate.getUTCDate()).padStart(2, "0");
  const hourNum = localDate.getUTCHours();
  const hour = String(hourNum).padStart(2, "0");
  const minute = String(localDate.getUTCMinutes()).padStart(2, "0");
  const secStr = String(localDate.getUTCSeconds()).padStart(2, "0");

  const dateStr = `${year}-${month}-${day}`;
  const timeStr = `${hour}:${minute}`;
  return {
    utcMs,
    dateStr,
    timeStr,
    secStr,
    label: `${dateStr} ${timeStr}`,
    hour: hourNum,
    period: Math.floor(hourNum / 6),
  };
}

function parseBackupLocalPeriod(backupRow, tzOffsetMinutes = -180) {
  if (backupRow && backupRow.created_at) {
    const parsed = Date.parse(backupRow.created_at);
    if (Number.isFinite(parsed)) {
      return formatClientLocalTime(backupRow.created_at, tzOffsetMinutes).period;
    }
  }
  const bDate = String((backupRow && backupRow.backup_date) || "");
  const m = bDate.match(/^\d{4}-\d{2}-\d{2}\s+(\d{2}):(\d{2})/);
  if (m) {
    const h = parseInt(m[1], 10);
    if (!Number.isNaN(h)) return Math.floor(h / 6);
  }
  return 0;
}

async function pruneOldCloudBackups(db, userId) {
  try {
    const cutoffIso = new Date(
      Date.now() - CLOUD_BACKUP_RETENTION_DAYS * 86400 * 1000
    ).toISOString();
    await db
      .prepare(
        `DELETE FROM user_database_backups
         WHERE user_id = ?1
           AND created_at < ?2
           AND id NOT IN (
             SELECT id FROM user_database_backups
             WHERE user_id = ?1
             ORDER BY created_at DESC, backup_date DESC
             LIMIT ?3
           )`
      )
      .bind(userId, cutoffIso, CLOUD_BACKUP_MIN_KEEP)
      .run();
  } catch (_) {}
}

async function ensurePeriodicCloudBackup(
  db,
  {
    userId,
    revision,
    encryptedPayloadOrMarker,
    sizeBytes,
    nowIso,
    tzOffsetMinutes = -180,
    forceNew = false,
    isCompaction = false,
    skipAntiWipe = false,
  }
) {
  if (!userId || !encryptedPayloadOrMarker) return false;

  const localNow = formatClientLocalTime(nowIso, tzOffsetMinutes);
  const dateStr = localNow.dateStr;

  try {
    const todayRes = await db
      .prepare(
        `SELECT id, backup_date, revision, size_bytes, created_at
         FROM user_database_backups
         WHERE user_id = ?1 AND backup_date LIKE ?2
         ORDER BY created_at DESC, backup_date DESC`
      )
      .bind(userId, `${dateStr}%`)
      .all();

    const todayBackups = (todayRes && todayRes.results) || [];

    const lastAny = await db
      .prepare(
        `SELECT size_bytes FROM user_database_backups
         WHERE user_id = ?1
         ORDER BY created_at DESC, backup_date DESC
         LIMIT 1`
      )
      .bind(userId)
      .first();

    if (
      !skipAntiWipe &&
      lastAny &&
      Number(lastAny.size_bytes || 0) >= 2000 &&
      sizeBytes < Number(lastAny.size_bytes) / 2
    ) {
      return false;
    }

    if (todayBackups.length > 0) {
      const latest = todayBackups[0];
      const latestSize = Number(latest.size_bytes || 0);
      const latestCreatedMs = Date.parse(latest.created_at || "");
      const elapsedSec = Number.isFinite(latestCreatedMs)
        ? Math.max(0, (localNow.utcMs - latestCreatedMs) / 1000)
        : 999999;

      if (
        !skipAntiWipe &&
        latestSize >= 2000 &&
        sizeBytes < latestSize / 2
      ) {
        return false;
      }

      const shouldUpgradeEmpty = latestSize < 2000 && sizeBytes >= 2000;
      const shouldUpdateFreshCompaction =
        isCompaction &&
        elapsedSec < 60 &&
        Number(revision || 0) > Number(latest.revision || 0);

      if (!forceNew && (shouldUpgradeEmpty || shouldUpdateFreshCompaction)) {
        await db
          .prepare(
            `UPDATE user_database_backups
             SET revision = ?1, size_bytes = ?2, payload = ?3, created_at = ?4
             WHERE id = ?5 AND user_id = ?6`
          )
          .bind(
            revision,
            sizeBytes,
            encryptedPayloadOrMarker,
            nowIso,
            latest.id,
            userId
          )
          .run();
        return true;
      }

      if (!forceNew) {
        if (todayBackups.length >= MAX_DAILY_AUTO_BACKUPS) {
          return false;
        }
        const elapsedMinutes = elapsedSec / 60;
        const latestPeriod = parseBackupLocalPeriod(latest, tzOffsetMinutes);
        const periodChanged = localNow.period !== latestPeriod;
        if (
          elapsedMinutes < MIN_BACKUP_INTERVAL_MINUTES &&
          !(periodChanged && elapsedMinutes >= MIN_PERIOD_CHANGE_INTERVAL_MINUTES)
        ) {
          return false;
        }
      }
    }

    const existingIds = new Set(todayBackups.map((b) => String(b.id || "")));
    let slotIdx = 1;
    while (existingIds.has(`${userId}_${dateStr}_${slotIdx}`)) {
      slotIdx++;
    }
    const backupId = `${userId}_${dateStr}_${slotIdx}`;

    const existingDates = new Set(
      todayBackups.map((b) => String(b.backup_date || ""))
    );
    let backupDateLabel = localNow.label;
    if (existingDates.has(backupDateLabel)) {
      backupDateLabel = `${localNow.label}:${localNow.secStr}`;
      if (existingDates.has(backupDateLabel)) {
        backupDateLabel = `${localNow.label}:${localNow.secStr}_${slotIdx}`;
      }
    }

    await db
      .prepare(
        `INSERT INTO user_database_backups (id, user_id, backup_date, revision, size_bytes, payload, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`
      )
      .bind(
        backupId,
        userId,
        backupDateLabel,
        revision,
        sizeBytes,
        encryptedPayloadOrMarker,
        nowIso
      )
      .run();

    await pruneOldCloudBackups(db, userId);
    return true;
  } catch (_) {
    return false;
  }
}

async function ensurePeriodicCloudBackupFromCurrentDb(
  db,
  userId,
  nowIso,
  tzOffsetMinutes = -180
) {
  if (!db || !userId) return false;
  try {
    const row = await db
      .prepare(
        `SELECT revision, payload FROM user_databases WHERE user_id = ?1`
      )
      .bind(userId)
      .first();
    if (!row || !row.payload) return false;

    const meta = await ensureUserSyncMeta(db, userId);
    const rev = Math.max(Number(row.revision || 1), Number(meta.snapshotSeq || 1));

    // Tenta reutilizar o size_bytes exato se este mesmo payload já tiver sido salvo em backup
    const matchedBackup = await db
      .prepare(
        `SELECT size_bytes FROM user_database_backups
         WHERE user_id = ?1 AND payload = ?2
         LIMIT 1`
      )
      .bind(userId, row.payload)
      .first();

    let sizeBytes = matchedBackup ? Number(matchedBackup.size_bytes || 0) : 0;
    const isChunked =
      typeof row.payload === "string" && row.payload.startsWith("chunked:");
    if (sizeBytes <= 0) {
      if (isChunked) {
        const r = parseChunkRange(row.payload);
        if (r) {
          const sumRow = await db
            .prepare(
              `SELECT COALESCE(SUM(LENGTH(chunk_data)), 0) AS total
               FROM user_database_chunks
               WHERE user_id = ?1 AND chunk_index >= ?2 AND chunk_index < ?3`
            )
            .bind(userId, r.start, r.end)
            .first();
          sizeBytes = Number((sumRow && sumRow.total) || 0);
        }
      } else {
        sizeBytes = String(row.payload).length;
      }
    }

    const created = await ensurePeriodicCloudBackup(db, {
      userId,
      revision: rev,
      encryptedPayloadOrMarker: row.payload,
      sizeBytes,
      nowIso,
      tzOffsetMinutes,
      skipAntiWipe: isChunked,
    });
    if (created) {
      await cleanupOrphanedChunksForUser(db, userId);
    }
    return created;
  } catch (_) {
    return false;
  }
}

async function saveEncryptedPayloadToD1(
  db,
  userId,
  nextRev,
  encryptedPayload,
  prefsStr,
  nowIso,
  tzOffsetMinutes,
  sizeBytes,
  isCompaction = false
) {
  if (encryptedPayload.length <= MAX_D1_CHUNK_CHARS) {
    await db
      .prepare(
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

    await ensurePeriodicCloudBackup(db, {
      userId,
      revision: nextRev,
      encryptedPayloadOrMarker: encryptedPayload,
      sizeBytes,
      nowIso,
      tzOffsetMinutes,
      isCompaction,
    });

    await cleanupOrphanedChunksForUser(db, userId);
  } else {
    // Copy-On-Write (MVCC): usa um batchSlot exclusivo por gravação para que uploads
    // simultâneos ou interrompidos JAMAIS misturem blocos de IVs AES-GCM diferentes!
    const chunks = [];
    for (let i = 0; i < encryptedPayload.length; i += MAX_D1_CHUNK_CHARS) {
      chunks.push(encryptedPayload.slice(i, i + MAX_D1_CHUNK_CHARS));
    }

    const batchSlot =
      (Math.floor(Math.random() * 899999) + 100000) * 100; // ex: 54321000

    for (let idx = 0; idx < chunks.length; idx++) {
      await db
        .prepare(
          `INSERT INTO user_database_chunks (user_id, chunk_index, chunk_data)
           VALUES (?1, ?2, ?3)
           ON CONFLICT(user_id, chunk_index) DO UPDATE SET
             chunk_data = excluded.chunk_data`
        )
        .bind(userId, batchSlot + idx, chunks[idx])
        .run();
    }

    const marker = `chunked:v3:${batchSlot}:${chunks.length}`;
    await db
      .prepare(
        `INSERT INTO user_databases (user_id, schema_version, revision, payload, preferences, updated_at)
         VALUES (?1, 7, ?2, ?3, ?4, ?5)
         ON CONFLICT(user_id) DO UPDATE SET
           schema_version = 7,
           revision = excluded.revision,
           payload = excluded.payload,
           preferences = excluded.preferences,
           updated_at = excluded.updated_at`
      )
      .bind(userId, nextRev, marker, prefsStr, nowIso)
      .run();

    await ensurePeriodicCloudBackup(db, {
      userId,
      revision: nextRev,
      encryptedPayloadOrMarker: marker,
      sizeBytes,
      nowIso,
      tzOffsetMinutes,
      isCompaction,
    });

    // Limpa apenas blocos antigos que não são referenciados nem por user_databases nem por user_database_backups
    await cleanupOrphanedChunksForUser(db, userId);
  }
}

async function loadEncryptedPayloadFromD1(db, userId, rawPayloadField) {
  if (!rawPayloadField) {
    return rawPayloadField;
  }
  if (rawPayloadField.startsWith("chunked:v3:")) {
    const partsMeta = rawPayloadField.split(":");
    const batchSlot = Number(partsMeta[2] || 0);
    const totalChunks = Number(partsMeta[3] || 0);
    const parts = [];
    for (let idx = 0; idx < totalChunks; idx++) {
      const cRow = await db
        .prepare(
          `SELECT chunk_data FROM user_database_chunks WHERE user_id = ?1 AND chunk_index = ?2`
        )
        .bind(userId, batchSlot + idx)
        .first();
      if (!cRow || !cRow.chunk_data) {
        throw new Error(
          `Bloco v3 ${idx + 1}/${totalChunks} não localizado no D1.`
        );
      }
      parts.push(cRow.chunk_data);
    }
    return parts.join("");
  }
  if (rawPayloadField.startsWith("chunked:v2:")) {
    const totalChunks = Number(rawPayloadField.split(":")[2] || 0);
    const parts = [];
    for (let idx = 0; idx < totalChunks; idx++) {
      const cRow = await db
        .prepare(
          `SELECT chunk_data FROM user_database_chunks WHERE user_id = ?1 AND chunk_index = ?2`
        )
        .bind(userId, idx)
        .first();
      if (!cRow || !cRow.chunk_data) {
        throw new Error(
          `Bloco v2 ${idx + 1}/${totalChunks} não localizado no D1.`
        );
      }
      parts.push(cRow.chunk_data);
    }
    return parts.join("");
  }
  return rawPayloadField;
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
      { name: "Alimentação", parent: null, type: "Despesa" },
      { name: "Bares e Restaurantes", parent: "Alimentação", type: "Despesa" },
      { name: "Mercado", parent: "Alimentação", type: "Despesa" },
      { name: "Assinaturas e Serviços", parent: null, type: "Despesa" },
      { name: "Apple", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Games", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Google", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "IA", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Microsoft", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Nintendo", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Sites e Domínios", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Streaming", parent: "Assinaturas e Serviços", type: "Despesa" },
      { name: "Casa", parent: null, type: "Despesa" },
      { name: "Água, Esgoto", parent: "Casa", type: "Despesa" },
      { name: "Condomínio", parent: "Casa", type: "Despesa" },
      { name: "Despesas da casa", parent: "Casa", type: "Despesa" },
      { name: "Eletricidade", parent: "Casa", type: "Despesa" },
      { name: "Gás", parent: "Casa", type: "Despesa" },
      { name: "Internet", parent: "Casa", type: "Despesa" },
      { name: "IPTU", parent: "Casa", type: "Despesa" },
      { name: "Telefonia", parent: "Casa", type: "Despesa" },
      { name: "TV", parent: "Casa", type: "Despesa" },
      { name: "Compras", parent: null, type: "Despesa" },
      { name: "Automóveis", parent: "Compras", type: "Despesa" },
      { name: "Eletrodomésticos", parent: "Compras", type: "Despesa" },
      { name: "Eletrônicos e Informática", parent: "Compras", type: "Despesa" },
      { name: "Móveis", parent: "Compras", type: "Despesa" },
      { name: "Músicas & Filmes", parent: "Compras", type: "Despesa" },
      { name: "Softwares", parent: "Compras", type: "Despesa" },
      { name: "Videogames", parent: "Compras", type: "Despesa" },
      { name: "Cuidados pessoais", parent: null, type: "Despesa" },
      { name: "Educação", parent: null, type: "Despesa" },
      { name: "Família", parent: null, type: "Despesa" },
      { name: "Festas", parent: null, type: "Despesa" },
      { name: "Impostos e Taxas", parent: null, type: "Despesa" },
      { name: "Investimentos (D)", parent: null, type: "Despesa" },
      { name: "Lazer e hobbies", parent: null, type: "Despesa" },
      { name: "Academia", parent: "Lazer e hobbies", type: "Despesa" },
      { name: "Cinema, Teatro", parent: "Lazer e hobbies", type: "Despesa" },
      { name: "Diversão", parent: "Lazer e hobbies", type: "Despesa" },
      { name: "Saúde", parent: null, type: "Despesa" },
      { name: "Medicamentos", parent: "Saúde", type: "Despesa" },
      { name: "Médicos", parent: "Saúde", type: "Despesa" },
      { name: "Plano de saúde", parent: "Saúde", type: "Despesa" },
      { name: "Seguro de Vida", parent: "Saúde", type: "Despesa" },
      { name: "Terapeutas", parent: "Saúde", type: "Despesa" },
      { name: "Transporte", parent: null, type: "Despesa" },
      { name: "Combustível", parent: "Transporte", type: "Despesa" },
      { name: "Documentação", parent: "Transporte", type: "Despesa" },
      { name: "Estacionamento, Pedágio", parent: "Transporte", type: "Despesa" },
      { name: "Manutenção, Serviços", parent: "Transporte", type: "Despesa" },
      { name: "Metro, Ônibus, Taxi", parent: "Transporte", type: "Despesa" },
      { name: "Multas", parent: "Transporte", type: "Despesa" },
      { name: "Seguro Auto", parent: "Transporte", type: "Despesa" },
      { name: "Viagem", parent: null, type: "Despesa" },
      { name: "Cashback", parent: null, type: "Receita" },
      { name: "Investimentos (C)", parent: null, type: "Receita" },
      { name: "Renda", parent: null, type: "Receita" },
      { name: "Distribuição de Lucros", parent: "Renda", type: "Receita" },
      { name: "Pró-labore", parent: "Renda", type: "Receita" },
      { name: "Outras Rendas", parent: null, type: "Receita" },
      { name: "Benefícios", parent: "Outras Rendas", type: "Receita" },
      { name: "Devolução de impostos", parent: "Outras Rendas", type: "Receita" },
      { name: "Prestação de Serviços", parent: "Outras Rendas", type: "Receita" },
      { name: "Reembolso", parent: "Outras Rendas", type: "Receita" },
      { name: "Rendimentos", parent: null, type: "Receita" },
      { name: "Vendas", parent: null, type: "Receita" },
      { name: "Automóveis", parent: "Vendas", type: "Receita" },
      { name: "Eletrodomésticos", parent: "Vendas", type: "Receita" },
      { name: "Eletrônicos e Informática", parent: "Vendas", type: "Receita" },
      { name: "Móveis", parent: "Vendas", type: "Receita" },
    ],
    txs: [],
    recs: [],
    budgets: {},
  };
}

async function encryptRecordWithKey(plainJsonStr, aesKey) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipherBuf = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    aesKey,
    encoder.encode(plainJsonStr)
  );
  return `rec:v1:${bytesToBase64(iv)}:${bytesToBase64(
    new Uint8Array(cipherBuf)
  )}`;
}

async function decryptRecordWithKey(storedStr, aesKey) {
  if (!storedStr) return null;
  if (storedStr.startsWith("rec:v1:")) {
    const parts = storedStr.split(":");
    if (parts.length !== 4) return null;
    const iv = base64ToBytes(parts[2]);
    const cipherBytes = base64ToBytes(parts[3]);
    const plainBuf = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      aesKey,
      cipherBytes
    );
    return JSON.parse(decoder.decode(plainBuf));
  }
  return JSON.parse(storedStr);
}

function catIdOf(c) {
  if (typeof c === "string") return c;
  if (!c || typeof c !== "object") return "";
  const p = c.parent ? String(c.parent).trim() : "";
  const n = c.name ? String(c.name).trim() : "";
  return p ? `${p} › ${n}` : n;
}

function applySyncChangesToSnapshot(payloadObj, prefsObj, changes) {
  if (!payloadObj || typeof payloadObj !== "object") return;
  if (!Array.isArray(changes) || changes.length === 0) return;

  if (!Array.isArray(payloadObj.accounts)) payloadObj.accounts = [];
  if (!Array.isArray(payloadObj.cats)) payloadObj.cats = [];
  if (!Array.isArray(payloadObj.txs)) payloadObj.txs = [];
  if (!Array.isArray(payloadObj.recs)) payloadObj.recs = [];
  if (!payloadObj.budgets || typeof payloadObj.budgets !== "object") {
    payloadObj.budgets = {};
  }
  if (!payloadObj.comments || typeof payloadObj.comments !== "object") {
    payloadObj.comments = {};
  }

  let accMap = null;
  let catMap = null;
  let txMap = null;
  let recMap = null;
  let pendingAccountOrder = null;

  for (const ch of changes) {
    if (!ch || !ch.coll || ch.id === undefined || ch.id === null) continue;
    const coll = String(ch.coll);
    const id = String(ch.id);
    const isDel = Boolean(ch.deleted) || ch.data === null || ch.data === undefined;

    if (coll === "txs") {
      if (!txMap) {
        txMap = new Map();
        for (const t of payloadObj.txs) {
          if (t && t.id !== undefined) txMap.set(String(t.id), t);
        }
      }
      if (isDel) {
        txMap.delete(id);
      } else {
        txMap.set(id, ch.data);
      }
    } else if (coll === "accounts") {
      if (!accMap) {
        accMap = new Map();
        for (const a of payloadObj.accounts) {
          if (a && a.id !== undefined) accMap.set(String(a.id), a);
        }
      }
      if (isDel) {
        accMap.delete(id);
      } else {
        accMap.set(id, ch.data);
      }
    } else if (coll === "cats") {
      if (!catMap) {
        catMap = new Map();
        for (const c of payloadObj.cats) {
          const cid = catIdOf(c);
          if (cid) catMap.set(cid, c);
        }
      }
      if (isDel) {
        catMap.delete(id);
      } else {
        catMap.set(id, ch.data);
      }
    } else if (coll === "recs") {
      if (!recMap) {
        recMap = new Map();
        for (const r of payloadObj.recs) {
          if (r && r.id !== undefined) recMap.set(String(r.id), r);
        }
      }
      if (isDel) {
        recMap.delete(id);
      } else {
        recMap.set(id, ch.data);
      }
    } else if (coll === "budgets") {
      if (isDel) {
        delete payloadObj.budgets[id];
      } else {
        payloadObj.budgets[id] = Number(ch.data) || 0;
      }
    } else if (coll === "comments") {
      if (isDel) {
        delete payloadObj.comments[id];
      } else {
        payloadObj.comments[id] = String(ch.data);
      }
    } else if (coll === "meta") {
      if (id === "predMode" && !isDel) {
        payloadObj.predMode = ch.data === "invoice" ? "invoice" : "month";
      } else if (id === "accountOrder" && Array.isArray(ch.data)) {
        pendingAccountOrder = ch.data.map((x) => String(x));
      }
    } else if (coll === "prefs") {
      if (id === "userPrefs" && ch.data && typeof ch.data === "object") {
        Object.assign(prefsObj, ch.data);
      }
    }
  }

  if (txMap) payloadObj.txs = Array.from(txMap.values());
  if (accMap) payloadObj.accounts = Array.from(accMap.values());
  if (catMap) payloadObj.cats = Array.from(catMap.values());
  if (recMap) payloadObj.recs = Array.from(recMap.values());

  if (pendingAccountOrder && Array.isArray(payloadObj.accounts)) {
    const byId = new Map();
    for (const a of payloadObj.accounts) {
      if (a && a.id !== undefined) byId.set(String(a.id), a);
    }
    const ordered = [];
    for (const aid of pendingAccountOrder) {
      if (byId.has(aid)) {
        ordered.push(byId.get(aid));
        byId.delete(aid);
      }
    }
    for (const rem of byId.values()) {
      ordered.push(rem);
    }
    payloadObj.accounts = ordered;
  }
}

async function ensureUserSyncMeta(db, userId) {
  let meta = await db
    .prepare(
      `SELECT seq, base_seq, snapshot_seq, updated_at FROM user_sync_meta WHERE user_id = ?1`
    )
    .bind(userId)
    .first();
  if (meta) {
    return {
      seq: Number(meta.seq || 1),
      baseSeq: Number(meta.base_seq || 1),
      snapshotSeq: Number(meta.snapshot_seq || 1),
      updatedAt: String(meta.updated_at || new Date().toISOString()),
    };
  }
  const dbRow = await db
    .prepare(`SELECT revision, updated_at FROM user_databases WHERE user_id = ?1`)
    .bind(userId)
    .first();
  const initialSeq = dbRow ? Math.max(1, Number(dbRow.revision || 1)) : 1;
  const nowIso = dbRow?.updated_at || new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO user_sync_meta (user_id, seq, base_seq, snapshot_seq, updated_at)
       VALUES (?1, ?2, ?2, ?2, ?3)
       ON CONFLICT(user_id) DO NOTHING`
    )
    .bind(userId, initialSeq, nowIso)
    .run();
  return {
    seq: initialSeq,
    baseSeq: initialSeq,
    snapshotSeq: initialSeq,
    updatedAt: nowIso,
  };
}

async function loadDecryptedSyncChangesSince(db, userId, sinceSeq, aesKey) {
  const res = await db
    .prepare(
      `SELECT coll, record_id, encrypted_data, deleted, seq, updated_at
       FROM user_sync_records
       WHERE user_id = ?1 AND seq > ?2
       ORDER BY seq ASC`
    )
    .bind(userId, sinceSeq)
    .all();
  const rows = (res && res.results) || [];
  const changes = [];
  for (const r of rows) {
    const isDel = Number(r.deleted || 0) === 1 || !r.encrypted_data;
    let data = null;
    if (!isDel) {
      try {
        data = await decryptRecordWithKey(r.encrypted_data, aesKey);
      } catch (_) {
        continue;
      }
    }
    changes.push({
      coll: String(r.coll),
      id: String(r.record_id),
      data: isDel ? null : data,
      deleted: isDel,
      seq: Number(r.seq || 0),
    });
  }
  return changes;
}

async function notifyDurableObjectSync(env, userId, payload) {
  if (!env.SYNC) return;
  try {
    const id = env.SYNC.idFromName(userId);
    const stub = env.SYNC.get(id);
    await stub.fetch("https://sync.internal/notify", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-OpenMoney-User-Id": userId,
      },
      body: JSON.stringify(payload),
    });
  } catch (_) {}
}

function formatCurrencyCents(cents, currency = "BRL") {
  const val = Number(cents || 0) / 100;
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: currency || "BRL",
  }).format(val);
}

function addMonthsIso(dateIso, months) {
  if (!months) return dateIso;
  const parts = String(dateIso || "").split("-");
  if (parts.length < 3) return dateIso;
  let y = parseInt(parts[0], 10);
  let m = parseInt(parts[1], 10);
  let d = parseInt(parts[2], 10);
  m += months;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  const mm = String(m).padStart(2, "0");
  const dd = String(Math.min(d, 28)).padStart(2, "0");
  return `${y}-${mm}-${dd}`;
}

async function loadDecryptedUserDatabase(env, userId) {
  const row = await env.DB.prepare(
    "SELECT schema_version, revision, payload, preferences, updated_at FROM user_databases WHERE user_id = ?1"
  )
    .bind(userId)
    .first();

  if (!row || !row.payload) {
    return {
      db: defaultOpenMoneyV7Payload(),
      revision: 1,
      preferences: {},
      isNew: true,
    };
  }

  const fullEncrypted = await loadEncryptedPayloadFromD1(
    env.DB,
    userId,
    row.payload
  );
  const plainStr = await decryptUserPayload(fullEncrypted, userId, env);
  let parsed;
  try {
    parsed = JSON.parse(plainStr);
  } catch (_) {
    parsed = defaultOpenMoneyV7Payload();
  }
  let prefs = {};
  try {
    prefs = JSON.parse(row.preferences || "{}");
  } catch (_) {}

  // Aplica alterações incrementais em user_sync_records posteriores ao snapshot carregado
  const meta = await ensureUserSyncMeta(env.DB, userId);
  const snapSeq = Math.max(
    Number(row.revision || 1),
    Number(meta.snapshotSeq || 1)
  );
  if (meta.seq > snapSeq) {
    const aesKey = await deriveUserAesKey(userId, env);
    const uncompacted = await loadDecryptedSyncChangesSince(
      env.DB,
      userId,
      snapSeq,
      aesKey
    );
    if (uncompacted.length > 0) {
      applySyncChangesToSnapshot(parsed, prefs, uncompacted);
    }
  }

  return {
    db: parsed,
    revision: Number(meta.seq || row.revision || 1),
    preferences: prefs,
    isNew: false,
  };
}

async function saveDecryptedUserDatabase(
  env,
  userId,
  dbObj,
  prefsObj = {},
  syncChanges = null
) {
  const meta = await ensureUserSyncMeta(env.DB, userId);
  const nextSeq = (meta.seq || 1) + 1;
  const nowIso = new Date().toISOString();
  const plainJsonStr = JSON.stringify(dbObj);
  const sizeBytes = encoder.encode(plainJsonStr).byteLength;
  const encryptedPayload = await encryptUserPayload(plainJsonStr, userId, env);
  const prefsStr = JSON.stringify(prefsObj || {});
  const aesKey = await deriveUserAesKey(userId, env);

  // 1. Grava o snapshot completo criptografado em user_databases
  await saveEncryptedPayloadToD1(
    env.DB,
    userId,
    nextSeq,
    encryptedPayload,
    prefsStr,
    nowIso,
    0,
    sizeBytes,
    false
  );

  // 2. Grava cada delta em user_sync_records para que clientes conectados via Sync v2
  // (WebSocket ou HTTP polling) recebam a alteração imediatamente e integrem em suas memórias locais!
  if (Array.isArray(syncChanges) && syncChanges.length > 0) {
    const stmts = [];
    for (const ch of syncChanges) {
      if (!ch || !ch.coll || ch.id === undefined || ch.id === null) continue;
      const isDel =
        Boolean(ch.deleted) || ch.data === null || ch.data === undefined;
      let encData = null;
      if (!isDel) {
        encData = await encryptRecordWithKey(JSON.stringify(ch.data), aesKey);
      }
      stmts.push(
        env.DB.prepare(
          `INSERT INTO user_sync_records (user_id, coll, record_id, encrypted_data, deleted, seq, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
           ON CONFLICT(user_id, coll, record_id) DO UPDATE SET
             encrypted_data = excluded.encrypted_data,
             deleted = excluded.deleted,
             seq = excluded.seq,
             updated_at = excluded.updated_at`
        ).bind(
          userId,
          String(ch.coll),
          String(ch.id),
          encData,
          isDel ? 1 : 0,
          nextSeq,
          nowIso
        )
      );
    }
    if (stmts.length > 0) {
      await env.DB.batch(stmts);
    }
  }

  // 3. Atualiza user_sync_meta: seq = nextSeq, snapshot_seq = nextSeq
  // Como acabamos de gravar o snapshot completo em user_databases, snapshot_seq avança junto!
  await env.DB.prepare(
    "UPDATE user_sync_meta SET seq = ?1, snapshot_seq = ?1, updated_at = ?2 WHERE user_id = ?3"
  )
    .bind(nextSeq, nowIso, userId)
    .run();

  // 4. Notifica o Durable Object com as alterações reais para broadcast instantâneo via WebSocket
  const broadcastChanges = (syncChanges || []).map((ch) => ({
    coll: String(ch.coll),
    id: String(ch.id),
    data: ch.deleted ? null : ch.data,
    deleted: Boolean(ch.deleted),
    seq: nextSeq,
  }));

  await notifyDurableObjectSync(env, userId, {
    seq: nextSeq,
    reset: false,
    changes: broadcastChanges,
  });

  return nextSeq;
}

const MCP_TOOLS = [
  {
    name: "openmoney_get_financial_overview",
    description:
      "Obtém resumo financeiro consolidado: patrimônio líquido, saldo em contas bancárias e carteiras, status das faturas de cartões de crédito (fechamento, vencimento e total) e totais de receitas, despesas e resultado do mês.",
    inputSchema: {
      type: "object",
      properties: {
        month: {
          type: "string",
          description:
            "Mês no formato YYYY-MM (ex: 2026-11). Se omitido, usa o mês atual.",
        },
      },
    },
  },
  {
    name: "openmoney_list_transactions",
    description:
      "Lista e pesquisa transações no OpenMoney com filtros flexíveis por período, conta, categoria, texto livre ou status de conciliação.",
    inputSchema: {
      type: "object",
      properties: {
        startDate: {
          type: "string",
          description: "Data inicial no formato YYYY-MM-DD",
        },
        endDate: {
          type: "string",
          description: "Data final no formato YYYY-MM-DD",
        },
        accountId: {
          type: "string",
          description: "ID ou nome da conta para filtrar",
        },
        category: {
          type: "string",
          description: "Nome ou caminho da categoria",
        },
        search: {
          type: "string",
          description: "Termo de busca no favorecido (payee) ou notas (memo)",
        },
        onlyUnreconciled: {
          type: "boolean",
          description: "Se true, filtra apenas transações não conciliadas",
        },
        limit: {
          type: "number",
          description:
            "Limite máximo de registros a retornar (padrão: 35, máx: 100)",
        },
      },
    },
  },
  {
    name: "openmoney_get_cashflow_projection",
    description:
      "Calcula a projeção futura de fluxo de caixa mês a mês (contas a pagar e receber, parcelamentos, despesas recorrentes e saldo projetado).",
    inputSchema: {
      type: "object",
      properties: {
        monthsAhead: {
          type: "number",
          description:
            "Quantidade de meses futuros para projetar (1 a 12, padrão: 3)",
        },
      },
    },
  },
  {
    name: "openmoney_create_transaction",
    description:
      "Cria uma nova despesa, receita ou transferência no OpenMoney. Registrado com auditoria [MCP Remoto] nos logs do sistema.",
    inputSchema: {
      type: "object",
      required: ["date", "accountId", "payee", "amountCents"],
      properties: {
        date: {
          type: "string",
          description: "Data da transação no formato YYYY-MM-DD",
        },
        accountId: {
          type: "string",
          description: "ID ou nome da conta de origem/débito",
        },
        payee: {
          type: "string",
          description: "Nome do estabelecimento, favorecido ou descrição",
        },
        category: {
          type: "string",
          description:
            "Categoria da transação (ex: Alimentação › Restaurante)",
        },
        amountCents: {
          type: "number",
          description:
            "Valor em centavos inteiros (negativo para despesa, positivo para receita, ex: -4590 para R$ 45,90)",
        },
        memo: {
          type: "string",
          description: "Observação opcional da transação",
        },
        tags: {
          type: "array",
          items: { type: "string" },
          description:
            'Lista de tags (sem #, ex: ["Viagem", "Trabalho"])',
        },
        toAccountId: {
          type: "string",
          description: "Se for transferência, ID ou nome da conta de destino",
        },
        installments: {
          type: "number",
          description: "Número total de parcelas (padrão 1)",
        },
      },
    },
  },
  {
    name: "openmoney_update_transaction",
    description:
      "Atualiza um lançamento existente pelo ID (alteração de valor, categoria, favorecido, data ou nota). Registrado nos logs de auditoria.",
    inputSchema: {
      type: "object",
      required: ["transactionId"],
      properties: {
        transactionId: {
          type: "string",
          description: "ID da transação a ser editada",
        },
        payee: {
          type: "string",
          description: "Novo favorecido/estabelecimento",
        },
        category: { type: "string", description: "Nova categoria" },
        amountCents: { type: "number", description: "Novo valor em centavos" },
        date: { type: "string", description: "Nova data YYYY-MM-DD" },
        memo: { type: "string", description: "Nova observação" },
        tags: {
          type: "array",
          items: { type: "string" },
          description: "Novas tags",
        },
      },
    },
  },
  {
    name: "openmoney_delete_transaction",
    description:
      "Exclui permanentemente um lançamento no OpenMoney pelo ID com registro no log de auditoria.",
    inputSchema: {
      type: "object",
      required: ["transactionId"],
      properties: {
        transactionId: {
          type: "string",
          description: "ID da transação a ser excluída",
        },
      },
    },
  },
  {
    name: "openmoney_get_budget_status",
    description:
      "Avalia os limites/tetos mensais de gastos configurados por categoria e o quanto já foi consumido no mês.",
    inputSchema: {
      type: "object",
      properties: {
        month: {
          type: "string",
          description: "Mês YYYY-MM (opcional, padrão mês atual)",
        },
      },
    },
  },
];

function addMonthsYMJs(ym, delta) {
  const parts = String(ym || "").split("-");
  const y = Number(parts[0]) || new Date().getUTCFullYear();
  const m = Number(parts[1]) || 1;
  const total = y * 12 + (m - 1) + delta;
  const ny = Math.floor(total / 12);
  const nm = (total % 12) + 1;
  return `${String(ny).padStart(4, "0")}-${String(nm).padStart(2, "0")}`;
}

function invKeyForJs(card, dateStr) {
  const parts = String(dateStr || "").split("-");
  if (parts.length !== 3) {
    return String(dateStr || "").slice(0, 7);
  }
  const y = Number(parts[0]) || new Date().getUTCFullYear();
  const m = Number(parts[1]) || 1;
  const d = Number(parts[2]) || 1;
  const closeDay = Number(card?.closeDay || 1);
  const dueDay = Number(card?.dueDay || 10);
  const k = `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}`;
  const closeMonth = d > closeDay ? addMonthsYMJs(k, 1) : k;
  return dueDay <= closeDay ? addMonthsYMJs(closeMonth, 1) : closeMonth;
}

function computeAccountBalancesJs(db, targetMonth) {
  const allAccounts = Array.isArray(db.accounts) ? db.accounts : [];
  const txs = Array.isArray(db.txs) ? db.txs : [];
  const endOfMonth = `${targetMonth}-31`;

  const realBalances = {};
  const predBalances = {};
  const cardAccounts = {};
  for (const acc of allAccounts) {
    const opening = Number(acc.opening || 0);
    realBalances[acc.id] = opening;
    predBalances[acc.id] = opening;
    if ((acc.type === "Cartão" || acc.card) && acc.card) {
      cardAccounts[acc.id] = acc;
    }
  }

  for (const tx of txs) {
    if (realBalances[tx.acc] === undefined) continue;
    const amt = Number(tx.amt || 0);

    // 1. Saldo Atual / Real (Conciliado): considera APENAS transações conciliadas (tx.rec === true)
    if (tx.rec === true) {
      realBalances[tx.acc] += amt;
    }

    // 2. Saldo Previsto no Mês: considera conciliadas + pendentes até o fim de targetMonth
    const cardAcc = cardAccounts[tx.acc];
    if (cardAcc) {
      if (tx.auto !== true || tx.rec === true) {
        const ik = tx.ik || tx.inv || invKeyForJs(cardAcc.card, tx.date);
        if (ik && ik <= targetMonth) {
          predBalances[tx.acc] += amt;
        }
      }
    } else {
      if (tx.rec === true || (tx.date && tx.date <= endOfMonth)) {
        predBalances[tx.acc] += amt;
      }
    }
  }

  return { realBalances, predBalances, allAccounts, txs };
}

async function executeMcpTool(name, args, userId, permissions, env, tokenId) {
  if (name === "openmoney_get_financial_overview" || name === "openmoney_list_accounts") {
    const { db } = await loadDecryptedUserDatabase(env, userId);
    const brNow = new Date(Date.now() - 3 * 3600 * 1000);
    const defaultMonth = brNow.toISOString().slice(0, 7);
    const targetMonth = (args.month || defaultMonth).trim();

    const { realBalances, predBalances, allAccounts, txs } = computeAccountBalancesJs(
      db,
      targetMonth
    );
    const accounts = allAccounts.filter((a) => !a.inactive);

    let totalRealNetWorth = 0;
    let totalPredNetWorth = 0;
    const accountsSummary = accounts
      .map((a) => {
        const realBal = realBalances[a.id] || 0;
        const predBal = predBalances[a.id] || 0;
        totalRealNetWorth += realBal;
        totalPredNetWorth += predBal;
        const cur = a.currency || db.baseCurrency || "BRL";
        const isCard = a.type === "Cartão" || Boolean(a.card);
        let cardInfo = "";
        if (isCard && a.card) {
          cardInfo = ` [Fechamento: dia ${a.card.closeDay || "?"}, Vencimento: dia ${a.card.dueDay || "?"}]`;
        }
        return `- **${a.name}** (ID: \`${a.id}\`, Tipo: ${a.type || "Conta"}): **Saldo Atual do Dia (Conciliado): ${formatCurrencyCents(realBal, cur)}** | Saldo Previsto no Mês (${targetMonth}, inclui não conciliadas): ${formatCurrencyCents(predBal, cur)}${cardInfo}`;
      })
      .join("\n");

    let monthIncome = 0;
    let monthExpense = 0;
    let monthReconciledIncome = 0;
    let monthReconciledExpense = 0;
    for (const tx of txs) {
      if (
        tx.auto === true ||
        tx.xfer ||
        !tx.date ||
        !tx.date.startsWith(targetMonth)
      ) {
        continue;
      }
      const amt = Number(tx.amt || 0);
      if (amt > 0) {
        monthIncome += amt;
        if (tx.rec === true) monthReconciledIncome += amt;
      }
      if (amt < 0) {
        monthExpense += amt;
        if (tx.rec === true) monthReconciledExpense += amt;
      }
    }
    const monthNet = monthIncome + monthExpense;

    return (
      `### Resumo Financeiro OpenMoney (${targetMonth})\n\n` +
      `> **Nota de Saldo:** Quando o usuário perguntar o **saldo atual / saldo do dia** de uma conta, utilize SEMPRE o **Saldo Atual do Dia (Conciliado)**, que soma apenas o saldo inicial e as transações já conciliadas (\`rec: true\`). O **Saldo Previsto no Mês** inclui também lançamentos pendentes (não conciliados) até o fim de ${targetMonth}.\n\n` +
      `- **Patrimônio Líquido Atual (Conciliado):** ${formatCurrencyCents(totalRealNetWorth, db.baseCurrency || "BRL")}\n` +
      `- **Patrimônio Líquido Previsto no Mês (com pendentes):** ${formatCurrencyCents(totalPredNetWorth, db.baseCurrency || "BRL")}\n\n` +
      `#### Movimentação do Mês (${targetMonth}):\n` +
      `- **Receitas do Mês:** ${formatCurrencyCents(monthIncome, db.baseCurrency || "BRL")} (Conciliadas: ${formatCurrencyCents(monthReconciledIncome, db.baseCurrency || "BRL")})\n` +
      `- **Despesas do Mês:** ${formatCurrencyCents(monthExpense, db.baseCurrency || "BRL")} (Conciliadas: ${formatCurrencyCents(monthReconciledExpense, db.baseCurrency || "BRL")})\n` +
      `- **Resultado do Mês:** ${formatCurrencyCents(monthNet, db.baseCurrency || "BRL")} (${monthNet >= 0 ? "Superávit" : "Déficit"})\n\n` +
      `#### Contas & Cartões Ativos:\n${accountsSummary || "Nenhuma conta cadastrada."}`
    );
  }

  if (name === "openmoney_list_transactions" || name === "openmoney_query_transactions") {
    const { db } = await loadDecryptedUserDatabase(env, userId);
    const txs = Array.isArray(db.txs) ? db.txs : [];
    const accounts = Array.isArray(db.accounts) ? db.accounts : [];
    const accMap = new Map(accounts.map((a) => [a.id, a]));

    let filtered = txs.filter((t) => t.auto !== true);

    if (args.startDate) {
      filtered = filtered.filter((t) => t.date && t.date >= args.startDate);
    }
    if (args.endDate) {
      filtered = filtered.filter((t) => t.date && t.date <= args.endDate);
    }
    if (args.accountId) {
      const targetId = String(args.accountId).toLowerCase();
      filtered = filtered.filter((t) => {
        if (t.acc === args.accountId) return true;
        const a = accMap.get(t.acc);
        return a && a.name.toLowerCase().includes(targetId);
      });
    }
    if (args.category) {
      const cat = String(args.category).toLowerCase();
      filtered = filtered.filter(
        (t) => t.cat && t.cat.toLowerCase().includes(cat)
      );
    }
    if (args.search) {
      const q = String(args.search).toLowerCase();
      filtered = filtered.filter(
        (t) =>
          (t.payee && t.payee.toLowerCase().includes(q)) ||
          (t.memo && t.memo.toLowerCase().includes(q)) ||
          (t.cat && t.cat.toLowerCase().includes(q))
      );
    }
    if (args.onlyUnreconciled) {
      filtered = filtered.filter((t) => !t.rec);
    }

    filtered.sort((a, b) => (b.date || "").localeCompare(a.date || ""));

    const limit = Math.min(Math.max(1, Number(args.limit || 35)), 100);
    const sliced = filtered.slice(0, limit);

    if (sliced.length === 0) {
      return "Nenhuma transação encontrada com os filtros informados.";
    }

    const lines = sliced.map((t) => {
      const acc = accMap.get(t.acc);
      const accName = acc ? acc.name : t.acc;
      const cur = acc?.currency || db.baseCurrency || "BRL";
      const tagsStr =
        Array.isArray(t.tags) && t.tags.length > 0
          ? ` [${t.tags.map((tag) => "#" + tag).join(" ")}]`
          : "";
      const recStr = t.rec ? "✓ Conciliado" : "Pendente";
      const memoStr = t.memo ? ` — "${t.memo}"` : "";
      return `- **${t.date}** | \`${t.id}\` | **${t.payee}** | ${formatCurrencyCents(t.amt, cur)} | ${t.cat} | ${accName}${memoStr}${tagsStr} (${recStr})`;
    });

    return (
      `### Transações Encontradas (${sliced.length} de ${filtered.length}):\n\n` +
      lines.join("\n")
    );
  }

  if (name === "openmoney_get_cashflow_projection") {
    const { db } = await loadDecryptedUserDatabase(env, userId);
    const monthsCount = Math.min(Math.max(1, Number(args.monthsAhead || 3)), 12);
    const now = new Date();
    const currentY = now.getFullYear();
    const currentM = now.getMonth() + 1;

    const targetMonths = [];
    for (let i = 0; i < monthsCount; i++) {
      const d = new Date(Date.UTC(currentY, currentM - 1 + i, 1));
      targetMonths.push(d.toISOString().slice(0, 7));
    }

    const projection = targetMonths.map((m) => {
      let income = 0;
      let expense = 0;
      for (const t of db.txs || []) {
        if (t.auto === true || t.xfer || !t.date || !t.date.startsWith(m)) {
          continue;
        }
        const amt = Number(t.amt || 0);
        if (amt > 0) income += amt;
        if (amt < 0) expense += amt;
      }
      return {
        month: m,
        income,
        expense,
        net: income + expense,
      };
    });

    let report = `### Projeção de Fluxo de Caixa (${monthsCount} meses)\n\n| Mês | Entradas Previstas | Saídas Previstas | Resultado Líquido |\n| :--- | :--- | :--- | :--- |\n`;
    for (const p of projection) {
      report += `| **${p.month}** | ${formatCurrencyCents(p.income, db.baseCurrency || "BRL")} | ${formatCurrencyCents(p.expense, db.baseCurrency || "BRL")} | ${formatCurrencyCents(p.net, db.baseCurrency || "BRL")} |\n`;
    }
    return report;
  }

  if (
    name === "openmoney_create_transaction" ||
    name === "openmoney_add_transaction"
  ) {
    if (permissions === "read_only") {
      throw new Error(
        "Token de acesso possui permissão apenas de leitura (read_only)."
      );
    }
    const { db, preferences } = await loadDecryptedUserDatabase(env, userId);
    const accounts = Array.isArray(db.accounts) ? db.accounts : [];
    const targetAcc =
      accounts.find(
        (a) =>
          a.id === args.accountId ||
          a.name.toLowerCase() === String(args.accountId).toLowerCase()
      ) || accounts[0];
    if (!targetAcc) throw new Error("Conta não encontrada.");

    const isXfer = Boolean(args.toAccountId);
    const toAcc = isXfer
      ? accounts.find(
          (a) =>
            a.id === args.toAccountId ||
            a.name.toLowerCase() === String(args.toAccountId).toLowerCase()
        )
      : null;
    if (isXfer && !toAcc) {
      throw new Error("Conta de destino para transferência não encontrada.");
    }

    const txId =
      "tx_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7);
    const date = (args.date || new Date().toISOString().slice(0, 10)).trim();
    const payee = String(args.payee || "Lançamento").trim();

    // Tratamento robusto de valor: aceita amountCents (centavos) ou amount (em reais)
    let amt = 0;
    if (args.amountCents !== undefined && args.amountCents !== null) {
      amt = Number(args.amountCents);
    } else if (args.amount !== undefined && args.amount !== null) {
      amt = Math.round(Number(args.amount) * 100);
    }

    const typeHint = String(args.type || "").toLowerCase();
    if ((typeHint === "expense" || typeHint === "despesa") && amt > 0) {
      amt = -amt;
    } else if ((typeHint === "income" || typeHint === "receita") && amt < 0) {
      amt = Math.abs(amt);
    }

    const cat = isXfer
      ? `Transferência: ${toAcc.name}`
      : String(args.category || "Outros").trim();
    const memo = String(args.memo || "").trim();
    const tags = Array.isArray(args.tags)
      ? args.tags.map((t) => String(t).trim()).filter(Boolean)
      : null;
    const installments = Math.max(1, Number(args.installments || 1));

    if (!Array.isArray(db.txs)) db.txs = [];
    const syncChanges = [];

    if (isXfer) {
      const xid = "xfer_" + Date.now();
      const absAmt = Math.abs(amt);
      const tx1 = {
        id: txId,
        acc: targetAcc.id,
        date,
        payee: "Transferência",
        cat: `Transferência: ${toAcc.name}`,
        memo,
        amt: -absAmt,
        rec: false,
        xfer: xid,
        peer: toAcc.id,
      };
      const peerId =
        "tx_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7);
      const tx2 = {
        id: peerId,
        acc: toAcc.id,
        date,
        payee: "Transferência",
        cat: `Transferência: ${targetAcc.name}`,
        memo,
        amt: absAmt,
        rec: false,
        xfer: xid,
        peer: targetAcc.id,
      };
      db.txs.push(tx1);
      db.txs.push(tx2);
      syncChanges.push({ coll: "txs", id: tx1.id, data: tx1, deleted: false });
      syncChanges.push({ coll: "txs", id: tx2.id, data: tx2, deleted: false });
    } else if (installments > 1) {
      const planId = "plan_" + Date.now();
      const instAmt = Math.round(amt / installments);
      for (let i = 0; i < installments; i++) {
        const instDate = addMonthsIso(date, i);
        const thisId =
          i === 0
            ? txId
            : "tx_" +
              Date.now() +
              "_" +
              i +
              "_" +
              Math.random().toString(36).slice(2, 6);
        const instTx = {
          id: thisId,
          acc: targetAcc.id,
          date: instDate,
          payee: `${payee} (${i + 1}/${installments})`,
          cat,
          memo,
          amt: instAmt,
          rec: false,
          plan: planId,
          pn: i + 1,
          pt: installments,
          tags: tags ? [...tags] : null,
        };
        db.txs.push(instTx);
        syncChanges.push({
          coll: "txs",
          id: instTx.id,
          data: instTx,
          deleted: false,
        });
      }
    } else {
      const singleTx = {
        id: txId,
        acc: targetAcc.id,
        date,
        payee,
        cat,
        memo,
        amt,
        rec: false,
        tags,
      };
      db.txs.push(singleTx);
      syncChanges.push({
        coll: "txs",
        id: singleTx.id,
        data: singleTx,
        deleted: false,
      });
    }

    await saveDecryptedUserDatabase(
      env,
      userId,
      db,
      preferences,
      syncChanges
    );

    const typeLabel = isXfer
      ? "Transferência"
      : amt < 0
      ? "Despesa"
      : "Receita";
    const formattedAmt = formatCurrencyCents(
      amt,
      targetAcc.currency || db.baseCurrency || "BRL"
    );
    const logDesc =
      installments > 1
        ? `[MCP Remoto] ${typeLabel} parcelado (${installments}x): "${payee}" em ${targetAcc.name}, total: ${formattedAmt}`
        : `[MCP Remoto] ${typeLabel}: "${payee}" em ${targetAcc.name}, ${formattedAmt} (${cat})`;

    await env.DB.prepare(
      `INSERT INTO user_audit_logs (id, user_id, action, entity, target_id, summary, details, created_at)
       VALUES (?1, ?2, 'create', 'transaction', ?3, ?4, ?5, ?6)`
    )
      .bind(
        "log_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7),
        userId,
        txId,
        logDesc,
        JSON.stringify({ source: "mcp_remote", tokenId }),
        new Date().toISOString()
      )
      .run()
      .catch(() => {});

    return `Lançamento criado com sucesso!\n- **ID**: \`${txId}\`\n- **Favorecido**: ${payee}\n- **Valor**: ${formattedAmt}\n- **Conta**: ${targetAcc.name}\n- **Data**: ${date}`;
  }

  if (name === "openmoney_update_transaction") {
    if (permissions === "read_only") {
      throw new Error(
        "Token de acesso possui permissão apenas de leitura (read_only)."
      );
    }
    const { db, preferences } = await loadDecryptedUserDatabase(env, userId);
    const txs = Array.isArray(db.txs) ? db.txs : [];
    const idx = txs.findIndex((t) => t.id === args.transactionId);
    if (idx === -1) {
      throw new Error(
        `Lançamento com ID ${args.transactionId} não encontrado.`
      );
    }

    const t = txs[idx];
    if (args.payee !== undefined) t.payee = String(args.payee).trim();
    if (args.category !== undefined) t.cat = String(args.category).trim();
    if (args.amountCents !== undefined && args.amountCents !== null) {
      t.amt = Number(args.amountCents);
    } else if (args.amount !== undefined && args.amount !== null) {
      t.amt = Math.round(Number(args.amount) * 100);
    }
    if (args.date !== undefined) t.date = String(args.date).trim();
    if (args.memo !== undefined) t.memo = String(args.memo).trim();
    if (Array.isArray(args.tags)) {
      t.tags = args.tags.map((tag) => String(tag).trim()).filter(Boolean);
    }

    const syncChanges = [{ coll: "txs", id: t.id, data: t, deleted: false }];
    await saveDecryptedUserDatabase(
      env,
      userId,
      db,
      preferences,
      syncChanges
    );

    const cur = db.baseCurrency || "BRL";
    const logDesc = `[MCP Remoto] Lançamento alterado: "${t.payee}", ${formatCurrencyCents(t.amt, cur)} (${t.cat})`;
    await env.DB.prepare(
      `INSERT INTO user_audit_logs (id, user_id, action, entity, target_id, summary, details, created_at)
       VALUES (?1, ?2, 'update', 'transaction', ?3, ?4, ?5, ?6)`
    )
      .bind(
        "log_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7),
        userId,
        t.id,
        logDesc,
        JSON.stringify({ source: "mcp_remote", tokenId }),
        new Date().toISOString()
      )
      .run()
      .catch(() => {});

    return `Lançamento atualizado com sucesso!\n- **ID**: \`${t.id}\`\n- **Favorecido**: ${t.payee}\n- **Valor**: ${formatCurrencyCents(t.amt, cur)}\n- **Categoria**: ${t.cat}\n- **Data**: ${t.date}`;
  }

  if (name === "openmoney_delete_transaction") {
    if (permissions === "read_only") {
      throw new Error(
        "Token de acesso possui permissão apenas de leitura (read_only)."
      );
    }
    const { db, preferences } = await loadDecryptedUserDatabase(env, userId);
    const txs = Array.isArray(db.txs) ? db.txs : [];
    const idx = txs.findIndex((t) => t.id === args.transactionId);
    if (idx === -1) {
      throw new Error(
        `Lançamento com ID ${args.transactionId} não encontrado.`
      );
    }

    const t = txs[idx];
    txs.splice(idx, 1);
    const syncChanges = [{ coll: "txs", id: t.id, data: null, deleted: true }];
    if (t.xfer) {
      const peerIdx = txs.findIndex((x) => x.xfer === t.xfer);
      if (peerIdx !== -1) {
        const peer = txs[peerIdx];
        txs.splice(peerIdx, 1);
        syncChanges.push({
          coll: "txs",
          id: peer.id,
          data: null,
          deleted: true,
        });
      }
    }

    await saveDecryptedUserDatabase(
      env,
      userId,
      db,
      preferences,
      syncChanges
    );

    const cur = db.baseCurrency || "BRL";
    const logDesc = `[MCP Remoto] Lançamento excluído: "${t.payee}", ${formatCurrencyCents(t.amt, cur)}`;
    await env.DB.prepare(
      `INSERT INTO user_audit_logs (id, user_id, action, entity, target_id, summary, details, created_at)
       VALUES (?1, ?2, 'delete', 'transaction', ?3, ?4, ?5, ?6)`
    )
      .bind(
        "log_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7),
        userId,
        t.id,
        logDesc,
        JSON.stringify({ source: "mcp_remote", tokenId }),
        new Date().toISOString()
      )
      .run()
      .catch(() => {});

    return `Lançamento \`${t.id}\` ("${t.payee}") excluído com sucesso.`;
  }

  if (name === "openmoney_get_budget_status") {
    const { db } = await loadDecryptedUserDatabase(env, userId);
    const targetMonth = (
      args.month || new Date().toISOString().slice(0, 7)
    ).trim();
    const categories = Array.isArray(db.cats) ? db.cats : [];
    const txs = Array.isArray(db.txs) ? db.txs : [];

    const spentByCat = {};
    for (const t of txs) {
      if (
        t.auto === true ||
        t.xfer ||
        !t.date ||
        !t.date.startsWith(targetMonth) ||
        Number(t.amt || 0) >= 0
      ) {
        continue;
      }
      const c = t.cat || "Outros";
      spentByCat[c] = (spentByCat[c] || 0) + Math.abs(Number(t.amt || 0));
    }

    const budgetItems = categories.filter((c) => Number(c.budget || 0) > 0);
    if (budgetItems.length === 0) {
      return `Nenhum orçamento configurado nas categorias para o mês de ${targetMonth}.`;
    }

    let report = `### Status dos Orçamentos (${targetMonth})\n\n| Categoria | Teto Mensal | Gasto Atual | % Consumido | Saldo Restante |\n| :--- | :--- | :--- | :--- | :--- |\n`;
    for (const b of budgetItems) {
      const budget = Number(b.budget || 0);
      const spent = spentByCat[b.name] || 0;
      const pct = Math.round((spent / budget) * 100);
      const remaining = budget - spent;
      const alert = pct > 100 ? " ⚠️ (Estourado)" : "";
      report += `| **${b.name}** | ${formatCurrencyCents(budget)} | ${formatCurrencyCents(spent)} | ${pct}%${alert} | ${formatCurrencyCents(remaining)} |\n`;
    }
    return report;
  }

  throw new Error(`Ferramenta desconhecida: ${name}`);
}

async function handleJsonRpcRequest(body, auth, env, origin, sessionId = null) {
  if (Array.isArray(body)) {
    const results = [];
    for (const item of body) {
      const res = await handleJsonRpcRequest(item, auth, env, origin, sessionId);
      if (res) results.push(res);
    }
    return results.length > 0 ? results : null;
  }

  if (!body || typeof body !== "object") {
    return {
      jsonrpc: "2.0",
      id: null,
      error: { code: -32700, message: "Parse error" },
    };
  }

  const { id, method, params } = body;

  if (method === "initialize") {
    const requestedVersion = params?.protocolVersion;
    const negotiatedVersion =
      typeof requestedVersion === "string" && /^202\d-\d{2}-\d{2}$/.test(requestedVersion)
        ? requestedVersion
        : "2025-03-26";
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: negotiatedVersion,
        serverInfo: {
          name: "openmoney-cloud",
          version: "2.5.4",
        },
        capabilities: {
          tools: {
            listChanged: false,
          },
        },
      },
    };
  }

  if ((typeof method === "string" && method.startsWith("notifications/")) || id === undefined) {
    return null;
  }

  if (method === "resources/list") {
    return { jsonrpc: "2.0", id, result: { resources: [] } };
  }

  if (method === "resources/templates/list") {
    return { jsonrpc: "2.0", id, result: { resourceTemplates: [] } };
  }

  if (method === "prompts/list") {
    return { jsonrpc: "2.0", id, result: { prompts: [] } };
  }

  if (method === "logging/setLevel") {
    return { jsonrpc: "2.0", id, result: {} };
  }

  if (method === "tools/list") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        tools: MCP_TOOLS,
      },
    };
  }

  if (method === "tools/call") {
    const toolName = params?.name;
    const toolArgs = params?.arguments || {};
    try {
      const textResult = await executeMcpTool(
        toolName,
        toolArgs,
        auth.userId,
        auth.permissions,
        env,
        auth.tokenId
      );
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [
            {
              type: "text",
              text: String(textResult),
            },
          ],
          isError: false,
        },
      };
    } catch (e) {
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [
            {
              type: "text",
              text: `Erro ao executar ${toolName}: ${e && e.message ? e.message : String(e)}`,
            },
          ],
          isError: true,
        },
      };
    }
  }

  if (method === "ping") {
    return {
      jsonrpc: "2.0",
      id,
      result: {},
    };
  }

  return {
    jsonrpc: "2.0",
    id,
    error: {
      code: -32601,
      message: `Método não suportado: ${method}`,
    },
  };
}

async function authenticateRequest(request, env) {
  let token = "";
  const auth = request.headers.get("Authorization") || "";
  if (auth.startsWith("Bearer ")) {
    token = auth.slice(7).trim();
  } else {
    try {
      const url = new URL(request.url);
      token = (url.searchParams.get("token") || "").trim();
    } catch (_) {}
  }
  if (!token) return null;

  // 1. Personal Access Token para MCP / APIs Externas (opm_live_...)
  if (token.startsWith("opm_live_")) {
    try {
      const tokenHash = await sha256Hex(token);
      const row = await env.DB.prepare(
        `SELECT id, user_id, name, permissions FROM user_api_tokens WHERE token_hash = ?1`
      )
        .bind(tokenHash)
        .first();

      if (row) {
        // Atualiza last_used_at sem bloquear
        env.DB.prepare(
          `UPDATE user_api_tokens SET last_used_at = ?1 WHERE id = ?2`
        )
          .bind(new Date().toISOString(), row.id)
          .run()
          .catch(() => {});

        return {
          sub: String(row.user_id),
          isApiToken: true,
          tokenId: row.id,
          tokenName: row.name,
          permissions: row.permissions || "read_write",
        };
      }
    } catch (e) {
      console.error("[authenticateRequest] Erro ao validar token MCP:", e);
    }
    return null;
  }

  // 2. JWT padrão de sessão do usuário no app
  return verifyJwt(token, env);
}

function getOpenApiSpec() {
  return {
    openapi: "3.0.3",
    info: {
      title: "OpenMoney API & AI Actions",
      version: "2.5.3",
      description: "API e Ações de Inteligência Artificial do OpenMoney para ChatGPT Actions, Gemini Extensions, MCP e conectores externos.",
      contact: {
        name: "OpenMoney",
        url: "https://openmoney.app.br",
      },
    },
    servers: [
      {
        url: "https://openmoney.app.br",
        description: "Servidor Oficial de Produção OpenMoney",
      },
    ],
    paths: {
      "/api/v1/tools/get_financial_overview": {
        get: {
          summary: "Obter visão geral e saldos financeiros",
          description: "Retorna o patrimônio líquido total, saldos detalhados de todas as contas e cartões de crédito e o resumo de receitas/despesas do mês.",
          operationId: "getFinancialOverview",
          parameters: [
            {
              name: "month",
              in: "query",
              required: false,
              description: "Mês de referência no formato YYYY-MM (ex: '2026-11'). Se omitido, utiliza o mês atual.",
              schema: { type: "string", example: "2026-11" },
            },
          ],
          responses: {
            "200": {
              description: "Visão financeira detalhada com saldos e resumo",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/list_accounts": {
        get: {
          summary: "Listar contas bancárias e cartões",
          description: "Lista todas as contas financeiras (corrente, poupança, investimento, carteira) e cartões de crédito cadastrados com seus respectivos IDs.",
          operationId: "listAccounts",
          responses: {
            "200": {
              description: "Lista de contas e cartões",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/list_categories": {
        get: {
          summary: "Listar categorias financeiras",
          description: "Lista todas as categorias e subcategorias de despesas e receitas cadastradas.",
          operationId: "listCategories",
          responses: {
            "200": {
              description: "Lista de categorias disponíveis",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/query_transactions": {
        post: {
          summary: "Consultar lançamentos com filtros",
          description: "Pesquisa transações financeiras filtrando por intervalo de datas, conta, categoria ou busca textual na descrição.",
          operationId: "queryTransactions",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    start_date: { type: "string", description: "Data inicial no formato YYYY-MM-DD", example: "2026-11-01" },
                    end_date: { type: "string", description: "Data final no formato YYYY-MM-DD", example: "2026-11-30" },
                    search: { type: "string", description: "Termo de busca textual na descrição do lançamento" },
                    account_id: { type: "string", description: "ID da conta para filtrar lançamentos" },
                    category_id: { type: "string", description: "ID da categoria para filtrar lançamentos" },
                    limit: { type: "integer", description: "Limite de registros retornados (padrão 50)", default: 50 },
                  },
                },
              },
            },
          },
          responses: {
            "200": {
              description: "Lançamentos encontrados",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/create_transaction": {
        post: {
          summary: "Criar novo lançamento financeiro",
          description: "Registra uma nova despesa ou receita no OpenMoney com registro automático no log de auditoria.",
          operationId: "createTransaction",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  required: ["description", "amount", "account_id"],
                  properties: {
                    description: { type: "string", description: "Descrição do lançamento", example: "Almoço Restaurante" },
                    amount: { type: "number", description: "Valor monetário positivo (ex: 45.50)", example: 45.5 },
                    type: { type: "string", enum: ["expense", "income"], default: "expense", description: "Tipo: 'expense' (despesa) ou 'income' (receita)" },
                    account_id: { type: "string", description: "ID da conta ou cartão onde ocorreu o lançamento" },
                    category_id: { type: "string", description: "ID da categoria ou subcategoria (opcional)" },
                    date: { type: "string", description: "Data no formato YYYY-MM-DD. Se omitido, usa a data atual.", example: "2026-11-22" },
                    notes: { type: "string", description: "Observações adicionais (opcional)" },
                  },
                },
              },
            },
          },
          responses: {
            "200": {
              description: "Transação criada com sucesso",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/update_transaction": {
        post: {
          summary: "Editar lançamento existente",
          description: "Atualiza os campos de um lançamento existente com registro no log de auditoria.",
          operationId: "updateTransaction",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  required: ["transaction_id"],
                  properties: {
                    transaction_id: { type: "string", description: "ID único da transação a ser modificada" },
                    description: { type: "string", description: "Nova descrição" },
                    amount: { type: "number", description: "Novo valor monetário positivo" },
                    category_id: { type: "string", description: "Novo ID da categoria" },
                    date: { type: "string", description: "Nova data no formato YYYY-MM-DD" },
                    notes: { type: "string", description: "Novas observações" },
                  },
                },
              },
            },
          },
          responses: {
            "200": {
              description: "Transação atualizada com sucesso",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/delete_transaction": {
        post: {
          summary: "Excluir lançamento financeiro",
          description: "Exclui uma transação existente com registro no log de auditoria.",
          operationId: "deleteTransaction",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  required: ["transaction_id"],
                  properties: {
                    transaction_id: { type: "string", description: "ID único da transação a ser excluída" },
                  },
                },
              },
            },
          },
          responses: {
            "200": {
              description: "Transação excluída com sucesso",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
      "/api/v1/tools/get_credit_card_invoices": {
        get: {
          summary: "Consultar faturas de cartões de crédito",
          description: "Retorna faturas abertas e fechadas de todos os cartões de crédito, com datas de vencimento, fechamento e lançamentos vinculados.",
          operationId: "getCreditCardInvoices",
          parameters: [
            {
              name: "account_id",
              in: "query",
              required: false,
              description: "ID específico do cartão de crédito (opcional)",
              schema: { type: "string" },
            },
            {
              name: "month",
              in: "query",
              required: false,
              description: "Mês da fatura no formato YYYY-MM (opcional)",
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": {
              description: "Informações das faturas",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      ok: { type: "boolean" },
                      result: { type: "string" },
                    },
                  },
                },
              },
            },
          },
          security: [{ OAuth2: ["read_write"] }, { BearerAuth: [] }],
        },
      },
    },
    components: {
      securitySchemes: {
        OAuth2: {
          type: "oauth2",
          description: "Fluxo de Autorização OAuth 2.0 padrão para ChatGPT Actions e Gemini",
          flows: {
            authorizationCode: {
              authorizationUrl: "https://openmoney.app.br/api/oauth/authorize",
              tokenUrl: "https://openmoney.app.br/api/oauth/token",
              scopes: {
                read_write: "Acesso de leitura e escrita às finanças no OpenMoney",
              },
            },
          },
        },
        BearerAuth: {
          type: "http",
          scheme: "bearer",
          bearerFormat: "opm_live_token",
          description: "Token de Acesso Pessoal gerado no OpenMoney (ex: opm_live_...)",
        },
      },
    },
  };
}

export function getOAuthProtectedResourceMetadata(url, resourcePath = "/api/mcp") {
  const cleanPath = resourcePath.startsWith("/") ? resourcePath : `/${resourcePath}`;
  return {
    resource: `${url.origin}${cleanPath}`,
    authorization_servers: [url.origin],
    bearer_methods_supported: ["header"],
    scopes_supported: ["read_write", "read_only", "offline_access"],
    resource_documentation: `${url.origin}`,
  };
}

export function getOAuthAuthorizationServerMetadata(url) {
  return {
    issuer: url.origin,
    authorization_endpoint: `${url.origin}/api/oauth/authorize`,
    token_endpoint: `${url.origin}/api/oauth/token`,
    registration_endpoint: `${url.origin}/api/oauth/register`,
    userinfo_endpoint: `${url.origin}/api/oauth/userinfo`,
    jwks_uri: `${url.origin}/api/oauth/jwks`,
    response_types_supported: ["code"],
    response_modes_supported: ["query"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    subject_types_supported: ["public"],
    id_token_signing_alg_values_supported: ["RS256", "HS256"],
    token_endpoint_auth_methods_supported: [
      "none",
      "client_secret_post",
      "client_secret_basic",
    ],
    code_challenge_methods_supported: ["S256"],
    scopes_supported: ["read_write", "read_only", "offline_access"],
    authorization_response_iss_parameter_supported: true,
    client_id_metadata_document_supported: true,
    service_documentation: `${url.origin}`,
  };
}

export async function logMcpDiagnostic(env, request, path, status, note = "") {
  if (!env || !env.DB) return;
  try {
    const ua = (request.headers.get("User-Agent") || "").slice(0, 180);
    await env.DB.prepare(
      `INSERT INTO mcp_debug_logs (created_at, method, path, status, user_agent, note) VALUES (?1, ?2, ?3, ?4, ?5, ?6)`
    )
      .bind(new Date().toISOString(), request.method, path, status, ua, String(note || "").slice(0, 400))
      .run();
  } catch (_) {}
}

function formatOAuthClientDisplayName(clientId) {
  if (!clientId) return "Assistente de IA";
  const str = String(clientId).trim();
  if (str.startsWith("opm_c_")) {
    try {
      const parts = str.split("_");
      if (parts.length >= 4) {
        const b64 = parts
          .slice(2, parts.length - 1)
          .join("_")
          .replace(/-/g, "+")
          .replace(/_/g, "/");
        const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
        const bytes = Uint8Array.from(atob(b64 + pad), (c) => c.charCodeAt(0));
        const decoded = new TextDecoder().decode(bytes).trim();
        if (decoded) return decoded;
      }
    } catch (_) {}
  }
  if (str.startsWith("https://") || str.startsWith("http://")) {
    try {
      const u = new URL(str);
      if (u.hostname.includes("chatgpt") || u.hostname.includes("openai")) return "ChatGPT";
      if (u.hostname.includes("claude") || u.hostname.includes("anthropic")) return "Claude";
      if (u.hostname.includes("google") || u.hostname.includes("gemini")) return "Gemini";
      return u.hostname;
    } catch (_) {}
  }
  return str;
}

function renderOAuthConsentHtml({
  clientId,
  redirectUri,
  state,
  scope,
  codeChallenge = "",
  codeChallengeMethod = "S256",
  error = "",
  email = "",
}) {
  const rawClient = String(clientId || "ChatGPT / Claude / Gemini");
  const displayClient = formatOAuthClientDisplayName(rawClient);
  const safeClientDisplay = displayClient
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeClientId = rawClient
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeEmail = String(email || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeRedirect = String(redirectUri || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeState = String(state || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeScope = String(scope || "read_write")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeCodeChallenge = String(codeChallenge || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const safeCodeChallengeMethod = String(codeChallengeMethod || "S256")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  const errorBanner = error
    ? `<div style="background: rgba(239, 68, 68, 0.15); border: 1px solid rgba(239, 68, 68, 0.4); color: #fca5a5; padding: 12px 16px; border-radius: 8px; margin-bottom: 20px; font-size: 14px;">
        ⚠️ ${error}
       </div>`
    : "";

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Autorizar Conexão — OpenMoney</title>
  <link rel="icon" type="image/png" href="/favicon.png">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #090d16;
      color: #f1f5f9;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #111827;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 16px;
      padding: 32px;
      width: 100%;
      max-width: 440px;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }
    .logo-badge {
      background: linear-gradient(135deg, #10b981 0%, #059669 100%);
      width: 44px;
      height: 44px;
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
    }
    .brand-title {
      font-size: 20px;
      font-weight: 700;
      color: #fff;
      letter-spacing: -0.5px;
    }
    .brand-sub {
      font-size: 12px;
      color: #94a3b8;
    }
    h2 {
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 8px;
      color: #f8fafc;
    }
    .desc {
      font-size: 13.5px;
      color: #94a3b8;
      line-height: 1.5;
      margin-bottom: 20px;
    }
    .client-tag {
      color: #34d399;
      font-weight: 600;
    }
    .permissions {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 10px;
      padding: 14px;
      margin-bottom: 24px;
    }
    .permissions-title {
      font-size: 12px;
      text-transform: uppercase;
      font-weight: 700;
      color: #64748b;
      margin-bottom: 8px;
      letter-spacing: 0.5px;
    }
    .perm-item {
      display: flex;
      align-items: flex-start;
      gap: 8px;
      font-size: 13px;
      color: #cbd5e1;
      margin-bottom: 6px;
    }
    .perm-item:last-child { margin-bottom: 0; }
    .perm-icon { color: #10b981; font-weight: bold; }
    .form-group {
      margin-bottom: 16px;
    }
    label {
      display: block;
      font-size: 13px;
      font-weight: 500;
      color: #cbd5e1;
      margin-bottom: 6px;
    }
    input[type="email"], input[type="password"] {
      width: 100%;
      background: #1e293b;
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 8px;
      padding: 12px 14px;
      color: #fff;
      font-size: 14px;
      outline: none;
      transition: border-color 0.2s;
    }
    input[type="email"]:focus, input[type="password"]:focus {
      border-color: #10b981;
    }
    .btn-submit {
      width: 100%;
      background: #10b981;
      color: #064e3b;
      border: none;
      border-radius: 8px;
      padding: 12px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.2s, transform 0.1s;
      margin-top: 8px;
    }
    .btn-submit:hover {
      background: #34d399;
    }
    .btn-submit:active {
      transform: scale(0.99);
    }
    .footer-note {
      text-align: center;
      font-size: 11.5px;
      color: #64748b;
      margin-top: 18px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">
      <div class="logo-badge">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"></circle>
          <path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"></path>
          <path d="M12 6v2m0 8v2"></path>
        </svg>
      </div>
      <div>
        <div class="brand-title">OpenMoney Cloud</div>
        <div class="brand-sub">Conector Oficial de IA (MCP / OAuth 2.1)</div>
      </div>
    </div>

    ${errorBanner}

    <h2>Autorizar Conexão</h2>
    <p class="desc">O assistente <span class="client-tag">${safeClientDisplay}</span> está solicitando acesso para interagir com suas finanças pessoais no OpenMoney.</p>

    <div class="permissions">
      <div class="permissions-title">Permissões Solicitadas:</div>
      <div class="perm-item">
        <span class="perm-icon">✓</span>
        <span>Consultar saldos, faturas e lançamentos financeiros</span>
      </div>
      <div class="perm-item">
        <span class="perm-icon">✓</span>
        <span>Criar, editar ou excluir lançamentos autorizados</span>
      </div>
      <div class="perm-item">
        <span class="perm-icon">✓</span>
        <span>Todas as ações geram logs no Histórico de Auditoria</span>
      </div>
    </div>

    <form method="POST" action="/api/oauth/authorize">
      <input type="hidden" name="client_id" value="${safeClientId}">
      <input type="hidden" name="redirect_uri" value="${safeRedirect}">
      <input type="hidden" name="state" value="${safeState}">
      <input type="hidden" name="scope" value="${safeScope}">
      <input type="hidden" name="code_challenge" value="${safeCodeChallenge}">
      <input type="hidden" name="code_challenge_method" value="${safeCodeChallengeMethod}">

      <div class="form-group">
        <label for="email">Seu E-mail no OpenMoney</label>
        <input type="email" id="email" name="email" value="${safeEmail}" required placeholder="seu@email.com" autocomplete="username">
      </div>

      <div class="form-group">
        <label for="password">Sua Senha</label>
        <input type="password" id="password" name="password" required placeholder="••••••••" autocomplete="current-password">
      </div>

      <button type="submit" class="btn-submit">Autorizar e Conectar</button>
    </form>

    <div class="footer-note">
      🔒 Criptografia ponta a ponta. Você pode revogar o acesso a qualquer momento nas Configurações do OpenMoney.
    </div>
  </div>
</body>
</html>`;
}

export async function onRequest(context) {
  const { request, env } = context;
  const origin = request.headers.get("Origin") || "*";
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");

  const isPublicOrAi =
    path.startsWith("/api/mcp") ||
    path.startsWith("/api/oauth") ||
    path.startsWith("/api/openapi") ||
    path.startsWith("/api/v1/tools") ||
    path.includes("/.well-known/");

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin, isPublicOrAi) });
  }

  // ==========================================================================
  // 0.0 Descoberta Automática OAuth 2.1 / MCP (RFC 8414 & RFC 9728)
  // ==========================================================================
  if (path.includes("/.well-known/oauth-protected-resource")) {
    return jsonResponse(getOAuthProtectedResourceMetadata(url, "/api/mcp"), 200, origin, true);
  }
  if (
    path.includes("/.well-known/oauth-authorization-server") ||
    path.includes("/.well-known/openid-configuration")
  ) {
    return jsonResponse(getOAuthAuthorizationServerMetadata(url), 200, origin, true);
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

    try {
      getMasterSecret(env);
    } catch (e) {
      return jsonResponse(
        { error: e.message },
        500,
        origin
      );
    }

  // ==========================================================================
  // 0.1 GET /api/openapi.json (OpenAPI 3.0 para ChatGPT Custom Actions / Gemini)
  // ==========================================================================
  if (path === "/api/openapi.json" && request.method === "GET") {
    return jsonResponse(getOpenApiSpec(), 200, origin, true);
  }

  // ==========================================================================
  // 0.1b POST /api/oauth/register (Dynamic Client Registration — RFC 7591)
  //      Permite que Claude, ChatGPT e Gemini se registrem automaticamente
  // ==========================================================================
  if (path === "/api/oauth/register" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const clientName = String(body.client_name || "Assistente IA").trim().slice(0, 60);
    const encodedName = bytesToBase64(new TextEncoder().encode(clientName))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    const randomSuffix = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
    const clientId = `opm_c_${encodedName}_${randomSuffix}`;
    const clientSecret = `opm_s_${crypto.randomUUID().replace(/-/g, "")}`;
    const redirectUris = Array.isArray(body.redirect_uris) ? body.redirect_uris : [];
    const grantTypes = Array.isArray(body.grant_types)
      ? body.grant_types
      : ["authorization_code", "refresh_token"];
    const responseTypes = Array.isArray(body.response_types)
      ? body.response_types
      : ["code"];
    const authMethod = body.token_endpoint_auth_method || "client_secret_post";

    const registrationResponse = {
      client_id: clientId,
      client_name: clientName,
      redirect_uris: redirectUris,
      grant_types: grantTypes,
      response_types: responseTypes,
      token_endpoint_auth_method: authMethod,
      scope: body.scope || "read_write offline_access",
    };

    if (authMethod !== "none") {
      registrationResponse.client_secret = clientSecret;
      registrationResponse.client_secret_expires_at = 0;
    }

    await logMcpDiagnostic(
      env,
      request,
      path,
      201,
      `DCR client_name=${clientName} auth=${authMethod} uris=${JSON.stringify(redirectUris)}`
    );

    return jsonResponse(registrationResponse, 201, origin, true);
  }

  // ==========================================================================
  // 0.1c GET /api/oauth/jwks (JSON Web Key Set para descoberta OIDC)
  // ==========================================================================
  if (path === "/api/oauth/jwks" && (request.method === "GET" || request.method === "HEAD")) {
    return jsonResponse({ keys: [] }, 200, origin, true);
  }

  // ==========================================================================
  // 0.1d GET /api/oauth/debug-logs (Diagnóstico de conexões MCP / OAuth)
  // ==========================================================================
  if (path === "/api/oauth/debug-logs" && request.method === "GET") {
    try {
      const rows = await env.DB.prepare(
        "SELECT id, created_at, method, path, status, user_agent, note FROM mcp_debug_logs ORDER BY id DESC LIMIT 40"
      ).all();
      return jsonResponse({ ok: true, logs: rows.results || [] }, 200, origin, true);
    } catch (e) {
      return jsonResponse({ ok: false, error: e.message }, 200, origin, true);
    }
  }

  // ==========================================================================
  // 0.2 GET & POST /api/oauth/authorize (Consentimento OAuth 2.1 + PKCE)
  // ==========================================================================
  if (path === "/api/oauth/authorize") {
    if (request.method === "GET" || request.method === "HEAD") {
      const clientId = url.searchParams.get("client_id") || "ChatGPT / Claude / Gemini";
      const redirectUri = url.searchParams.get("redirect_uri") || "";
      const state = url.searchParams.get("state") || "";
      const scope = url.searchParams.get("scope") || "read_write";
      const codeChallenge = url.searchParams.get("code_challenge") || "";
      const codeChallengeMethod = url.searchParams.get("code_challenge_method") || "S256";
      await logMcpDiagnostic(
        env,
        request,
        path,
        200,
        `authorize GET client=${clientId} redirect=${redirectUri}`
      );
      return new Response(
        renderOAuthConsentHtml({
          clientId,
          redirectUri,
          state,
          scope,
          codeChallenge,
          codeChallengeMethod,
        }),
        { headers: { "Content-Type": "text/html; charset=utf-8" } }
      );
    }

    if (request.method === "POST") {
      let formData;
      try {
        formData = await request.formData();
      } catch (_) {
        const text = await request.text();
        formData = new URLSearchParams(text);
      }

      const email = (formData.get("email") || "").trim().toLowerCase();
      const password = formData.get("password") || "";
      const clientId = formData.get("client_id") || "ChatGPT / Claude / Gemini";
      const redirectUri = formData.get("redirect_uri") || "";
      const state = formData.get("state") || "";
      const scope = formData.get("scope") || "read_write";
      const codeChallenge = formData.get("code_challenge") || "";
      const codeChallengeMethod = formData.get("code_challenge_method") || "S256";

      if (!redirectUri) {
        return new Response("redirect_uri é obrigatório.", { status: 400 });
      }

      const user = await env.DB.prepare(
        "SELECT id, email, name, password_hash, password_salt, failed_attempts, locked_until FROM users WHERE email = ?1"
      ).bind(email).first();

      let loginError = "";
      if (!user) {
        loginError = "E-mail ou senha incorretos.";
      } else if (user.locked_until && new Date(user.locked_until) > new Date()) {
        loginError = "Conta temporariamente bloqueada por segurança. Tente em 15 minutos.";
      } else {
        const computedHash = await hashPasswordPBKDF2(password, user.password_salt);
        if (!timingSafeEqual(computedHash, user.password_hash)) {
          loginError = "E-mail ou senha incorretos.";
        }
      }

      if (loginError) {
        return new Response(
          renderOAuthConsentHtml({
            clientId,
            redirectUri,
            state,
            scope,
            codeChallenge,
            codeChallengeMethod,
            error: loginError,
            email,
          }),
          { status: 401, headers: { "Content-Type": "text/html; charset=utf-8" } }
        );
      }

      const code = "opm_code_" + crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "").slice(0, 8);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      const packedScope = JSON.stringify({
        scope: scope || "read_write",
        cc: codeChallenge || "",
        ccm: codeChallengeMethod || "S256",
      });
      await env.DB.prepare(
        "INSERT INTO oauth_codes (code, user_id, client_id, redirect_uri, scope, created_at, expires_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
      ).bind(code, user.id, clientId, redirectUri, packedScope, new Date().toISOString(), expiresAt).run();

      const targetUrl = new URL(redirectUri);
      targetUrl.searchParams.set("code", code);
      if (state) targetUrl.searchParams.set("state", state);
      targetUrl.searchParams.set("iss", url.origin);

      return Response.redirect(targetUrl.toString(), 302);
    }
  }

  // ==========================================================================
  // 0.3 POST /api/oauth/token (Troca de Código por Access Token + PKCE + Refresh)
  // ==========================================================================
  if (path === "/api/oauth/token" && request.method === "POST") {
    let params;
    const contentType = request.headers.get("Content-Type") || "";
    if (contentType.includes("application/json")) {
      params = await request.json().catch(() => ({}));
    } else {
      const text = await request.text();
      params = Object.fromEntries(new URLSearchParams(text).entries());
    }

    const grantType = params.grant_type;
    let clientId = params.client_id || "";
    const authHeader = request.headers.get("Authorization") || "";
    if (!clientId && authHeader.startsWith("Basic ")) {
      try {
        const decoded = atob(authHeader.slice(6).trim());
        clientId = decoded.split(":")[0] || "";
      } catch (_) {}
    }

    if (grantType === "refresh_token") {
      const refreshToken = String(params.refresh_token || "").trim();
      if (!refreshToken.startsWith("opm_live_")) {
        return jsonResponse(
          { error: "invalid_grant", error_description: "refresh_token inválido." },
          400,
          origin,
          true
        );
      }
      const tokenHash = await sha256Hex(refreshToken);
      const tokRow = await env.DB.prepare(
        "SELECT id, permissions FROM user_api_tokens WHERE token_hash = ?1"
      ).bind(tokenHash).first();
      if (!tokRow) {
        return jsonResponse(
          { error: "invalid_grant", error_description: "Token revogado ou inexistente." },
          400,
          origin,
          true
        );
      }
      return jsonResponse(
        {
          access_token: refreshToken,
          token_type: "Bearer",
          expires_in: 31536000,
          refresh_token: refreshToken,
          scope: tokRow.permissions || "read_write",
        },
        200,
        origin,
        true
      );
    }

    const code = (params.code || "").trim();
    if (grantType !== "authorization_code" || !code) {
      return jsonResponse(
        { error: "unsupported_grant_type", error_description: "grant_type deve ser 'authorization_code' ou 'refresh_token'." },
        400,
        origin,
        true
      );
    }

    const nowIso = new Date().toISOString();
    const codeRow = await env.DB.prepare(
      "SELECT code, user_id, client_id, redirect_uri, scope, expires_at FROM oauth_codes WHERE code = ?1 AND expires_at > ?2"
    ).bind(code, nowIso).first();

    if (!codeRow) {
      return jsonResponse(
        { error: "invalid_grant", error_description: "Código de autorização inválido ou expirado." },
        400,
        origin,
        true
      );
    }

    let actualScope = "read_write";
    let savedChallenge = "";
    let savedMethod = "S256";
    try {
      if (codeRow.scope && codeRow.scope.startsWith("{")) {
        const parsed = JSON.parse(codeRow.scope);
        actualScope = parsed.scope || "read_write";
        savedChallenge = parsed.cc || "";
        savedMethod = parsed.ccm || "S256";
      } else if (codeRow.scope) {
        actualScope = codeRow.scope;
      }
    } catch (_) {}

    if (savedChallenge) {
      const verifier = String(params.code_verifier || "").trim();
      if (!verifier) {
        return jsonResponse(
          { error: "invalid_grant", error_description: "code_verifier (PKCE) obrigatório." },
          400,
          origin,
          true
        );
      }
      if (savedMethod.toUpperCase() === "S256") {
        const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
        const computedChallenge = bytesToBase64(new Uint8Array(digest))
          .replace(/\+/g, "-")
          .replace(/\//g, "_")
          .replace(/=+$/, "");
        if (computedChallenge !== savedChallenge) {
          return jsonResponse(
            { error: "invalid_grant", error_description: "Falha na verificação PKCE S256." },
            400,
            origin,
            true
          );
        }
      } else if (verifier !== savedChallenge) {
        return jsonResponse(
          { error: "invalid_grant", error_description: "Falha na verificação PKCE." },
          400,
          origin,
          true
        );
      }
    }

    await env.DB.prepare("DELETE FROM oauth_codes WHERE code = ?1").bind(code).run().catch(() => {});

    const rawToken = "opm_live_" + crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
    const tokenHash = await sha256Hex(rawToken);
    const tokenPrefix = rawToken.slice(0, 15) + "...";
    const tokenId = crypto.randomUUID();
    const displayClient = formatOAuthClientDisplayName(clientId || codeRow.client_id);
    const clientName = "OAuth: " + displayClient;
    const dbPermissions = actualScope === "read_only" ? "read_only" : "read_write";

    await env.DB.prepare(
      "INSERT INTO user_api_tokens (id, user_id, name, token_hash, token_prefix, permissions, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
    ).bind(
      tokenId,
      codeRow.user_id,
      clientName,
      tokenHash,
      tokenPrefix,
      dbPermissions,
      new Date().toISOString()
    ).run();

    const cleanScopeTokens = String(actualScope || "read_write")
      .split(/\s+/)
      .filter((s) => s && s !== "openid" && s !== "profile" && s !== "email");
    const responseScope =
      cleanScopeTokens.length > 0 ? cleanScopeTokens.join(" ") : "read_write";

    await logMcpDiagnostic(
      env,
      request,
      path,
      200,
      `token issued client=${displayClient} scope=${responseScope}`
    );

    return jsonResponse(
      {
        access_token: rawToken,
        token_type: "Bearer",
        expires_in: 31536000,
        refresh_token: rawToken,
        scope: responseScope,
      },
      200,
      origin,
      true
    );
  }

  // ==========================================================================
  // 0.4 GET /api/oauth/userinfo (Informações do Usuário Autenticado)
  // ==========================================================================
  if (path === "/api/oauth/userinfo" && request.method === "GET") {
    const claims = await authenticateRequest(request, env);
    if (!claims || !claims.sub) {
      return jsonResponse({ error: "Não autenticado." }, 401, origin, true);
    }
    const user = await env.DB.prepare("SELECT id, email, name FROM users WHERE id = ?1").bind(claims.sub).first();
    if (!user) {
      return jsonResponse({ error: "Usuário não encontrado." }, 404, origin, true);
    }
    return jsonResponse(
      {
        sub: user.id,
        email: user.email,
        name: user.name || user.email.split("@")[0],
      },
      200,
      origin,
      true
    );
  }

  // ==========================================================================
  // 1.0. POST /api/auth/register-request (Envia código de 6 dígitos para o e-mail)
  // ==========================================================================
  if (path === "/api/auth/register-request" && request.method === "POST") {
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

    // Proteção Anti-Spam / Cooldown: intervalo mínimo de 60 segundos entre solicitações para o mesmo e-mail
    const recentToken = await env.DB.prepare(
      `SELECT created_at FROM email_verification_tokens
       WHERE email = ?1 AND type = 'register'
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(email)
      .first();

    if (recentToken && recentToken.created_at) {
      const diffSec = (Date.now() - new Date(recentToken.created_at).getTime()) / 1000;
      if (diffSec >= 0 && diffSec < 60) {
        return jsonResponse(
          {
            error: `Aguarde ${Math.ceil(60 - diffSec)} segundo(s) antes de solicitar um novo código de verificação.`,
          },
          429,
          origin
        );
      }
    }

    const code = generateSixDigitCode();
    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, email, secret);
    const tokenId = `reg_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const nowIso = new Date().toISOString();
    const expiresAtIso = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    const initialObj =
      body.initialPayload && typeof body.initialPayload === "object"
        ? body.initialPayload
        : defaultOpenMoneyV7Payload();

    const saltBytes = crypto.getRandomValues(new Uint8Array(16));
    const saltB64 = bytesToBase64(saltBytes);
    const passwordHash = await hashPasswordPBKDF2(password, saltB64);

    const pendingPayload = JSON.stringify({
      name,
      email,
      passwordHash,
      saltB64,
      initialObj,
    });

    await env.DB.prepare(
      "UPDATE email_verification_tokens SET used = 1 WHERE email = ?1 AND type = 'register' AND used = 0"
    )
      .bind(email)
      .run();

    await env.DB.prepare(
      `INSERT INTO email_verification_tokens (id, user_id, email, type, code_hash, pending_payload, created_at, expires_at, used)
       VALUES (?1, NULL, ?2, 'register', ?3, ?4, ?5, ?6, 0)`
    )
      .bind(tokenId, email, codeHash, pendingPayload, nowIso, expiresAtIso)
      .run();

    try {
      const htmlText = buildRegistrationEmailHtml({
        code,
        email,
        name,
      });
      await sendResendEmail({
        env,
        to: email,
        subject: `OpenMoney: Código de Confirmação de Cadastro (${code})`,
        htmlText,
      });
    } catch (err) {
      return jsonResponse(
        {
          error:
            err.message ||
            "Não foi possível enviar o e-mail de confirmação. Verifique a configuração do Resend na Cloudflare.",
        },
        500,
        origin
      );
    }

    return jsonResponse(
      {
        ok: true,
        step: "verify_code",
        message: "Código de confirmação enviado para o seu e-mail!",
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 1.1. POST /api/auth/register-confirm (Valida código e cria conta)
  // ==========================================================================
  if (path === "/api/auth/register-confirm" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return jsonResponse({ error: "JSON inválido." }, 400, origin);
    }

    const email = String(body.email || "")
      .trim()
      .toLowerCase();
    const code = String(body.code || "").trim();

    if (!email || !code) {
      return jsonResponse(
        { error: "E-mail e código de verificação são obrigatórios." },
        400,
        origin
      );
    }

    const nowIso = new Date().toISOString();

    const tokenRow = await env.DB.prepare(
      `SELECT id, code_hash, attempts, pending_payload FROM email_verification_tokens
       WHERE email = ?1 AND type = 'register' AND used = 0 AND expires_at > ?2
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(email, nowIso)
      .first();

    if (!tokenRow) {
      return jsonResponse(
        { error: "Código inválido ou expirado. Solicite um novo código." },
        400,
        origin
      );
    }

    const attempts = Number(tokenRow.attempts || 0);
    if (attempts >= 5) {
      await env.DB.prepare(
        "UPDATE email_verification_tokens SET used = 2 WHERE id = ?1"
      )
        .bind(tokenRow.id)
        .run();
      return jsonResponse(
        {
          error:
            "Código bloqueado por excesso de tentativas. Solicite um novo código de confirmação.",
        },
        429,
        origin
      );
    }

    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, email, secret);

    if (!timingSafeEqual(codeHash, tokenRow.code_hash)) {
      const nextAttempts = attempts + 1;
      await env.DB.prepare(
        "UPDATE email_verification_tokens SET attempts = ?1 WHERE id = ?2"
      )
        .bind(nextAttempts, tokenRow.id)
        .run();
      const remaining = Math.max(0, 5 - nextAttempts);
      return jsonResponse(
        {
          error:
            remaining > 0
              ? `Código de confirmação incorreto. Você tem mais ${remaining} tentativa(s).`
              : "Código bloqueado por excesso de tentativas. Solicite um novo código de confirmação.",
        },
        remaining > 0 ? 400 : 429,
        origin
      );
    }

    let pendingData = null;
    try {
      pendingData = JSON.parse(tokenRow.pending_payload);
    } catch (_) {
      return jsonResponse(
        { error: "Dados de cadastro pendente corrompidos." },
        500,
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
    const encryptedPayload = await encryptUserPayload(
      JSON.stringify(pendingData.initialObj || defaultOpenMoneyV7Payload()),
      userId,
      env
    );

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO users (id, email, name, password_hash, password_salt, failed_attempts, created_at, last_login_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?6)`
      ).bind(
        userId,
        email,
        pendingData.name || "",
        pendingData.passwordHash,
        pendingData.saltB64,
        nowIso
      ),
      env.DB.prepare(
        `INSERT INTO user_databases (user_id, schema_version, revision, payload, preferences, updated_at)
         VALUES (?1, 7, 1, ?2, '{}', ?3)`
      ).bind(userId, encryptedPayload, nowIso),
      env.DB.prepare(
        "UPDATE email_verification_tokens SET used = 1 WHERE id = ?1"
      ).bind(tokenRow.id),
    ]);

    const token = await signJwt(
      { sub: userId, email, name: pendingData.name || "" },
      env
    );
    return jsonResponse(
      {
        token,
        revision: 1,
        user: { id: userId, email, name: pendingData.name || "" },
      },
      201,
      origin
    );
  }

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
  // 2.1 POST /api/auth/forgot-password (Solicita código de 6 dígitos via Resend)
  // ==========================================================================
  if (path === "/api/auth/forgot-password" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const email = String(body.email || "").trim().toLowerCase();

    if (!email || !email.includes("@")) {
      return jsonResponse({ error: "Informe um e-mail válido." }, 400, origin);
    }

    const user = await env.DB.prepare(
      "SELECT id, name, email FROM users WHERE email = ?1"
    )
      .bind(email)
      .first();

    if (!user) {
      return jsonResponse(
        {
          ok: true,
          message:
            "Se este e-mail estiver cadastrado, você receberá o código de recuperação em instantes.",
        },
        200,
        origin
      );
    }

    // Proteção Anti-Spam / Cooldown: intervalo mínimo de 60 segundos entre solicitações para o mesmo e-mail
    const recentReset = await env.DB.prepare(
      `SELECT created_at FROM password_reset_tokens
       WHERE email = ?1
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(email)
      .first();

    if (recentReset && recentReset.created_at) {
      const diffSec = (Date.now() - new Date(recentReset.created_at).getTime()) / 1000;
      if (diffSec >= 0 && diffSec < 60) {
        return jsonResponse(
          {
            error: `Aguarde ${Math.ceil(60 - diffSec)} segundo(s) antes de solicitar um novo código de recuperação.`,
          },
          429,
          origin
        );
      }
    }

    const code = generateSixDigitCode();
    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, email, secret);
    const tokenId = `rst_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const nowIso = new Date().toISOString();
    const expiresAtIso = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    await env.DB.prepare(
      "UPDATE password_reset_tokens SET used = 1 WHERE email = ?1 AND used = 0"
    )
      .bind(email)
      .run();

    await env.DB.prepare(
      `INSERT INTO password_reset_tokens (id, user_id, email, code_hash, created_at, expires_at, used)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)`
    )
      .bind(tokenId, user.id, email, codeHash, nowIso, expiresAtIso)
      .run();

    try {
      const htmlText = buildPasswordResetEmailHtml({
        code,
        email,
        name: user.name,
      });
      await sendResendEmail({
        env,
        to: email,
        subject: `OpenMoney: Código de Recuperação de Senha (${code})`,
        htmlText,
      });
    } catch (err) {
      return jsonResponse(
        {
          error:
            err.message ||
            "Não foi possível enviar o e-mail de recuperação. Verifique a configuração do Resend na Cloudflare.",
        },
        500,
        origin
      );
    }

    return jsonResponse(
      {
        ok: true,
        message: "Código de recuperação enviado para o seu e-mail!",
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 2.2 POST /api/auth/verify-reset-code (Valida o código de 6 dígitos)
  // ==========================================================================
  if (path === "/api/auth/verify-reset-code" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const email = String(body.email || "").trim().toLowerCase();
    const code = String(body.code || "").trim();

    if (!email || !code) {
      return jsonResponse({ error: "E-mail e código são obrigatórios." }, 400, origin);
    }

    const nowIso = new Date().toISOString();

    const tokenRow = await env.DB.prepare(
      `SELECT id, code_hash, attempts FROM password_reset_tokens 
       WHERE email = ?1 AND used = 0 AND expires_at > ?2
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(email, nowIso)
      .first();

    if (!tokenRow) {
      return jsonResponse(
        { error: "Código inválido ou expirado. Solicite um novo código." },
        400,
        origin
      );
    }

    const attempts = Number(tokenRow.attempts || 0);
    if (attempts >= 5) {
      await env.DB.prepare(
        "UPDATE password_reset_tokens SET used = 2 WHERE id = ?1"
      )
        .bind(tokenRow.id)
        .run();
      return jsonResponse(
        {
          error:
            "Código bloqueado por excesso de tentativas. Solicite um novo código de recuperação.",
        },
        429,
        origin
      );
    }

    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, email, secret);

    if (!timingSafeEqual(codeHash, tokenRow.code_hash)) {
      const nextAttempts = attempts + 1;
      await env.DB.prepare(
        "UPDATE password_reset_tokens SET attempts = ?1 WHERE id = ?2"
      )
        .bind(nextAttempts, tokenRow.id)
        .run();
      const remaining = Math.max(0, 5 - nextAttempts);
      return jsonResponse(
        {
          error:
            remaining > 0
              ? `Código de recuperação incorreto. Você tem mais ${remaining} tentativa(s).`
              : "Código bloqueado por excesso de tentativas. Solicite um novo código de recuperação.",
        },
        remaining > 0 ? 400 : 429,
        origin
      );
    }

    return jsonResponse({ ok: true, valid: true }, 200, origin);
  }

  // ==========================================================================
  // 2.3 POST /api/auth/reset-password (Define a nova senha com o código)
  // ==========================================================================
  if (path === "/api/auth/reset-password" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const email = String(body.email || "").trim().toLowerCase();
    const code = String(body.code || "").trim();
    const newPassword = String(body.newPassword || "");

    if (!email || !code) {
      return jsonResponse({ error: "E-mail e código são obrigatórios." }, 400, origin);
    }
    if (newPassword.length < 8) {
      return jsonResponse(
        { error: "A nova senha deve ter pelo menos 8 caracteres." },
        400,
        origin
      );
    }

    const nowIso = new Date().toISOString();

    const tokenRow = await env.DB.prepare(
      `SELECT id, user_id, code_hash, attempts FROM password_reset_tokens 
       WHERE email = ?1 AND used = 0 AND expires_at > ?2
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(email, nowIso)
      .first();

    if (!tokenRow) {
      return jsonResponse(
        { error: "Código inválido ou expirado. Solicite um novo código." },
        400,
        origin
      );
    }

    const attempts = Number(tokenRow.attempts || 0);
    if (attempts >= 5) {
      await env.DB.prepare(
        "UPDATE password_reset_tokens SET used = 2 WHERE id = ?1"
      )
        .bind(tokenRow.id)
        .run();
      return jsonResponse(
        {
          error:
            "Código bloqueado por excesso de tentativas. Solicite um novo código de recuperação.",
        },
        429,
        origin
      );
    }

    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, email, secret);

    if (!timingSafeEqual(codeHash, tokenRow.code_hash)) {
      const nextAttempts = attempts + 1;
      await env.DB.prepare(
        "UPDATE password_reset_tokens SET attempts = ?1 WHERE id = ?2"
      )
        .bind(nextAttempts, tokenRow.id)
        .run();
      const remaining = Math.max(0, 5 - nextAttempts);
      return jsonResponse(
        {
          error:
            remaining > 0
              ? `Código de recuperação incorreto. Você tem mais ${remaining} tentativa(s).`
              : "Código bloqueado por excesso de tentativas. Solicite um novo código de recuperação.",
        },
        remaining > 0 ? 400 : 429,
        origin
      );
    }

    const user = await env.DB.prepare(
      "SELECT id, name, email FROM users WHERE id = ?1"
    )
      .bind(tokenRow.user_id)
      .first();

    if (!user) {
      return jsonResponse({ error: "Usuário não encontrado." }, 404, origin);
    }

    const newSalt = bytesToBase64(crypto.getRandomValues(new Uint8Array(16)));
    const newHash = await hashPasswordPBKDF2(newPassword, newSalt);

    await env.DB.batch([
      env.DB.prepare(
        "UPDATE users SET password_hash = ?1, password_salt = ?2, failed_attempts = 0, locked_until = NULL WHERE id = ?3"
      ).bind(newHash, newSalt, user.id),
      env.DB.prepare(
        "UPDATE password_reset_tokens SET used = 1 WHERE id = ?1"
      ).bind(tokenRow.id),
    ]);

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
        ok: true,
        token,
        revision: dbRow ? Number(dbRow.revision) : 1,
        user: { id: user.id, email: user.email, name: user.name },
        message: "Senha redefinida com sucesso!",
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // Todas as rotas abaixo exigem Token JWT ou OAuth Bearer válido
  // ==========================================================================
  const claims = await authenticateRequest(request, env);
  if (!claims || !claims.sub) {
    if (isPublicOrAi) {
      const originalPath = request.headers.get("X-OpenMoney-Original-Path") || path;
      await logMcpDiagnostic(env, request, originalPath, 401, "MCP 401 challenge");
      return new Response(
        JSON.stringify({
          error: "invalid_token",
          error_description: "Autenticação OAuth 2.1 necessária para acessar o servidor MCP do OpenMoney.",
        }),
        {
          status: 401,
          headers: {
            ...corsHeaders(origin, true),
            "WWW-Authenticate": `Bearer resource_metadata="${url.origin}/.well-known/oauth-protected-resource${originalPath}", scope="read_write"`,
          },
        }
      );
    }
    return jsonResponse(
      { error: "Sessão expirada ou não autenticada." },
      401,
      origin
    );
  }
  const userId = String(claims.sub);

  // ==========================================================================
  // 2.4 POST /api/auth/change-email-request (Solicita troca de e-mail autenticado)
  // ==========================================================================
  if (path === "/api/auth/change-email-request" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const newEmail = String(body.newEmail || "").trim().toLowerCase();
    const currentPassword = String(body.password || "");

    if (!newEmail || !newEmail.includes("@")) {
      return jsonResponse(
        { error: "Informe um novo endereço de e-mail válido." },
        400,
        origin
      );
    }

    if (!currentPassword) {
      return jsonResponse(
        { error: "Informe sua senha atual para confirmar a troca de e-mail." },
        400,
        origin
      );
    }

    const user = await env.DB.prepare(
      "SELECT id, email, name, password_hash, password_salt FROM users WHERE id = ?1"
    )
      .bind(userId)
      .first();

    if (!user) {
      return jsonResponse({ error: "Usuário não encontrado." }, 404, origin);
    }

    if (newEmail === String(user.email).toLowerCase()) {
      return jsonResponse(
        { error: "O novo e-mail deve ser diferente do e-mail atual." },
        400,
        origin
      );
    }

    const validPass = await verifyPasswordPBKDF2(
      currentPassword,
      user.password_hash,
      user.password_salt
    );
    if (!validPass) {
      return jsonResponse({ error: "Senha incorreta." }, 403, origin);
    }

    const existingNew = await env.DB.prepare(
      "SELECT id FROM users WHERE email = ?1"
    )
      .bind(newEmail)
      .first();

    if (existingNew) {
      return jsonResponse(
        {
          error:
            "Este novo endereço de e-mail já está sendo utilizado por outra conta.",
        },
        409,
        origin
      );
    }

    // Proteção Anti-Spam / Cooldown: intervalo mínimo de 60 segundos entre solicitações para o mesmo usuário
    const recentChange = await env.DB.prepare(
      `SELECT created_at FROM email_verification_tokens
       WHERE user_id = ?1 AND type = 'change_email'
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(user.id)
      .first();

    if (recentChange && recentChange.created_at) {
      const diffSec = (Date.now() - new Date(recentChange.created_at).getTime()) / 1000;
      if (diffSec >= 0 && diffSec < 60) {
        return jsonResponse(
          {
            error: `Aguarde ${Math.ceil(60 - diffSec)} segundo(s) antes de solicitar um novo código de confirmação.`,
          },
          429,
          origin
        );
      }
    }

    const code = generateSixDigitCode();
    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, newEmail, secret);
    const tokenId = `eml_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const nowIso = new Date().toISOString();
    const expiresAtIso = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    await env.DB.prepare(
      "UPDATE email_verification_tokens SET used = 1 WHERE user_id = ?1 AND type = 'change_email' AND used = 0"
    )
      .bind(user.id)
      .run();

    await env.DB.prepare(
      `INSERT INTO email_verification_tokens (id, user_id, email, type, code_hash, pending_payload, created_at, expires_at, used)
       VALUES (?1, ?2, ?3, 'change_email', ?4, ?5, ?6, ?7, 0)`
    )
      .bind(
        tokenId,
        user.id,
        newEmail,
        codeHash,
        JSON.stringify({ currentEmail: user.email, newEmail }),
        nowIso,
        expiresAtIso
      )
      .run();

    try {
      const htmlText = buildChangeEmailHtml({
        code,
        currentEmail: user.email,
        newEmail,
        name: user.name,
      });
      await sendResendEmail({
        env,
        to: newEmail,
        subject: `OpenMoney: Código para Confirmação do Novo E-mail (${code})`,
        htmlText,
      });
    } catch (err) {
      return jsonResponse(
        {
          error:
            err.message ||
            "Não foi possível enviar o e-mail para o novo endereço. Verifique o e-mail digitado.",
        },
        500,
        origin
      );
    }

    return jsonResponse(
      {
        ok: true,
        message: `Código de verificação enviado para o novo e-mail (${newEmail})!`,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 2.5 POST /api/auth/change-email-confirm (Confirma e altera o e-mail)
  // ==========================================================================
  if (path === "/api/auth/change-email-confirm" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const newEmail = String(body.newEmail || "").trim().toLowerCase();
    const code = String(body.code || "").trim();

    if (!newEmail || !code) {
      return jsonResponse(
        { error: "Novo e-mail e código de verificação são obrigatórios." },
        400,
        origin
      );
    }

    const nowIso = new Date().toISOString();

    const tokenRow = await env.DB.prepare(
      `SELECT id, code_hash, attempts FROM email_verification_tokens
       WHERE user_id = ?1 AND email = ?2 AND type = 'change_email' AND used = 0 AND expires_at > ?3
       ORDER BY created_at DESC LIMIT 1`
    )
      .bind(userId, newEmail, nowIso)
      .first();

    if (!tokenRow) {
      return jsonResponse(
        { error: "Código inválido ou expirado. Solicite um novo código." },
        400,
        origin
      );
    }

    const attempts = Number(tokenRow.attempts || 0);
    if (attempts >= 5) {
      await env.DB.prepare(
        "UPDATE email_verification_tokens SET used = 2 WHERE id = ?1"
      )
        .bind(tokenRow.id)
        .run();
      return jsonResponse(
        {
          error:
            "Código bloqueado por excesso de tentativas. Solicite um novo código de alteração de e-mail.",
        },
        429,
        origin
      );
    }

    const secret = getMasterSecret(env);
    const codeHash = await hashResetCode(code, newEmail, secret);

    if (!timingSafeEqual(codeHash, tokenRow.code_hash)) {
      const nextAttempts = attempts + 1;
      await env.DB.prepare(
        "UPDATE email_verification_tokens SET attempts = ?1 WHERE id = ?2"
      )
        .bind(nextAttempts, tokenRow.id)
        .run();
      const remaining = Math.max(0, 5 - nextAttempts);
      return jsonResponse(
        {
          error:
            remaining > 0
              ? `Código de confirmação incorreto. Você tem mais ${remaining} tentativa(s).`
              : "Código bloqueado por excesso de tentativas. Solicite um novo código de alteração de e-mail.",
        },
        remaining > 0 ? 400 : 429,
        origin
      );
    }

    const user = await env.DB.prepare(
      "SELECT id, name FROM users WHERE id = ?1"
    )
      .bind(userId)
      .first();

    if (!user) {
      return jsonResponse({ error: "Usuário não encontrado." }, 404, origin);
    }

    await env.DB.batch([
      env.DB.prepare("UPDATE users SET email = ?1 WHERE id = ?2").bind(
        newEmail,
        user.id
      ),
      env.DB.prepare(
        "UPDATE email_verification_tokens SET used = 1 WHERE id = ?1"
      ).bind(tokenRow.id),
    ]);

    const token = await signJwt(
      { sub: user.id, email: newEmail, name: user.name },
      env
    );
    return jsonResponse(
      {
        ok: true,
        token,
        newEmail,
        user: { id: user.id, email: newEmail, name: user.name },
        message: "E-mail da conta atualizado com sucesso!",
      },
      200,
      origin
    );
  }

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
  // 3.5. GET /api/db/revision ou HEAD /api/db (Consulta leve de revisão remota sem tráfego de dados)
  // ==========================================================================
  if (
    (path === "/api/db/revision" && request.method === "GET") ||
    (path === "/api/db" && request.method === "HEAD")
  ) {
    const meta = await ensureUserSyncMeta(env.DB, userId);
    const currentRev = meta.seq;
    const updatedAt = meta.updatedAt;

    if (request.method === "HEAD") {
      return new Response(null, {
        status: 200,
        headers: {
          ...corsHeaders(origin),
          "X-OpenMoney-Revision": String(currentRev),
          "X-OpenMoney-Updated-At": updatedAt,
        },
      });
    }

    return jsonResponse(
      {
        ok: true,
        revision: currentRev,
        updatedAt: updatedAt,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 3.8. GET & POST /api/sync (Motor Sync v2 Granular por Registro em Tempo Real)
  // ==========================================================================
  if (path === "/api/sync" && request.method === "GET") {
    const upgradeHeader = (request.headers.get("Upgrade") || "").toLowerCase();
    if (upgradeHeader === "websocket") {
      if (env.SYNC) {
        const doId = env.SYNC.idFromName(userId);
        const stub = env.SYNC.get(doId);
        return stub.fetch(request);
      }
      return jsonResponse(
        { ok: false, wsSupported: false, message: "Durable Object não vinculado; usando canal delta rápido." },
        426,
        origin
      );
    }

    const since = Math.max(
      0,
      parseInt(url.searchParams.get("since") || "0", 10) || 0
    );
    const meta = await ensureUserSyncMeta(env.DB, userId);

    if (url.searchParams.get("ensureBackup") === "1") {
      const tzOffset = extractTzOffsetMinutes(request, url);
      await ensurePeriodicCloudBackupFromCurrentDb(
        env.DB,
        userId,
        new Date().toISOString(),
        tzOffset
      );
    }

    // 1. Caminho ultrarrápido: cliente já está na sequência exata da nuvem
    if (since > 0 && since >= meta.seq && since >= meta.baseSeq) {
      return jsonResponse(
        {
          ok: true,
          seq: meta.seq,
          snapshotSeq: meta.snapshotSeq,
          full: false,
          fullReloadRequired: false,
          changes: [],
        },
        200,
        origin
      );
    }

    // 2. Sincronização incremental (Delta): retorna apenas os registros alterados desde `since`
    if (since > 0 && since >= meta.baseSeq && since < meta.seq) {
      const aesKey = await deriveUserAesKey(userId, env);
      const changes = await loadDecryptedSyncChangesSince(
        env.DB,
        userId,
        since,
        aesKey
      );
      return jsonResponse(
        {
          ok: true,
          seq: meta.seq,
          snapshotSeq: meta.snapshotSeq,
          full: false,
          fullReloadRequired: false,
          changes,
        },
        200,
        origin
      );
    }

    // 3. Carga inicial (`since == 0`) ou após reset/importação completa (`since < baseSeq`):
    // Instrui o cliente a baixar o snapshot binário Gzip via GET /api/db?format=binary (0.5ms CPU no Worker)
    // e aplicar os deltas posteriores a snapshotSeq localmente no navegador.
    return jsonResponse(
      {
        ok: true,
        seq: meta.seq,
        snapshotSeq: meta.snapshotSeq,
        full: false,
        fullReloadRequired: true,
        changes: [],
      },
      200,
      origin
    );
  }

  if (path === "/api/sync" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return jsonResponse({ error: "JSON inválido em /api/sync." }, 400, origin);
    }

    const opId = String(body.opId || "").trim();
    const clientSince = Math.max(0, Number(body.since || 0));
    const incomingChanges = Array.isArray(body.changes) ? body.changes : [];
    const meta = await ensureUserSyncMeta(env.DB, userId);
    const aesKey = await deriveUserAesKey(userId, env);

    // Verifica idempotência por opId (evita duplicação em retentativas de rede)
    if (opId) {
      const existingOp = await env.DB.prepare(
        `SELECT seq FROM user_sync_ops WHERE user_id = ?1 AND op_id = ?2`
      )
        .bind(userId, opId)
        .first();
      if (existingOp) {
        const remoteChanges =
          clientSince >= meta.baseSeq && clientSince < meta.seq
            ? await loadDecryptedSyncChangesSince(
                env.DB,
                userId,
                clientSince,
                aesKey
              )
            : [];
        return jsonResponse(
          {
            ok: true,
            duplicate: true,
            opId,
            seq: meta.seq,
            snapshotSeq: meta.snapshotSeq,
            remoteChanges,
          },
          200,
          origin
        );
      }
    }

    // Busca alterações feitas por outros dispositivos desde `clientSince` antes de gravar o lote atual
    let remoteChanges = [];
    let fullReloadRequired = false;
    if (clientSince === 0 || clientSince < meta.baseSeq) {
      fullReloadRequired = true;
    } else if (clientSince < meta.seq) {
      remoteChanges = await loadDecryptedSyncChangesSince(
        env.DB,
        userId,
        clientSince,
        aesKey
      );
    }

    // Se o cliente ainda não carregou o snapshot base ou está antes de um reset/restore,
    // exige pull completo antes de aceitar gravações para jamais corromper a base!
    if (fullReloadRequired) {
      return jsonResponse(
        {
          ok: true,
          opId,
          seq: meta.seq,
          snapshotSeq: meta.snapshotSeq,
          remoteChanges: [],
          fullReloadRequired: true,
        },
        200,
        origin
      );
    }

    if (incomingChanges.length === 0) {
      return jsonResponse(
        {
          ok: true,
          opId,
          seq: meta.seq,
          snapshotSeq: meta.snapshotSeq,
          remoteChanges,
          fullReloadRequired: false,
        },
        200,
        origin
      );
    }

    const nextSeq = meta.seq + 1;
    const nowIso = new Date().toISOString();
    const stmts = [];
    const broadcastChanges = [];

    for (const ch of incomingChanges) {
      if (!ch || !ch.coll || ch.id === undefined || ch.id === null) continue;
      const coll = String(ch.coll).trim();
      const recId = String(ch.id);
      if (!coll || !recId) continue;

      const isDel =
        Boolean(ch.deleted) || ch.data === null || ch.data === undefined;
      let encData = null;
      if (!isDel) {
        encData = await encryptRecordWithKey(JSON.stringify(ch.data), aesKey);
      }

      stmts.push(
        env.DB.prepare(
          `INSERT INTO user_sync_records (user_id, coll, record_id, encrypted_data, deleted, seq, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
           ON CONFLICT(user_id, coll, record_id) DO UPDATE SET
             encrypted_data = excluded.encrypted_data,
             deleted = excluded.deleted,
             seq = excluded.seq,
             updated_at = excluded.updated_at`
        ).bind(userId, coll, recId, encData, isDel ? 1 : 0, nextSeq, nowIso)
      );

      broadcastChanges.push({
        coll,
        id: recId,
        data: isDel ? null : ch.data,
        deleted: isDel,
        seq: nextSeq,
      });
    }

    // Executa em lotes seguros para o D1
    const BATCH_LIMIT = 75;
    for (let i = 0; i < stmts.length; i += BATCH_LIMIT) {
      await env.DB.batch(stmts.slice(i, i + BATCH_LIMIT));
    }

    const metaStmts = [
      env.DB.prepare(
        `UPDATE user_sync_meta SET seq = ?1, updated_at = ?2 WHERE user_id = ?3`
      ).bind(nextSeq, nowIso, userId),
    ];
    if (opId) {
      metaStmts.push(
        env.DB.prepare(
          `INSERT INTO user_sync_ops (user_id, op_id, seq, created_at)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT(user_id, op_id) DO UPDATE SET seq = excluded.seq`
        ).bind(userId, opId, nextSeq, nowIso)
      );
    }
    await env.DB.batch(metaStmts);

    if (typeof context.waitUntil === "function") {
      context.waitUntil(
        notifyDurableObjectSync(env, userId, {
          seq: nextSeq,
          opId,
          reset: false,
          changes: broadcastChanges,
        })
      );
    }

    return jsonResponse(
      {
        ok: true,
        opId,
        seq: nextSeq,
        snapshotSeq: meta.snapshotSeq,
        updatedAt: nowIso,
        remoteChanges,
        fullReloadRequired: false,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 4. GET /api/db (Leitura isolada e descriptografada do openmoney.json)
  // ==========================================================================
  if (path === "/api/db" && request.method === "GET") {
    const meta = await ensureUserSyncMeta(env.DB, userId);
    const row = await env.DB.prepare(
      "SELECT schema_version, revision, payload, preferences, updated_at FROM user_databases WHERE user_id = ?1"
    )
      .bind(userId)
      .first();

    const wantBinary = url.searchParams.get("format") === "binary";

    if (!row) {
      const initial = defaultOpenMoneyV7Payload();
      if (wantBinary) {
        const gzipBytes = await compressGzip(JSON.stringify(initial));
        return new Response(gzipBytes, {
          status: 200,
          headers: {
            ...corsHeaders(origin),
            "Content-Type": "application/octet-stream",
            "X-OpenMoney-Compression": "gzip",
            "X-OpenMoney-Revision": "1",
            "X-OpenMoney-Sync-Seq": String(meta.seq),
            "X-OpenMoney-Snapshot-Seq": String(meta.snapshotSeq),
            "X-OpenMoney-Updated-At": new Date().toISOString(),
            "X-OpenMoney-Prefs": base64UrlEncode("{}"),
          },
        });
      }
      return jsonResponse(
        {
          schemaVersion: 7,
          revision: 1,
          syncSeq: meta.seq,
          snapshotSeq: meta.snapshotSeq,
          payload: initial,
          preferences: {},
          updatedAt: new Date().toISOString(),
        },
        200,
        origin
      );
    }

    try {
      const fullEncrypted = await loadEncryptedPayloadFromD1(
        env.DB,
        userId,
        row.payload
      );

      const snapshotRev = Number(row.revision || 1);
      const syncSeq = Math.max(meta.seq, snapshotRev);
      const snapshotSeq = Math.min(meta.snapshotSeq, syncSeq);
      const tzOffset = extractTzOffsetMinutes(request, url);

      if (wantBinary) {
        // Caminho binário ultrarrápido: retorna os bytes Gzip direto sem JSON.parse/decompress no Worker
        const gzipBytes = await decryptUserPayloadToGzipBytes(
          fullEncrypted,
          userId,
          env
        );
        await ensurePeriodicCloudBackupFromCurrentDb(
          env.DB,
          userId,
          new Date().toISOString(),
          tzOffset
        );
        return new Response(gzipBytes, {
          status: 200,
          headers: {
            ...corsHeaders(origin),
            "Content-Type": "application/octet-stream",
            "X-OpenMoney-Compression": "gzip",
            "X-OpenMoney-Revision": String(snapshotRev),
            "X-OpenMoney-Sync-Seq": String(syncSeq),
            "X-OpenMoney-Snapshot-Seq": String(snapshotSeq),
            "X-OpenMoney-Updated-At": String(row.updated_at || ""),
            "X-OpenMoney-Prefs": base64UrlEncode(row.preferences || "{}"),
          },
        });
      }

      const decryptedStr = await decryptUserPayload(fullEncrypted, userId, env);
      const parsedPayload = JSON.parse(decryptedStr);

      let parsedPrefs = {};
      try {
        parsedPrefs = JSON.parse(row.preferences || "{}");
      } catch (_) {}

      await ensurePeriodicCloudBackupFromCurrentDb(
        env.DB,
        userId,
        new Date().toISOString(),
        tzOffset
      );

      return jsonResponse(
        {
          schemaVersion: Number(row.schema_version || 7),
          revision: snapshotRev,
          syncSeq,
          snapshotSeq,
          payload: parsedPayload,
          preferences: parsedPrefs,
          updatedAt: row.updated_at,
        },
        200,
        origin
      );
    } catch (decryptErr) {
      // NUNCA sobrescreve user_databases ou apaga chunks em caso de erro de leitura/CPU!
      console.error(
        "Erro ao ler/descriptografar base para user_id:",
        userId,
        decryptErr
      );
      return jsonResponse(
        {
          error: `Erro temporário ao ler base criptografada na nuvem: ${
            decryptErr.message || decryptErr
          }`,
        },
        500,
        origin
      );
    }
  }

  // ==========================================================================
  // 5. PUT /api/db (Gravação criptografada AES-256-GCM + Chunking D1 + Backup Diário)
  // ==========================================================================
  if (path === "/api/db" && request.method === "PUT") {
    const contentType = (
      request.headers.get("Content-Type") || ""
    ).toLowerCase();

    let encryptedPayload = "";
    let prefsStr = "{}";
    let sizeBytes = 0;

    if (contentType.includes("application/octet-stream")) {
      // Caminho binário Gzip pré-comprimido no cliente (zero CPU de JSON/Gzip no Worker!)
      const rawBuf = await request.arrayBuffer();
      const compressedBytes = new Uint8Array(rawBuf);
      if (compressedBytes.byteLength === 0) {
        return jsonResponse({ error: "Payload binário vazio." }, 400, origin);
      }
      sizeBytes = Number(
        request.headers.get("X-OpenMoney-Raw-Size") ||
          compressedBytes.byteLength
      );
      const prefsHeader = request.headers.get("X-OpenMoney-Prefs") || "";
      if (prefsHeader) {
        try {
          prefsStr = decoder.decode(base64UrlDecodeToBytes(prefsHeader));
        } catch (_) {
          prefsStr = "{}";
        }
      }
      encryptedPayload = await encryptCompressedBytes(
        compressedBytes,
        userId,
        env
      );
    } else {
      // Compatibilidade JSON para payloads menores ou clientes legados
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
      const plainJsonStr = JSON.stringify(payloadObj);
      sizeBytes = encoder.encode(plainJsonStr).byteLength;
      encryptedPayload = await encryptUserPayload(plainJsonStr, userId, env);
      prefsStr = JSON.stringify(prefsObj);
    }

    const meta = await ensureUserSyncMeta(env.DB, userId);
    const current = await env.DB.prepare(
      "SELECT revision, payload FROM user_databases WHERE user_id = ?1"
    )
      .bind(userId)
      .first();

    const currentRev = Math.max(
      meta.seq,
      current ? Number(current.revision || 1) : 0
    );

    const isForce =
      request.headers.get("X-OpenMoney-Force") === "true" ||
      url.searchParams.get("force") === "true";

    // Proteção absoluta contra perda de dados: se a base atual no D1 é grande (chunked)
    // e o envio não tem force=true explícito, bloqueia qualquer payload vazio/pequeno (<50KB)!
    // Nota: uma base vazia com 66 categorias padrão em JSON possui ~4.2KB.
    const currentIsChunked =
      current &&
      typeof current.payload === "string" &&
      current.payload.startsWith("chunked:");
    if (currentIsChunked && sizeBytes < 50000 && !isForce) {
      return jsonResponse(
        {
          error:
            "Proteção anti-perda ativada: tentativa de sobrescrever base grande com payload vazio/reduzido bloqueada.",
        },
        409,
        origin
      );
    }

    // Modo de compactação em background enviado pelo cliente após aplicar deltas Sync v2
    const compactSeqHeader =
      request.headers.get("X-OpenMoney-Compact-Seq") ||
      url.searchParams.get("compactSeq");
    if (compactSeqHeader !== null && compactSeqHeader !== undefined) {
      if (currentIsChunked && sizeBytes < 50000) {
        return jsonResponse(
          {
            error:
              "Proteção anti-perda ativada: compactação em lote reduzido (<50KB) sobre base grande bloqueada.",
          },
          409,
          origin
        );
      }
      const compactSeq = parseInt(compactSeqHeader, 10);
      if (isNaN(compactSeq) || compactSeq < meta.seq) {
        return jsonResponse(
          {
            ok: false,
            skipped: true,
            seq: meta.seq,
          },
          200,
          origin
        );
      }
      const nowIso = new Date().toISOString();
      const tzOffset = extractTzOffsetMinutes(request, url);

      await saveEncryptedPayloadToD1(
        env.DB,
        userId,
        compactSeq,
        encryptedPayload,
        prefsStr,
        nowIso,
        tzOffset,
        sizeBytes,
        true
      );

      const minKeepSeq = Math.max(1, compactSeq - 500);
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE user_sync_meta
           SET snapshot_seq = ?1, base_seq = ?2, updated_at = ?3
           WHERE user_id = ?4 AND seq = ?1`
        ).bind(compactSeq, minKeepSeq, nowIso, userId),
        env.DB.prepare(
          `DELETE FROM user_sync_records WHERE user_id = ?1 AND seq < ?2`
        ).bind(userId, minKeepSeq),
        env.DB.prepare(
          `DELETE FROM user_sync_ops WHERE user_id = ?1 AND seq < ?2`
        ).bind(userId, Math.max(1, compactSeq - 200)),
      ]);

      return jsonResponse(
        {
          ok: true,
          compacted: true,
          revision: compactSeq,
          updatedAt: nowIso,
        },
        200,
        origin
      );
    }

    // Proteção estrita contra sobrescrita e perda de dados (Concorrência Optimista)
    const baseRevHeader = request.headers.get("X-OpenMoney-Base-Revision");
    let clientBaseRev = 0;
    if (baseRevHeader !== null && baseRevHeader !== undefined) {
      clientBaseRev = parseInt(baseRevHeader, 10);
      if (!isNaN(clientBaseRev) && currentRev > clientBaseRev && !isForce) {
        return jsonResponse(
          {
            error: `Conflito de sincronização: existe uma versão mais recente na nuvem (r${currentRev} vs r${clientBaseRev}). Sincronize antes de sobrescrever.`,
            conflict: true,
            currentRevision: currentRev,
            clientRevision: clientBaseRev,
          },
          409,
          origin
        );
      }
    }

    const nextRev = Math.max(currentRev, isNaN(clientBaseRev) ? 0 : clientBaseRev) + 1;
    const nowIso = new Date().toISOString();
    const tzOffset = extractTzOffsetMinutes(request, url);

    await saveEncryptedPayloadToD1(
      env.DB,
      userId,
      nextRev,
      encryptedPayload,
      prefsStr,
      nowIso,
      tzOffset,
      sizeBytes,
      false
    );

    await env.DB.batch([
      env.DB.prepare(
        `DELETE FROM user_sync_records WHERE user_id = ?1`
      ).bind(userId),
      env.DB.prepare(
        `INSERT INTO user_sync_meta (user_id, seq, base_seq, snapshot_seq, updated_at)
         VALUES (?1, ?2, ?2, ?2, ?3)
         ON CONFLICT(user_id) DO UPDATE SET
           seq = excluded.seq,
           base_seq = excluded.base_seq,
           snapshot_seq = excluded.snapshot_seq,
           updated_at = excluded.updated_at`
      ).bind(userId, nextRev, nowIso),
    ]);

    if (typeof context.waitUntil === "function") {
      context.waitUntil(
        notifyDurableObjectSync(env, userId, {
          seq: nextRev,
          reset: true,
          changes: [],
        })
      );
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
  // 6. GET /api/backups (Lista os snapshots automáticos do próprio usuário)
  // ==========================================================================
  if (path === "/api/backups" && request.method === "GET") {
    const tzOffset = extractTzOffsetMinutes(request, url);
    await ensurePeriodicCloudBackupFromCurrentDb(
      env.DB,
      userId,
      new Date().toISOString(),
      tzOffset
    );

    const res = await env.DB.prepare(
      `SELECT id, backup_date, revision, size_bytes, created_at
       FROM user_database_backups
       WHERE user_id = ?1
       ORDER BY created_at DESC, backup_date DESC
       LIMIT 30`
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

    try {
      await loadEncryptedPayloadFromD1(env.DB, userId, backupRow.payload);
    } catch (chunkErr) {
      return jsonResponse(
        {
          error: `Não foi possível restaurar este backup porque seus blocos foram substituídos anteriormente (${chunkErr.message}). Tente restaurar outro snapshot ou importar seu arquivo .json.`,
        },
        422,
        origin
      );
    }

    const meta = await ensureUserSyncMeta(env.DB, userId);
    const current = await env.DB.prepare(
      "SELECT revision FROM user_databases WHERE user_id = ?1"
    )
      .bind(userId)
      .first();
    const nextRev =
      Math.max(meta.seq, current ? Number(current.revision || 1) : 1) + 1;
    const nowIso = new Date().toISOString();

    await env.DB.batch([
      env.DB.prepare(
        `UPDATE user_databases SET revision = ?1, payload = ?2, updated_at = ?3 WHERE user_id = ?4`
      ).bind(nextRev, backupRow.payload, nowIso, userId),
      env.DB.prepare(
        `DELETE FROM user_sync_records WHERE user_id = ?1`
      ).bind(userId),
      env.DB.prepare(
        `UPDATE user_sync_meta SET seq = ?1, base_seq = ?1, snapshot_seq = ?1, updated_at = ?2 WHERE user_id = ?3`
      ).bind(nextRev, nowIso, userId),
    ]);

    if (typeof context.waitUntil === "function") {
      context.waitUntil(
        notifyDurableObjectSync(env, userId, {
          seq: nextRev,
          reset: true,
          changes: [],
        })
      );
    }

    return jsonResponse(
      {
        ok: true,
        revision: nextRev,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 7b. GET /api/audit-logs (Busca logs de auditoria do próprio usuário)
  // ==========================================================================
  if (path === "/api/audit-logs" && request.method === "GET") {
    const rawLimit = Number(url.searchParams.get("limit") || 500);
    const limit = Math.min(Math.max(rawLimit, 1), 1000);

    const res = await env.DB.prepare(
      `SELECT id, action, entity, target_id, summary, details, created_at
       FROM user_audit_logs
       WHERE user_id = ?1
       ORDER BY created_at DESC
       LIMIT ?2`
    )
      .bind(userId, limit)
      .all();

    const logs = ((res && res.results) || []).map((row) => {
      let parsedDetails = null;
      if (row.details) {
        try {
          parsedDetails = JSON.parse(row.details);
        } catch (_) {}
      }
      return {
        id: row.target_id || row.id,
        action: row.action,
        entity: row.entity,
        summary: row.summary,
        details: parsedDetails,
        ts: row.created_at,
      };
    });

    return jsonResponse({ ok: true, logs }, 200, origin);
  }

  // ==========================================================================
  // 7c. POST /api/audit-logs (Registra entradas de log de auditoria no D1)
  // ==========================================================================
  if (path === "/api/audit-logs" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return jsonResponse({ error: "JSON inválido." }, 400, origin);
    }

    const rawList = Array.isArray(body.logs)
      ? body.logs
      : body.log
      ? [body.log]
      : [];

    if (rawList.length === 0) {
      return jsonResponse({ ok: true, count: 0 }, 200, origin);
    }

    const statements = [];
    const nowIso = new Date().toISOString();

    for (const item of rawList.slice(0, 100)) {
      if (!item || typeof item !== "object") continue;
      const logId = `aud_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
      const action = String(item.action || "create").trim();
      const entity = String(item.entity || "transaction").trim();
      const targetId = item.id ? String(item.id) : null;
      const summary = String(item.summary || "").trim();
      const detailsStr =
        item.details && typeof item.details === "object"
          ? JSON.stringify(item.details)
          : null;
      const ts = String(item.ts || nowIso);

      statements.push(
        env.DB.prepare(
          `INSERT INTO user_audit_logs (id, user_id, action, entity, target_id, summary, details, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`
        ).bind(logId, userId, action, entity, targetId, summary, detailsStr, ts)
      );
    }

    if (statements.length > 0) {
      // Retenção de segurança de 30 dias: expurga registros anteriores
      const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
      statements.push(
        env.DB.prepare(
          `DELETE FROM user_audit_logs WHERE user_id = ?1 AND created_at < ?2`
        ).bind(userId, cutoff)
      );
      await env.DB.batch(statements);
    }

    return jsonResponse({ ok: true, count: statements.length }, 200, origin);
  }

  // ==========================================================================
  // 8. POST /api/db/delete ou DELETE /api/db (Exclui base existente ou conta completa)
  // ==========================================================================
  if (
    (path === "/api/db/delete" && request.method === "POST") ||
    (path === "/api/db" && request.method === "DELETE")
  ) {
    let body = {};
    try {
      body = await request.json();
    } catch (_) {}

    const confirmWord = String(body.confirm || "")
      .trim()
      .toUpperCase();
    if (confirmWord !== "EXCLUIR") {
      return jsonResponse(
        {
          error:
            "Confirmação de segurança obrigatória: digite EXCLUIR para prosseguir.",
        },
        400,
        origin
      );
    }

    const mode = String(body.mode || "db_only").trim();

    // 1. Obtém dados do usuário e base para gerar backup preventivo imutável por e-mail
    const userRow = await env.DB.prepare(
      "SELECT name, email FROM users WHERE id = ?1"
    )
      .bind(userId)
      .first();

    const targetEmail = (userRow && userRow.email) || claims.email;
    const targetName = (userRow && userRow.name) || claims.name || "";

    let backupZipBase64 = null;
    let hasBackupData = false;

    try {
      const dbRow = await env.DB.prepare(
        "SELECT payload FROM user_databases WHERE user_id = ?1"
      )
        .bind(userId)
        .first();

      if (dbRow && dbRow.payload) {
        const fullEncrypted = await loadEncryptedPayloadFromD1(
          env.DB,
          userId,
          dbRow.payload
        );
        const decryptedJson = await decryptUserPayload(
          fullEncrypted,
          userId,
          env
        );
        if (decryptedJson && decryptedJson.length > 20) {
          const zipBytes = createSingleFileZip(
            "openmoney.json",
            encoder.encode(decryptedJson)
          );
          backupZipBase64 = bytesToBase64(zipBytes);
          hasBackupData = true;
        }
      }
    } catch (e) {
      console.warn("Não foi possível gerar backup pré-exclusão para e-mail:", e.message);
    }

    if (mode === "full_account") {
      let emailDispatched = false;
      // Envia e-mail notificando a exclusão definitiva da conta e com o backup .zip ANTES de apagar
      if (targetEmail) {
        try {
          const htmlText = buildAccountDeletionEmailHtml({
            name: targetName,
            email: targetEmail,
            mode: "full_account",
            hasBackupAttachment: hasBackupData,
          });
          const attachments = hasBackupData && backupZipBase64
            ? [
                {
                  filename: "openmoney-backup-pre-exclusao.zip",
                  content: backupZipBase64,
                },
              ]
            : [];
          await sendResendEmail({
            env,
            to: targetEmail,
            subject: "OpenMoney: Confirmação de Exclusão da Conta e Backup de Segurança",
            htmlText,
            attachments,
          });
          emailDispatched = true;
        } catch (mailErr) {
          console.warn("Falha no disparo do e-mail de exclusão:", mailErr.message);
        }
      }

      await env.DB.batch([
        env.DB.prepare(
          `DELETE FROM user_sync_records WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_sync_ops WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_sync_meta WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_database_chunks WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_database_backups WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_audit_logs WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_ai_usage WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(
          `DELETE FROM user_databases WHERE user_id = ?1`
        ).bind(userId),
        env.DB.prepare(`DELETE FROM users WHERE id = ?1`).bind(userId),
      ]);

      return jsonResponse(
        {
          ok: true,
          deletedAccount: true,
          backupEmailed: emailDispatched,
        },
        200,
        origin
      );
    }

    // Modo db_only: apaga todos os lançamentos/blocos/backups da nuvem e recria base limpa v7
    const meta = await ensureUserSyncMeta(env.DB, userId);
    const nextRev = meta.seq + 1;
    const nowIso = new Date().toISOString();
    const freshPayload = await encryptUserPayload(
      JSON.stringify(defaultOpenMoneyV7Payload()),
      userId,
      env
    );

    await env.DB.batch([
      env.DB.prepare(
        `DELETE FROM user_sync_records WHERE user_id = ?1`
      ).bind(userId),
      env.DB.prepare(
        `DELETE FROM user_sync_ops WHERE user_id = ?1`
      ).bind(userId),
      env.DB.prepare(
        `INSERT INTO user_sync_meta (user_id, seq, base_seq, snapshot_seq, updated_at)
         VALUES (?1, ?2, ?2, ?2, ?3)
         ON CONFLICT(user_id) DO UPDATE SET
           seq = excluded.seq,
           base_seq = excluded.base_seq,
           snapshot_seq = excluded.snapshot_seq,
           updated_at = excluded.updated_at`
      ).bind(userId, nextRev, nowIso),
      env.DB.prepare(
        `DELETE FROM user_database_chunks WHERE user_id = ?1`
      ).bind(userId),
      env.DB.prepare(
        `DELETE FROM user_database_backups WHERE user_id = ?1`
      ).bind(userId),
      env.DB.prepare(
        `INSERT INTO user_databases (user_id, schema_version, revision, payload, preferences, updated_at)
         VALUES (?1, 7, ?2, ?3, '{}', ?4)
         ON CONFLICT(user_id) DO UPDATE SET
           schema_version = 7,
           revision = excluded.revision,
           payload = excluded.payload,
           updated_at = excluded.updated_at`
      ).bind(userId, nextRev, freshPayload, nowIso),
    ]);

    if (typeof context.waitUntil === "function") {
      context.waitUntil(
        notifyDurableObjectSync(env, userId, {
          seq: nextRev,
          reset: true,
          changes: [],
        })
      );
    }

    // Envia e-mail notificando a reinicialização da base e com o backup .zip
    let emailDispatched = false;
    if (targetEmail) {
      try {
        const htmlText = buildAccountDeletionEmailHtml({
          name: targetName,
          email: targetEmail,
          mode: "db_only",
          hasBackupAttachment: hasBackupData,
        });
        const attachments = hasBackupData && backupZipBase64
          ? [
              {
                filename: "openmoney-backup-pre-exclusao.zip",
                content: backupZipBase64,
              },
            ]
          : [];
        await sendResendEmail({
          env,
          to: targetEmail,
          subject: "OpenMoney: Confirmação de Exclusão da Base e Backup de Segurança",
          htmlText,
          attachments,
        });
        emailDispatched = true;
      } catch (mailErr) {
        console.warn("Falha no disparo do e-mail de exclusão de base:", mailErr.message);
      }
    }

    return jsonResponse(
      {
        ok: true,
        deletedAccount: false,
        revision: nextRev,
        backupEmailed: emailDispatched,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 9. GET /api/ai/capabilities & POST /api/ai/chat (Assistente IA & Proxy CORS)
  // ==========================================================================
  if (path === "/api/ai/capabilities" && request.method === "GET") {
    const managedProviders = [];
    if (env.AI_MANAGED_OPENROUTER_KEY) managedProviders.push("openrouter");
    if (env.AI_MANAGED_GEMINI_KEY) managedProviders.push("gemini");
    if (env.AI_MANAGED_ANTHROPIC_KEY) managedProviders.push("claude");
    if (env.AI_MANAGED_OPENAI_KEY) managedProviders.push("openai");

    const dailyLimit = Math.max(1, Number(env.AI_DAILY_LIMIT || 25));
    const todayIso = new Date().toISOString().substring(0, 10);
    const usageRow = await env.DB.prepare(
      "SELECT request_count FROM user_ai_usage WHERE user_id = ?1 AND usage_date = ?2"
    )
      .bind(userId, todayIso)
      .first();

    return jsonResponse(
      {
        ok: true,
        managedAvailable: managedProviders.length > 0,
        managedProviders,
        dailyLimit,
        usedToday: usageRow ? Number(usageRow.request_count || 0) : 0,
      },
      200,
      origin
    );
  }

  if (path === "/api/ai/chat" && request.method === "POST") {
    let body = {};
    try {
      body = await request.json();
    } catch (_) {
      return jsonResponse({ error: "Payload JSON inválido." }, 400, origin);
    }

    const provider = String(
      body.provider || request.headers.get("X-OpenMoney-AI-Provider") || "openrouter"
    )
      .trim()
      .toLowerCase();
    const useManaged = body.useManaged === true;
    const systemPrompt = String(body.systemPrompt || "").trim();
    const userPrompt = String(body.userPrompt || "").trim();
    const preferredModel = String(body.model || "").trim();
    const attachment =
      body.attachment && typeof body.attachment === "object"
        ? body.attachment
        : null;

    if (!userPrompt) {
      return jsonResponse(
        { error: "Informe a mensagem para a Assistente." },
        400,
        origin
      );
    }

    let apiKey = "";
    if (useManaged) {
      if (provider === "openrouter") apiKey = String(env.AI_MANAGED_OPENROUTER_KEY || "").trim();
      else if (provider === "gemini") apiKey = String(env.AI_MANAGED_GEMINI_KEY || "").trim();
      else if (provider === "claude") apiKey = String(env.AI_MANAGED_ANTHROPIC_KEY || "").trim();
      else if (provider === "openai") apiKey = String(env.AI_MANAGED_OPENAI_KEY || "").trim();

      if (!apiKey) {
        return jsonResponse(
          {
            error:
              "O provedor gerenciado solicitado não está ativo neste servidor. Configure sua própria chave (BYOK) ou use o Modo Sem Chave.",
          },
          400,
          origin
        );
      }

      const dailyLimit = Math.max(1, Number(env.AI_DAILY_LIMIT || 25));
      const todayIso = new Date().toISOString().substring(0, 10);
      const usageRow = await env.DB.prepare(
        "SELECT request_count FROM user_ai_usage WHERE user_id = ?1 AND usage_date = ?2"
      )
        .bind(userId, todayIso)
        .first();
      const usedToday = usageRow ? Number(usageRow.request_count || 0) : 0;

      if (usedToday >= dailyLimit) {
        return jsonResponse(
          {
            error: `Limite diário de ${dailyLimit} consultas gratuitas atingido. Configure sua própria chave de API ou aguarde a renovação diária.`,
          },
          429,
          origin
        );
      }

      await env.DB.prepare(
        `INSERT INTO user_ai_usage (user_id, usage_date, request_count)
         VALUES (?1, ?2, 1)
         ON CONFLICT(user_id, usage_date) DO UPDATE SET
           request_count = user_ai_usage.request_count + 1`
      )
        .bind(userId, todayIso)
        .run();
    } else {
      apiKey = String(request.headers.get("X-OpenMoney-AI-Key") || "").trim();
      if (!apiKey) {
        return jsonResponse(
          { error: "Chave de API não fornecida no cabeçalho X-OpenMoney-AI-Key." },
          401,
          origin
        );
      }
    }

    let replyText = null;

    if (provider === "claude") {
      const model = preferredModel || "claude-3-7-sonnet-latest";
      const contentBlocks = [];
      if (attachment && attachment.data) {
        const mime = String(attachment.mimeType || "image/jpeg");
        contentBlocks.push({
          type: mime === "application/pdf" ? "document" : "image",
          source: {
            type: "base64",
            media_type: mime,
            data: String(attachment.data),
          },
        });
      }
      contentBlocks.push({ type: "text", text: userPrompt });

      const upstream = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model,
          max_tokens: 2048,
          temperature: 0.15,
          system: systemPrompt,
          messages: [{ role: "user", content: contentBlocks }],
        }),
      });
      if (!upstream.ok) {
        return jsonResponse(
          { error: `Erro no provedor Claude (HTTP ${upstream.status}).` },
          upstream.status,
          origin
        );
      }
      const data = await upstream.json();
      const firstBlock =
        Array.isArray(data.content) &&
        data.content.find((b) => b && b.type === "text" && b.text);
      replyText = firstBlock ? String(firstBlock.text).trim() : null;
    } else if (provider === "openrouter") {
      const candidateModels = [];
      if (preferredModel && preferredModel.trim()) candidateModels.push(preferredModel.trim());
      candidateModels.push(
        "google/gemini-2.0-flash-001",
        "google/gemini-2.0-flash-exp:free",
        "deepseek/deepseek-chat",
        "meta-llama/llama-3.3-70b-instruct:free",
        "mistralai/mistral-small-24b-instruct-2501:free"
      );

      const userContent = [{ type: "text", text: userPrompt }];
      if (
        attachment &&
        attachment.data &&
        String(attachment.mimeType || "").startsWith("image/")
      ) {
        userContent.push({
          type: "image_url",
          image_url: {
            url: `data:${attachment.mimeType};base64,${attachment.data}`,
          },
        });
      }

      let lastError = null;
      let lastStatus = 502;

      for (const m of candidateModels) {
        try {
          const upstream = await fetch(
            "https://openrouter.ai/api/v1/chat/completions",
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json; charset=utf-8",
                "Authorization": `Bearer ${apiKey}`,
                "HTTP-Referer": "https://openmoney.app.br",
                "X-Title": "OpenMoney",
              },
              body: JSON.stringify({
                model: m,
                temperature: 0.15,
                response_format: { type: "json_object" },
                messages: [
                  { role: "system", content: systemPrompt },
                  { role: "user", content: userContent },
                ],
              }),
            }
          );
          if (!upstream.ok) {
            let errText = `HTTP ${upstream.status}`;
            try {
              const errJson = await upstream.json();
              if (errJson && errJson.error && errJson.error.message) {
                errText = errJson.error.message;
              }
            } catch (_) {}
            lastError = `Erro no provedor OpenRouter (${m}): ${errText}`;
            lastStatus = upstream.status;
            continue;
          }
          const data = await upstream.json();
          replyText =
            data &&
            Array.isArray(data.choices) &&
            data.choices[0] &&
            data.choices[0].message &&
            data.choices[0].message.content
              ? String(data.choices[0].message.content).trim()
              : null;
          if (replyText) break;
        } catch (e) {
          lastError = `Falha na requisição OpenRouter (${m}): ${e && e.message ? e.message : String(e)}`;
          continue;
        }
      }

      if (!replyText && lastError) {
        return jsonResponse(
          { error: lastError },
          lastStatus,
          origin
        );
      }
    } else if (provider === "openai") {
      const model = preferredModel || "gpt-4o-mini";
      const userContent = [{ type: "text", text: userPrompt }];
      if (
        attachment &&
        attachment.data &&
        String(attachment.mimeType || "").startsWith("image/")
      ) {
        userContent.push({
          type: "image_url",
          image_url: {
            url: `data:${attachment.mimeType};base64,${attachment.data}`,
          },
        });
      }

      const upstream = await fetch(
        "https://api.openai.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            model,
            temperature: 0.15,
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: systemPrompt },
              { role: "user", content: userContent },
            ],
          }),
        }
      );
      if (!upstream.ok) {
        return jsonResponse(
          { error: `Erro no provedor OpenAI (HTTP ${upstream.status}).` },
          upstream.status,
          origin
        );
      }
      const data = await upstream.json();
      replyText =
        data &&
        Array.isArray(data.choices) &&
        data.choices[0] &&
        data.choices[0].message &&
        data.choices[0].message.content
          ? String(data.choices[0].message.content).trim()
          : null;
    } else {
      const candidateModels = [];
      if (preferredModel && preferredModel.trim()) candidateModels.push(preferredModel.trim());
      candidateModels.push("gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-flash-latest", "gemini-flash-latest");

      const parts = [
        { text: `${systemPrompt}\n\nPEDIDO DO USUÁRIO:\n${userPrompt}` },
      ];
      if (attachment && attachment.data) {
        parts.push({
          inline_data: {
            mime_type: String(attachment.mimeType || "image/jpeg"),
            data: String(attachment.data),
          },
        });
      }

      let lastError = null;
      let lastStatus = 502;

      for (const m of candidateModels) {
        try {
          const upstream = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
              m
            )}:generateContent?key=${encodeURIComponent(apiKey)}`,
            {
              method: "POST",
              headers: { "Content-Type": "application/json; charset=utf-8" },
              body: JSON.stringify({
                contents: [{ parts }],
                generationConfig: {
                  temperature: 0.15,
                  response_mime_type: "application/json",
                },
              }),
            }
          );
          if (!upstream.ok) {
            let errText = `HTTP ${upstream.status}`;
            try {
              const errJson = await upstream.json();
              if (errJson && errJson.error && errJson.error.message) {
                errText = errJson.error.message;
              }
            } catch (_) {}
            lastError = `Erro no provedor Gemini (${m}): ${errText}`;
            lastStatus = upstream.status;
            continue;
          }
          const data = await upstream.json();
          replyText =
            data &&
            Array.isArray(data.candidates) &&
            data.candidates[0] &&
            data.candidates[0].content &&
            Array.isArray(data.candidates[0].content.parts) &&
            data.candidates[0].content.parts[0] &&
            data.candidates[0].content.parts[0].text
              ? String(data.candidates[0].content.parts[0].text).trim()
              : null;
          if (replyText) {
            break;
          }
        } catch (e) {
          lastError = `Falha na requisição Gemini (${m}): ${e && e.message ? e.message : String(e)}`;
          continue;
        }
      }

      if (!replyText && lastError) {
        return jsonResponse(
          { error: lastError },
          lastStatus,
          origin
        );
      }
    }

    if (!replyText) {
      return jsonResponse(
        { error: "Resposta vazia do provedor de IA." },
        502,
        origin
      );
    }

    return jsonResponse(
      {
        ok: true,
        provider,
        text: replyText,
      },
      200,
      origin
    );
  }

  // ==========================================================================
  // 10.1 GET /api/tokens (Lista os Personal Access Tokens do usuário)
  // ==========================================================================
  if (path === "/api/tokens" && request.method === "GET") {
    const rows = await env.DB.prepare(
      `SELECT id, name, token_prefix, permissions, last_used_at, created_at
       FROM user_api_tokens
       WHERE user_id = ?1
       ORDER BY created_at DESC`
    )
      .bind(userId)
      .all();
    return jsonResponse(
      { ok: true, tokens: (rows && rows.results) || [] },
      200,
      origin
    );
  }

  // ==========================================================================
  // 10.2 POST /api/tokens (Cria um novo Personal Access Token para MCP / API)
  // ==========================================================================
  if (path === "/api/tokens" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const name = String(body.name || "Token MCP").trim();
    const permissions =
      body.permissions === "read_only" ? "read_only" : "read_write";

    const rawBytes = new Uint8Array(24);
    crypto.getRandomValues(rawBytes);
    const tokenStr =
      "opm_live_" +
      Array.from(rawBytes)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    const tokenPrefix = tokenStr.slice(0, 14) + "..." + tokenStr.slice(-4);
    const tokenHash = await sha256Hex(tokenStr);
    const tokenId =
      "tok_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7);
    const nowIso = new Date().toISOString();

    await env.DB.prepare(
      `INSERT INTO user_api_tokens (id, user_id, name, token_hash, token_prefix, permissions, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`
    )
      .bind(tokenId, userId, name, tokenHash, tokenPrefix, permissions, nowIso)
      .run();

    return jsonResponse(
      {
        ok: true,
        id: tokenId,
        name,
        token: tokenStr,
        token_prefix: tokenPrefix,
        permissions,
        created_at: nowIso,
      },
      201,
      origin
    );
  }

  // ==========================================================================
  // 10.3 DELETE /api/tokens/:id ou POST /api/tokens/delete (Revoga token)
  // ==========================================================================
  if (
    (path.startsWith("/api/tokens/") && request.method === "DELETE") ||
    (path === "/api/tokens/delete" && request.method === "POST")
  ) {
    let tokenId = "";
    if (path.startsWith("/api/tokens/")) {
      tokenId = path.replace("/api/tokens/", "").trim();
    } else {
      const body = await request.json().catch(() => ({}));
      tokenId = String(body.id || body.tokenId || "").trim();
    }
    if (!tokenId) {
      return jsonResponse({ error: "ID do token não informado." }, 400, origin);
    }

    await env.DB.prepare(
      `DELETE FROM user_api_tokens WHERE id = ?1 AND user_id = ?2`
    )
      .bind(tokenId, userId)
      .run();

    return jsonResponse({ ok: true, deleted: tokenId }, 200, origin);
  }

  // ==========================================================================
  // 11.1 GET /api/mcp/sse (Transporte MCP Server-Sent Events)
  // ==========================================================================
  if (path === "/api/mcp/sse" && request.method === "GET") {
    if (!env.SYNC) {
      return jsonResponse(
        { error: "Durable Object de sincronização não vinculado." },
        503,
        origin
      );
    }
    const doId = env.SYNC.idFromName(userId);
    const stub = env.SYNC.get(doId);
    return stub.fetch(request);
  }

  // ==========================================================================
  // 11.2 POST /api/mcp/messages (Mensagens JSON-RPC para sessão SSE ativa)
  // ==========================================================================
  if (path === "/api/mcp/messages" && request.method === "POST") {
    const sessionId = url.searchParams.get("sessionId");
    const body = await request.json().catch(() => ({}));
    const rpcResponse = await handleJsonRpcRequest(
      body,
      {
        userId,
        permissions: claims.permissions || "read_write",
        tokenId: claims.tokenId || null,
      },
      env,
      origin,
      sessionId
    );

    if (sessionId && env.SYNC) {
      if (rpcResponse) {
        const doId = env.SYNC.idFromName(userId);
        const stub = env.SYNC.get(doId);
        await stub.fetch("https://sync.internal/mcp/send", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ sessionId, message: rpcResponse }),
        });
      }
      return new Response(null, { status: 202, headers: corsHeaders(origin) });
    }

    return jsonResponse(
      rpcResponse || { jsonrpc: "2.0", id: body.id, result: {} },
      200,
      origin
    );
  }

  // ==========================================================================
  // 11.3 POST, GET, HEAD & DELETE /api/mcp (Transporte MCP Streamable HTTP Oficial)
  // ==========================================================================
  if (path === "/api/mcp") {
    const originalPath = request.headers.get("X-OpenMoney-Original-Path") || path;
    const mcpProtocol = request.headers.get("MCP-Protocol-Version") || "2025-03-26";
    const sessionId =
      request.headers.get("Mcp-Session-Id") || `opm-sess-${userId.slice(0, 12)}`;
    const baseHeaders = {
      ...corsHeaders(origin, true),
      "MCP-Protocol-Version": mcpProtocol,
      "Mcp-Session-Id": sessionId,
    };

    if (request.method === "HEAD") {
      await logMcpDiagnostic(env, request, originalPath, 200, "MCP HEAD");
      return new Response(null, {
        status: 200,
        headers: baseHeaders,
      });
    }

    if (request.method === "DELETE") {
      await logMcpDiagnostic(env, request, originalPath, 200, "MCP DELETE session");
      return new Response(null, {
        status: 200,
        headers: baseHeaders,
      });
    }

    if (request.method === "GET") {
      const accept = request.headers.get("Accept") || "";
      // Pela especificação oficial MCP Streamable HTTP (Sec. 3.3):
      // Servidores que operam via POST e não mantêm stream SSE reverso DEVEM retornar 405
      // Method Not Allowed ao receber GET SSE. Isso instrui clientes como Gemini a
      // operar em modo request-response sobre POST sem aguardar timeout de SSE.
      if (accept.includes("text/event-stream")) {
        await logMcpDiagnostic(
          env,
          request,
          originalPath,
          405,
          `MCP GET 405 accept=${accept}`
        );
        return new Response(
          JSON.stringify({
            error: "Method Not Allowed",
            message:
              "Server-initiated streaming is not supported. Use HTTP POST for JSON-RPC messages.",
          }),
          {
            status: 405,
            headers: {
              ...baseHeaders,
              "Allow": "POST, DELETE, OPTIONS, HEAD",
              "Content-Type": "application/json; charset=utf-8",
            },
          }
        );
      }

      await logMcpDiagnostic(env, request, originalPath, 200, `MCP GET accept=${accept}`);
      return new Response(
        JSON.stringify({
          name: "openmoney-cloud",
          version: "2.5.4",
          protocolVersion: "2025-03-26",
          transport: "http",
          status: "ready",
          description: "OpenMoney Cloud MCP Server (Streamable HTTP + OAuth 2.1)",
        }),
        {
          status: 200,
          headers: { ...baseHeaders, "Content-Type": "application/json; charset=utf-8" },
        }
      );
    }

    if (request.method === "POST") {
      const accept = request.headers.get("Accept") || "";
      const body = await request.json().catch(() => ({}));
      const rpcMethod = Array.isArray(body)
        ? body.map((b) => b?.method).join(",")
        : body?.method || "unknown";
      const rpcResponse = await handleJsonRpcRequest(
        body,
        {
          userId,
          permissions: claims.permissions || "read_write",
          tokenId: claims.tokenId || null,
        },
        env,
        origin,
        null
      );

      if (rpcResponse?.result?.protocolVersion) {
        baseHeaders["MCP-Protocol-Version"] = rpcResponse.result.protocolVersion;
      }

      // Notificação (ex: notifications/initialized) -> 202 Accepted
      if (!rpcResponse) {
        await logMcpDiagnostic(
          env,
          request,
          originalPath,
          202,
          `MCP POST notif=${rpcMethod} accept=${accept}`
        );
        return new Response(null, {
          status: 202,
          headers: baseHeaders,
        });
      }

      await logMcpDiagnostic(
        env,
        request,
        originalPath,
        200,
        `MCP POST method=${rpcMethod} ver=${body?.params?.protocolVersion || mcpProtocol} accept=${accept}`
      );

      // Se o cliente aceitar apenas text/event-stream e não application/json
      if (accept.includes("text/event-stream") && !accept.includes("application/json")) {
        const sseData = `event: message\ndata: ${JSON.stringify(rpcResponse)}\n\n`;
        return new Response(sseData, {
          status: 200,
          headers: {
            ...baseHeaders,
            "Content-Type": "text/event-stream; charset=utf-8",
            "Cache-Control": "no-cache, no-transform",
          },
        });
      }

      // Resposta padrão JSON-RPC sobre Streamable HTTP
      return new Response(JSON.stringify(rpcResponse), {
        status: 200,
        headers: {
          ...baseHeaders,
          "Content-Type": "application/json; charset=utf-8",
        },
      });
    }
  }

  // ==========================================================================
  // 12. REST Tools Endpoints para ChatGPT Actions / OpenAPI / Gemini
  // ==========================================================================
  if (path.startsWith("/api/v1/tools/")) {
    let toolName = path.replace("/api/v1/tools/", "").trim();
    if (!toolName.startsWith("openmoney_")) {
      toolName = "openmoney_" + toolName;
    }

    let toolArgs = {};
    if (request.method === "GET") {
      for (const [key, value] of url.searchParams.entries()) {
        toolArgs[key] = value;
      }
    } else if (request.method === "POST") {
      toolArgs = await request.json().catch(() => ({}));
    }

    try {
      const result = await executeMcpTool(
        toolName,
        toolArgs,
        userId,
        claims.permissions || "read_write",
        env,
        claims.tokenId || null
      );
      return jsonResponse({ ok: true, result }, 200, origin, true);
    } catch (e) {
      return jsonResponse(
        { ok: false, error: e && e.message ? e.message : String(e) },
        400,
        origin,
        true
      );
    }
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
