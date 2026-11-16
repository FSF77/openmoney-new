# ADR 011: Arquitetura Web Multiusuário Cloudflare e Manutenção do Modo Tradicional Local no Desktop

- **Data:** 06 de Novembro de 2026 (Atualizado)
- **Status:** Aceito e Implementado *(Modo Online/Híbrido posteriormente estendido ao Desktop e Swift pelos [ADR 013](013-realtime-record-sync.md), [ADR 014](014-desktop-hybrid-sync-audit-and-safety-backups.md) e [ADR 019](019-swift-cloud-sync-v2-parity.md))*
- **Plataformas Afetadas:** OpenMoney Flutter Web (Nuvem exclusiva na fase inicial); OpenMoney Swift & Flutter Desktop (posteriormente unificados no modo híbrido Local ↔ Online)

---

## 1. Contexto e Objetivo

Para disponibilizar o **OpenMoney** em versão **Web (Navegador / PWA)** para até **50 usuários** no plano gratuito da Cloudflare (já que navegadores não possuem acesso ao sistema de arquivos local do usuário), mantendo:
1. **Login e Senha individuais** para cada usuário na Web;
2. **Isolamento estrito e criptografia por usuário** da base de dados no Cloudflare D1;
3. **Continuidade total do formato `openmoney.json` (Schema `v: 7`)**;
4. **Isolamento e Segurança Máxima no Desktop (Fase Inicial):** Na entrega inicial deste ADR, as versões Desktop (Swift macOS/iOS e Flutter macOS/Windows) operavam **estritamente no modo tradicional de arquivo local em pasta (`openmoney.json`)**, sem comunicação de rede, sem rotinas de sincronismo e sem risco de conflito ou sobrescrita acidental. *(Nota: nas etapas seguintes do ecossistema, a operação híbrida Local ↔ Online com Sync v2 foi habilitada integralmente no Desktop Flutter e no Swift macOS/iOS, conforme [ADR 013](013-realtime-record-sync.md), [ADR 014](014-desktop-hybrid-sync-audit-and-safety-backups.md) e [ADR 019](019-swift-cloud-sync-v2-parity.md).)*

---

## 2. Decisão Arquitetural

### 2.1. Hospedagem 100% na Conta Cloudflare (Pages + Pages Functions + D1)
- **Frontend (`build/web`):** Hospedado no **Cloudflare Pages** (banda e requisições estáticas ilimitadas no plano gratuito), vinculado a um subdomínio do domínio já gerenciado na Cloudflare (ex: `openmoney.suaempresa.com.br`).
- **Backend Serverless (`functions/api/[[route]].js`):** Executado via **Cloudflare Pages Functions** na mesma origem do frontend (eliminando problemas de CORS e bloqueadores).
- **Persistência (`Cloudflare D1`):** Banco SQLite distribuído da Cloudflare (5 GB gratuitos, 5 milhões de leituras/dia e 100.000 gravações/dia gratuitas; **nunca pausa por inatividade**).

### 2.2. Segurança Multicamada e Isolamento por Usuário
1. **Banco D1 100% Privado:** O banco D1 não possui endpoint público na internet; apenas a *Pages Function* interna tem permissão de leitura e escrita via *binding* `env.DB`.
2. **Senhas com `PBKDF2-HMAC-SHA256`:** Cada usuário possui um *salt* aleatório de 128 bits e hash derivado com **100.000 iterações** via `WebCrypto API`, além de bloqueio temporário automático (15 minutos) após 5 tentativas inválidas consecutivas.
3. **Isolamento por JWT (`HMAC-SHA256`):** O `user_id` (`claims.sub`) é extraído exclusivamente da assinatura criptográfica do token JWT verificado no servidor. Todas as queries no D1 filtram estritamente por `WHERE user_id = ?1`.
4. **Criptografia em Repouso por Usuário (`AES-256-GCM` + `HKDF-SHA256`):** Antes de gravar o `openmoney.json` no banco D1, o servidor deriva uma chave `AES-256-GCM` exclusiva para aquele `user_id` via `HKDF-SHA256(MASTER_SECRET, user_id)` e criptografa o documento com IV aleatório de 96 bits (`enc:v1:<iv>:<ciphertext>`).
5. **Backups Diários Automáticos na Nuvem:** A cada dia em que o usuário salva alterações, é mantido 1 snapshot criptografado na tabela `user_database_backups` (com retenção automática dos últimos 15 dias por usuário).

### 2.3. Resolução de Bases Grandes (>1MB a 12MB+) via Chunking Copy-On-Write e Self-Healing
Devido ao limite de tamanho por query do Cloudflare D1 (~1MB), bases históricas volumosas são fragmentadas de forma atômica:
- **Protocolo `chunked:v3:${batchSlot}:${totalChunks}`:** Cada envio de base gera um `batchSlot` único. Os pedaços são gravados na tabela `user_database_chunks` com a assinatura do slot.
- **Transação Copy-On-Write (COW):** O ponteiro mestre em `user_databases` só é atualizado após a persistência bem-sucedida de todos os chunks. Requisições concorrentes ou trocas rápidas de conta nunca misturam pedaços nem causam falhas de descriptografia (`Decryption failed`).
- **Self-Healing Automático:** Na leitura (`GET /api/db`), se o servidor identificar chunks órfãos ou incompletos de um slot antigo, ele busca automaticamente o último slot 100% íntegro ou o snapshot mais recente de backup, restaurando o serviço sem intervenção manual.
- **Serialização de Push no Cliente:** O `CloudSyncService` serializa requisições de salvamento (`pushDatabase`) e vincula a chamada ao token JWT da conta ativa, descartando pushes enfileirados caso o usuário alterne de conta durante uma transmissão.

### 2.4. Gestão Multi-Contas e Ciclo de Vida da Base
- **Alternância Rápida de Contas (`SavedCloudAccount`):** O cliente armazena credenciais criptografadas localmente permitindo alternar entre diferentes bases/e-mails com um único clique.
- **Cancelamento Atômico de Save Pendente (`cancelPendingSave`):** Ao alternar de conta, qualquer gravação com debounce em espera é imediatamente revogada no `MoneyStore`, evitando contaminação de dados entre perfis.
- **Criação e Exclusão Segura de Bases:**
  - `POST /api/db/delete`: Limpa atomicamente os registros nas tabelas `user_databases`, `user_database_chunks` e `user_database_backups`.
  - Exige confirmação explícita digitando `EXCLUIR` no modal de confirmação.
  - Possibilidade de inicializar uma nova base limpa mantendo a conta existente.

### 2.5. Recuperação de Senha por E-mail (Integração Resend 100% Gratuita)
Para garantir autonomia aos usuários sem comprometer a segurança:
1. **Código de Verificação de 6 Dígitos:** Ao solicitar a recuperação (`POST /api/auth/forgot-password`), o backend gera um código numérico de 6 dígitos via `crypto.getRandomValues`, válido por **15 minutos**.
2. **Armazenamento Seguro de Tokens:** O código nunca é salvo em texto puro no banco D1; grava-se o hash `SHA-256(code:email:MASTER_SECRET)` na tabela `password_reset_tokens`.
3. **Disparo Transacional via Resend:**
   - O Cloudflare Pages Functions realiza uma chamada HTTP segura para `https://api.resend.com/emails`.
   - Utiliza a variável de ambiente secreta `RESEND_API_KEY` configurada no painel da Cloudflare.
   - O remetente padrão é `OpenMoney <seguranca@openmoney.app.br>` (configurável via `RESEND_FROM_EMAIL`).
   - O e-mail conta com template HTML escuro e legível com o código em destaque monoespaçado.
4. **Redefinição Atômica de Senha (`POST /api/auth/reset-password`):**
   - Valida o código e sua validade temporal.
   - Gera um novo *salt* criptográfico de 16 bytes e deriva a nova chave com `PBKDF2-HMAC-SHA256` (100.000 iterações).
   - Zera as tentativas incorretas (`failed_attempts = 0`), remove bloqueios e invalida o token (`used = 1`).
   - Emite automaticamente um novo token JWT, conectando o usuário imediatamente sem exigir novo login manual.
5. **Experiência Multiplataforma Integrada:**
   - **Flutter Web (`AuthView`):** Link "Esqueci minha senha" que alterna de forma fluida para a tela em 2 etapas.
   - **Flutter Desktop & Mobile (`CloudAccountModal`):** Fluxo integrado direto no modal de nuvem.
   - **Swift macOS & iOS (`CloudAccountSheet` / `CloudSyncManager`):** Interface nativa em SwiftUI com validação de 6 dígitos e feedback dinâmico.

### 2.6. Isolamento de Cabeçalhos Públicos e Tratamento Resiliente de Sessão Expirada (HTTP 401)
Ao alterar a senha em um dispositivo (ex: Web), os demais aparelhos conectados (ex: Desktop) mantêm temporariamente tokens de sessão residuais agora invalidados:
1. **Sanitização de Requisições Públicas (`requiresAuth: false`):** As rotas de login, cadastro, solicitação de código e redefinição de senha são estritamente públicas. Os clientes Swift e Flutter não anexam mais cabeçalhos residuais `Authorization: Bearer`, impedindo que tokens antigos interfiram no fluxo de autenticação.
2. **Prioridade Visual do Modo de Recuperação:** O estado de recuperação (`isForgotMode`) tem precedência sobre qualquer flag residual de sessão ativa, garantindo que o usuário sempre visualize o formulário de 6 dígitos e nova senha.
3. **Resolução de Sessão Expirada em 1 Clique:** Quando qualquer requisição de sincronização ou troca de conta retorna HTTP 401 (`"Sessão expirada ou não autenticada"`), a interface exibe instantaneamente:
   - **"Reconectar com Senha":** Limpa o token expirado, mantém o e-mail preenchido e solicita a nova credencial.
   - **"Recuperar Senha por E-mail":** Dispara diretamente o envio do código de 6 dígitos via Resend.
4. **Atalho Direto em "Alterar Senha":** No modal de alteração de senha de usuários conectados, foi adicionado o atalho *"Esqueci minha senha atual"*, dispensando adivinhações caso o usuário não recorde a senha em uso.

### 2.7. Controle de Concorrência Optimista (Prevenção Estrita de Sobrescrita) e Polling Contínuo
Para eliminar o risco de perda de dados ou sobrescrita cruzada entre múltiplos dispositivos (ex: Web no iPhone e Desktop no Mac):
1. **Revisão Base (`X-OpenMoney-Base-Revision`):** Toda requisição de salvamento (`PUT /api/db`) informa a revisão local na qual as alterações foram realizadas.
2. **Proteção HTTP 409 Conflict:** Se o servidor Cloudflare detectar que a revisão na nuvem é mais recente que a revisão base informada pelo cliente, a operação é rejeitada categoricamente com HTTP 409 e o servidor retorna a revisão atual para que o cliente se atualize antes de gravar.
3. **Consulta Leve de Revisão (`GET /api/db/revision` e `HEAD /api/db`):** Permite verificar a versão remota em ~5ms sem trafegar ou descriptografar o payload da base.
4. **Heartbeat Periódico (30s) e Sincronização na Abertura:**
   - Ao iniciar, o app Desktop (Swift macOS e Flutter) busca a base mais recente da nuvem antes de qualquer operação local, sem disparar push reverso.
   - A cada 30 segundos ou ao reativar a janela, o cliente verifica se houve alterações em outro dispositivo e sincroniza suavemente.

---

## 3. Guia Passo a Passo de Ativação 100% pelo Painel da Cloudflare (Sem precisar de `npx` no Mac)

Como o script [publish_release_macos.sh](file:///Users/fabiano/Developer/OpenMoneyFlutter/scripts/publish_release_macos.sh) já compila a versão Web em `web-dist/` e envia automaticamente para o seu GitHub (`FSF77/openmoney-new`), você pode configurar tudo direto pelo navegador no painel da Cloudflare, sem precisar instalar o Node.js/`npx` no Mac:

### Passo 1: Criar o Banco de Dados D1 no Painel da Cloudflare
1. No painel da sua conta Cloudflare, no menu lateral esquerdo, clique em **Workers & Pages > D1 SQL Database**.
2. Clique no botão azul **Create** e dê o nome: `openmoney-db`.
*(Você não precisa criar tabelas manualmente — o próprio sistema cria as tabelas `users`, `user_databases` e `user_database_backups` automaticamente no primeiro acesso!)*

### Passo 2: Conectar o Cloudflare Pages ao seu GitHub
1. No menu lateral da Cloudflare, vá em **Workers & Pages > Create > aba Pages > Connect to Git**.
2. Selecione o seu repositório **`FSF77/openmoney-new`**.
3. Em **Build settings**:
   - **Project name:** `openmoney`
   - **Build command:** *(deixe em branco, pois o seu Mac já envia compilado)*
   - **Build output directory:** `web-dist`
4. Clique em **Save and Deploy**.

### Passo 3: Vincular o Banco D1 e a Chave de Criptografia
Dentro do projeto `openmoney` recém-criado em **Workers & Pages > openmoney > Settings**:
1. Em **Bindings** > **Add** > **D1 database**:
   - **Variable name:** `DB`
   - **D1 database:** `openmoney-db`
2. Em **Variables and Secrets** > **Add**:
   - **`MASTER_SECRET`**: defina uma frase longa e secreta (usada para assinar os tokens JWT e criptografar o `openmoney.json` de cada usuário com `AES-256-GCM`).
   - **`RESEND_API_KEY`**: chave de API criada gratuitamente na [Resend](https://resend.com) (plano gratuito com 3.000 e-mails/mês) para o envio de códigos de recuperação de senha por e-mail.
   - **`RESEND_FROM_EMAIL`** *(Opcional)*: remetente dos e-mails (ex: `OpenMoney <seguranca@openmoney.app.br>`). Se não configurado, assume o padrão do sistema.
   - **`INVITE_CODE`** *(Opcional)*: se quiser que apenas pessoas com o seu código de convite possam criar conta, preencha um código aqui (ex: `EMPRESA2026`). Se deixar em branco, qualquer pessoa com o link poderá criar a própria conta isolada.

### Passo 4: Conectar o seu Subdomínio
Em **Workers & Pages > openmoney > Custom domains > Set up a custom domain**:
- Digite o subdomínio desejado (ex: `openmoney.suaempresa.com.br`) e clique em **Activate domain**. A própria Cloudflare configura o DNS (`CNAME`) e o certificado HTTPS automaticamente!

> **Nota Opcional (Caso queira ter o comando `npx` no Mac no futuro):**
> Como você já tem o Homebrew instalado no seu Mac, basta rodar `brew install node` no terminal se algum dia quiser usar o `npx wrangler` via linha de comando. Mas usando a integração com o GitHub acima, você não precisa dele!
