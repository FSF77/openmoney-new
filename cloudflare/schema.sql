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
