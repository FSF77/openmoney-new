-- ============================================================================
-- OpenMoney Cloud — Cloudflare D1 Database Schema (Multi-User Isolated v7)
-- ============================================================================

-- 1. Tabela de Usuários (Login/Senha com PBKDF2-HMAC-SHA256 + Lockout Anti-Brute-Force)
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
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 2. Base Principal openmoney.json (Schema v7) Criptografada (AES-256-GCM) por Usuário
CREATE TABLE IF NOT EXISTS user_databases (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  schema_version INTEGER NOT NULL DEFAULT 7,
  revision INTEGER NOT NULL DEFAULT 1,
  payload TEXT NOT NULL,
  preferences TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL
);

-- 2b. Blocos de 380KB para Bases Grandes (>10MB) respeitando o limite de 1MB por instrução SQL do D1
CREATE TABLE IF NOT EXISTS user_database_chunks (
  user_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  chunk_data TEXT NOT NULL,
  PRIMARY KEY (user_id, chunk_index)
);

-- 3. Backups Diários Automáticos na Nuvem (Isolados e Criptografados por Usuário)
CREATE TABLE IF NOT EXISTS user_database_backups (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  backup_date TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (user_id, backup_date)
);

CREATE INDEX IF NOT EXISTS idx_backups_user_date ON user_database_backups(user_id, backup_date DESC);

-- 4. Tokens de Recuperação de Senha (com Lockout Anti-Brute-Force após 5 tentativas)
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  email TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  used INTEGER NOT NULL DEFAULT 0
);

-- 5. Tokens de Confirmação de Cadastro e Troca de E-mail (com Lockout Anti-Brute-Force)
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
);

CREATE INDEX IF NOT EXISTS idx_email_verification_tokens ON email_verification_tokens (email, type, used);

-- 6. Metadados de Sincronização em Tempo Real (Sync v2 Granular)
CREATE TABLE IF NOT EXISTS user_sync_meta (
  user_id TEXT PRIMARY KEY,
  seq INTEGER NOT NULL DEFAULT 1,
  base_seq INTEGER NOT NULL DEFAULT 1,
  snapshot_seq INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
);

-- 7. Registros Granulares Criptografados por Usuário
CREATE TABLE IF NOT EXISTS user_sync_records (
  user_id TEXT NOT NULL,
  coll TEXT NOT NULL,
  record_id TEXT NOT NULL,
  encrypted_data TEXT,
  deleted INTEGER NOT NULL DEFAULT 0,
  seq INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, coll, record_id)
);

CREATE INDEX IF NOT EXISTS idx_user_sync_records_seq ON user_sync_records (user_id, seq);

-- 8. Log de Idempotência de Operações Sync
CREATE TABLE IF NOT EXISTS user_sync_ops (
  user_id TEXT NOT NULL,
  op_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, op_id)
);

-- 9. Logs de Auditoria e Alterações por Usuário (Isolamento Estrito)
CREATE TABLE IF NOT EXISTS user_audit_logs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  entity TEXT NOT NULL,
  target_id TEXT,
  summary TEXT NOT NULL,
  details TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_user_created ON user_audit_logs (user_id, created_at DESC);
