# ADR 015: Hardening de Segurança Web, Proteção Anti-Força-Bruta D1, Isolamento de Segredos e Mitigação de Ataques

- **Status:** Aceito (Implementado e Homologado no Cloudflare Pages, Cloudflare D1 e Flutter Web)
- **Data:** 2026-11-09
- **Contexto:** Ecossistema OpenMoney (`OpenMoneyFlutter`, `functions/api/[[route]].js`, `Cloudflare D1`, `web/_headers`, `web-dist/_headers`, `cloudflare/schema.sql`)

---

## 1. Contexto e Problema

Com a publicação em produção da versão Web sincronizada em `https://openmoney.app.br` ([ADR 011](011-web-multiuser-cloudflare-architecture.md), [ADR 013](013-realtime-record-sync.md) e [ADR 014](014-desktop-hybrid-sync-audit-and-safety-backups.md)), foi realizada uma auditoria técnica de segurança e arquitetura defensiva para avaliar a resiliência dos dados financeiros dos usuários armazenados no Cloudflare D1 e a exposição dos endpoints de API.

A auditoria identificou pontos fortes e cinco superfícies de risco que demandavam tratamento imediato:

1. **Pontos Fortes Pré-Existentes:**
   - O banco SQL Cloudflare D1 é 100% privado (sem endpoints públicos na internet; acessível exclusivamente via binding interno `env.DB` nas Pages Functions).
   - Ausência total de SQL Injection: 100% das instruções utilizam *Prepared Statements* parametrizados (`.bind(?1, ?2, ...)`).
   - Isolamento de tenants estrito (Anti-BOLA/IDOR): o identificador `userId` é extraído exclusivamente das *claims* assinadas do token JWT verificado (`claims.sub`), com cláusulas `WHERE user_id = ?1` em todas as rotas protegidas.
   - Criptografia em repouso por usuário (`AES-256-GCM` com chave derivada via `HKDF-SHA256`).
   - Hash de senhas forte via `PBKDF2-HMAC-SHA256` (100.000 iterações + salt aleatório de 16 bytes) com lockout anti-brute-force no login.

2. **Vulnerabilidades e Riscos Identificados:**
   - **Risco 1 (Crítico) — Fallback Inseguro de Chave Mestra:** A função `getMasterSecret(env)` continha uma string padrão de fallback (`"openmoney-cloudflare-default-master-key-change-in-dashboard-v1"`). Caso as variáveis de ambiente `MASTER_SECRET` ou `JWT_SECRET` não estivessem configuradas no painel do Cloudflare Pages, o servidor utilizava esse segredo conhecido no repositório público, permitindo a forja de tokens e decodificação de bases.
   - **Risco 2 (Alto) — Força Bruta nos Códigos de 6 Dígitos (PINs):** Os códigos de recuperação de senha, confirmação de cadastro e alteração de e-mail continham 6 dígitos (900.000 combinações) e validade de 15 minutos, mas **não registravam tentativas falhas**. Um atacante que conhecesse o e-mail da vítima poderia automatizar requisições e descobrir o código antes do término da vigência.
   - **Risco 3 (Médio) — Ausência de Cooldown/Rate-Limiting no Envio de E-mails (Resend):** Usuários podiam solicitar reenvio contínuo de e-mails em loop nas rotas `/api/auth/forgot-password`, `/api/auth/register-request` e `/api/auth/change-email-request`, gerando risco de *Email Bombing* na vítima e esgotamento da cota de envio na Resend.
   - **Risco 4 (Médio) — Reflexão Insegura de CORS:** A função de cabeçalhos CORS devolvia `origin || "*"`, aceitando requisições com cabeçalhos arbitrários de qualquer domínio terceiro da web.
   - **Risco 5 (Médio) — Cabeçalhos HTTP de Segurança Ausentes:** O arquivo `_headers` continha apenas `X-Content-Type-Options: nosniff`, deixando o aplicativo vulnerável a Clickjacking (`<iframe>`) e downgrade de conexões HTTPS.
   - **Interoperabilidade com Flutter Web:** Políticas excessivamente estritas de CSP (*Content-Security-Policy*) congelam o carregamento da aplicação se impedirem o download do motor gráfico CanvasKit WebAssembly a partir do CDN oficial da Google (`https://www.gstatic.com/flutter-canvaskit/...`) ou a criação de Web Workers via `blob:`.

---

## 2. Decisões Arquiteturais

### 2.1. Isolamento Estrito da Chave Mestra (`MASTER_SECRET`)

A função `getMasterSecret(env)` em [`functions/api/[[route]].js`](file:///Users/fabiano/Developer/OpenMoneyFlutter/functions/api/%5B%5Broute%5D%5D.js) foi refatorada para **eliminar qualquer valor padrão embutido**:

```javascript
function getMasterSecret(env) {
  const secret = (env && (env.MASTER_SECRET || env.JWT_SECRET)) || "";
  if (!secret || typeof secret !== "string" || secret.trim().length === 0) {
    throw new Error(
      "Configuração de segurança pendente: variável MASTER_SECRET não configurada no Cloudflare Pages."
    );
  }
  return secret.trim();
}
```

- **Fail-Fast no Ciclo da Requisição:** O handler `onRequest` valida a existência da `MASTER_SECRET` logo após inicializar o banco. Se a variável estiver ausente nas configurações do Cloudflare Pages, o servidor recusa a execução com HTTP 500, garantindo que o sistema **nunca opere com chaves inseguras ou expostas**.
- **Armazenamento Seguro:** A chave deve ser cadastrada diretamente na interface do Cloudflare Pages (**Settings > Variables and Secrets > Production**) com a flag **Encrypt** (Secret).

---

### 2.2. Proteção Anti-Força-Bruta nos Códigos de 6 Dígitos (PIN Lockout)

As tabelas `password_reset_tokens` e `email_verification_tokens` receberam a coluna `attempts INTEGER NOT NULL DEFAULT 0`:

```sql
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
```

- **Migração Transparente:** O método `ensureSchema` executa `ALTER TABLE ... ADD COLUMN attempts` em bloco protegido por `try-catch`, assegurando que bases D1 já em produção recebam a coluna sem necessidade de intervenção manual ou indisponibilidade.
- **Regra de 5 Tentativas Máximas:**
  1. Nas rotas `/api/auth/verify-reset-code`, `/api/auth/reset-password`, `/api/auth/register-confirm` e `/api/auth/change-email-confirm`, o token ativo mais recente é localizado por e-mail e vigência (`expires_at > now` e `used = 0`).
  2. Se `attempts >= 5`, o token é marcado como permanentemente revogado (`used = 2`) e a resposta retorna `HTTP 429 Too Many Requests`.
  3. Se o código digitado estiver incorreto (comparado com `timingSafeEqual`), o backend executa `UPDATE ... SET attempts = attempts + 1` e retorna `HTTP 400` com a contagem exata de tentativas restantes (ex: *"Código incorreto. Você tem mais 4 tentativa(s)."*).
  4. Reduz drasticamente a superfície de ataque de 900.000 tentativas para um teto estrito de 5 chutes por token de 15 minutos.

---

### 2.3. Cooldown Anti-Spam de 60 Segundos no Envio de E-mails (Resend)

Nas rotas de solicitação de código:
- `POST /api/auth/register-request`
- `POST /api/auth/forgot-password`
- `POST /api/auth/change-email-request`

O servidor consulta a data de criação do último token gerado para aquele e-mail/usuário. Se decorridos menos de 60 segundos desde a última solicitação:
```javascript
const diffSec = (Date.now() - new Date(recentToken.created_at).getTime()) / 1000;
if (diffSec >= 0 && diffSec < 60) {
  return jsonResponse(
    { error: `Aguarde ${Math.ceil(60 - diffSec)} segundo(s) antes de solicitar um novo código.` },
    429,
    origin
  );
}
```
Isso impede ataques de exaustão de cota no Resend e impede *email flood* contra caixas de entrada.

---

### 2.4. Restrição Estrita de Origens Permitidas (CORS)

A função `corsHeaders` deixou de aceitar qualquer origem refletida e passou a validar estritamente através do predicado `isAllowedOrigin(origin)`:

```javascript
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
```

- Origens não autorizadas recebem o fallback restrito de `https://openmoney.app.br`.
- Inclui o cabeçalho `Vary: Origin` para evitar envenenamento de cache em CDNs intermediárias.

---

### 2.5. Cabeçalhos HTTP de Segurança Avançados

Os arquivos [`web/_headers`](file:///Users/fabiano/Developer/OpenMoneyFlutter/web/_headers) e [`web-dist/_headers`](file:///Users/fabiano/Developer/OpenMoneyFlutter/web-dist/_headers) foram padronizados com as diretivas:

```http
# Regras de Cache e Headers HTTP de Segurança para Cloudflare Pages
/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()
  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

* **`X-Frame-Options: DENY`:** Mitiga 100% de ataques de Clickjacking ao impedir que qualquer outro domínio incorpore a aplicação web dentro de um `<iframe>` (`<iframe src="...">`).
* **`Strict-Transport-Security` (HSTS):** Força o navegador a usar HTTPS por 1 ano (31536000s), incluindo subdomínios e elegível para listas de preload.
* **`Referrer-Policy: strict-origin-when-cross-origin`:** Evita o vazamento de caminhos e parâmetros sensíveis em navegações externas.
* **`Permissions-Policy`:** Desabilita APIs de sensores, câmera, microfone e pagamentos nativos não utilizados pelo OpenMoney.
* **Compatibilidade com Flutter CanvasKit:** Como o Flutter Web compila para WebAssembly e baixa o runtime `canvaskit.js` / `canvaskit.wasm` a partir de `https://www.gstatic.com/flutter-canvaskit/...`, a diretiva de CSP não deve bloquear o CDN da Google nem a criação de workers em memória via `blob:`.

---

### 2.6. Sincronização Integral do Schema D1 (`cloudflare/schema.sql`)

O arquivo oficial [`cloudflare/schema.sql`](file:///Users/fabiano/Developer/OpenMoneyFlutter/cloudflare/schema.sql) foi atualizado para conter a totalidade das **9 tabelas** do ecossistema:

1. `users`: Login, credenciais PBKDF2 e lockout de senha.
2. `user_databases`: Base principal `openmoney.json` criptografada com AES-256-GCM.
3. `user_database_chunks`: Blocos de 380KB para bases volumosas (>10MB).
4. `user_database_backups`: Histórico de snapshots diários criptografados.
5. `password_reset_tokens`: Códigos de recuperação de senha com coluna `attempts`.
6. `email_verification_tokens`: Confirmação de cadastro e alteração de e-mail com coluna `attempts`.
7. `user_sync_meta`: Sequenciador de versões do motor Sync v2 em tempo real.
8. `user_sync_records`: Registros deltas granulares criptografados por entidade (`coll` + `record_id`).
9. `user_sync_ops`: Log de idempotência de operações de sincronização.
10. `user_audit_logs`: Logs de auditoria com retenção de 30 dias.

---

## 3. Consequências e Resultados

1. **Blindagem Contra Ataques Automatizados:**
   - Tentativas de adivinhação do código de 6 dígitos são bloqueadas após 5 erros, inutilizando scripts de ataque.
   - Tentativas contínuas de envio de e-mails são reprimidas pela barreira de 60 segundos por endereço.
2. **Eliminação de Segredos Vazados:**
   - A remoção de credenciais padrão do repositório garante conformidade com as melhores práticas OWASP de gerenciamento seguro de chaves criptográficas.
3. **Integridade de Dados e Recuperação:**
   - A base SQLite D1 opera com isolamento garantido por usuário (`AES-256-GCM` + `HKDF`), sem quebras de sessão e com compatibilidade assegurada para bases já criadas.
4. **Resiliência da Versão Web:**
   - A aplicação web em `https://openmoney.app.br` carrega instantaneamente, com segurança HTTP validada e proteção anti-clickjacking.
