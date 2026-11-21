# Guia do Usuário: Sincronização em Tempo Real (OpenMoney Cloud — Sync v2)

Este guia explica como funciona a **Sincronização Automática em Tempo Real por Registro (Sync v2)** no **OpenMoney**, abrangendo tanto a versão **Web (`https://openmoney.app.br`)** quanto os aplicativos para **Desktop (macOS e Windows)**.

---

## 🌐 1. Visão Geral da Arquitetura Sync v2

O **OpenMoney Cloud (Sync v2)** foi projetado para que você **nunca precise clicar em botões de sincronizar**:

- **Endereço Oficial Web:** [https://openmoney.app.br](https://openmoney.app.br)
- **Suporte Multiplataforma Híbrido:** Operação 100% em tempo real na Web e nos aplicativos de computador (macOS e Windows). No Desktop, você pode alternar facilmente entre bases locais em arquivo (`openmoney.json`) e bases sincronizadas na nuvem.
- **Sincronização Granular por Registro (Sem Sobrescrita):** Quando você altera um lançamento no celular e outro no computador, apenas os registros afetados são transmitidos e mesclados (`seq` monotônico incremental). Um dispositivo nunca sobrescreve o trabalho do outro.
- **Tempo Real Automático:** As alterações refletem entre abas e dispositivos conectados de forma instantânea via WebSockets e canais delta.
- **Fila Offline Inteligente (`Outbox`):** Se a conexão oscilar ou cair, você continua lançando normalmente. As alterações ficam guardadas em fila local segura e são transmitidas sozinhas assim que a internet voltar.
- **Criptografia em Repouso por Usuário (`AES-256-GCM`):** Cada registro e snapshot da base são criptografados com chaves exclusivas derivadas via `HKDF-SHA256` para cada usuário.

---

## 🚀 2. Primeiro Acesso

### A. No Desktop (macOS e Windows)
Ao abrir o OpenMoney pela primeira vez no computador (ou sem base configurada), é exibida a tela de boas-vindas com opções claras:

1. **Modo Local:**
   - *Abrir base local existente (.json):* Abre seu arquivo `openmoney.json` salvo no computador, iCloud Drive ou OneDrive.
   - *Criar nova base local (.json):* Cria um arquivo novo limpo no local que você escolher, já com as categorias sugeridas do sistema.
2. **Modo Online (OpenMoney Cloud):**
   - *Conectar em Conta Online ou Criar Nova Conta:* Abre o painel para entrar com sua conta existente ou criar um novo login na nuvem.

### B. Na Web (`https://openmoney.app.br`)
1. Acesse pelo navegador do computador ou adicione à Tela de Início do iPhone/Android como Web App.
2. Na aba **"Criar Conta"**, informe Nome, E-mail e Senha (mínimo de 8 caracteres).
3. Caso queira carregar sua base existente do computador, use a opção de importar o arquivo `openmoney.json`.

---

## ✉️ 3. Confirmação de Cadastro e Segurança (Código de 6 Dígitos)

Para garantir que a conta pertence de fato ao titular:

1. Ao solicitar a criação de uma conta online, um **código de verificação de 6 dígitos** é enviado imediatamente para o seu e-mail pelo serviço seguro de mensageria (**Resend**).
2. Na etapa 2 da tela de cadastro, digite o código de 6 dígitos recebido e clique em **"Confirmar e Ativar Conta"**. O código tem validade de **15 minutos**.
3. Uma vez validado, sua conta é ativada e a base financeira entra imediatamente em sincronismo.

> **Dica:** O mesmo processo de confirmação de 6 dígitos é utilizado caso você precise usar a opção **"Esqueceu a senha?"** ou queira **alterar o e-mail da sua conta**.

---

## 🔀 4. Alternando entre Modo Local e Modo Online no Menu Lateral (Desktop)

No rodapé da barra lateral dos aplicativos Desktop, há um seletor rápido com duas pílulas:

```
┌────────────────────────────────────────┐
│  [ 💻 Local ]      [ ☁️ Online ]       │
└────────────────────────────────────────┘
```

- **Clique em "Local":** O aplicativo desconecta da nuvem e passa a ler e gravar diretamente no seu arquivo físico em disco (`openmoney.json`).
- **Clique em "Online":** O aplicativo conecta na sua conta na nuvem e ativa a sincronização em tempo real.
- Se nenhuma base estiver configurada ao clicar em um dos modos, o aplicativo abre automaticamente o painel para você selecionar o arquivo ou fazer login.

---

## 🛡️ 5. Backups de Segurança: Proteção Dupla (Nuvem + Local no Computador)

O OpenMoney garante que você **nunca perca dados**, mantendo múltiplas camadas de segurança:

### A. Backups Locais no Computador para Contas Online (Desktop)
Mesmo quando você utiliza uma conta na nuvem, o aplicativo desktop mantém uma cópia física segura no seu computador:

1. **Backup Automático ao Acessar o App (3 a 4x ao dia):**
   - Toda vez que você abre o aplicativo (e periodicamente durante o uso, até 4 vezes ao dia por turno de 6h ou a cada 3h), é gerado automaticamente um arquivo compactado `.zip` na pasta de backups do computador:
     - **macOS:** `~/Library/Application Support/OpenMoney/Backups/openmoney-cloud-[email]-backup-[YYYY-MM-DD_HHmm].zip`
     - **Windows:** `%APPDATA%\OpenMoney\Backups\openmoney-cloud-[email]-backup-[YYYY-MM-DD_HHmm].zip`
2. **Backup Manual Pontual:**
   - No menu lateral, clique em **"Backups de Segurança"** e clique no botão **"Criar Backup Agora"**.
   - É gerado um arquivo com carimbo de data e hora: `openmoney-cloud-[email]-manual-[YYYY-MM-DD_HHmmss].zip`.
3. **Revelar no Finder / Explorer:**
   - Clique em "Revelar no Finder / Explorer" para visualizar todos os arquivos `.zip` salvos no seu disco rígido e copiá-los para um pendrive ou HD externo.

### B. Backups Automáticos na Nuvem (3 a 4x ao dia • Retenção de 15 dias)
- O servidor Cloudflare mantém automaticamente de **3 a 4 snapshots por dia** nos últimos **15 dias** da sua conta, gerados assim que você abre o aplicativo ou o site (`https://openmoney.app.br`) e ao salvar alterações.
- No painel **Cloud & Sincronização**, role até a seção **"Backups na Nuvem"** e clique em **"Restaurar"** ao lado do horário desejado (`YYYY-MM-DD HH:mm`) se precisar recuperar o estado de um momento anterior.

### C. Restauração Transparente
- Ao restaurar qualquer backup `.zip` (seja local ou da nuvem), a base restaurada é aplicada e sincronizada automaticamente para a nuvem, atualizando todos os seus outros dispositivos.

### D. Blindagem Automática Anti-Wipe e Inicialização Segura (>10MB)
Para proteger integralmente contas com histórico extenso (`>10MB`), principalmente após atualizações do aplicativo:
1. **Cache Isolado com Gravação Atômica:** No Desktop (macOS e Windows), o cache offline da sua base online é salvo em arquivo dedicado por conta (`cloud_cache/`) usando gravação atômica por arquivo temporário, evitando qualquer risco de corrupção ao fechar ou atualizar o aplicativo.
2. **Tela de Sincronização Inicial Segura:** Enquanto a base online é baixada ou validada na inicialização, o app exibe a tela *"Carregando seus dados..."* com retentativas automáticas, impedindo que uma tela zerada seja exibida ou manipulada acidentalmente antes da carga completa.
3. **Proteção Tripla Contra Sobrescrita Vazia:** Se qualquer cache local estiver incompleto ou vazio em uma conta já populada, o aplicativo o descarta automaticamente e baixa o snapshot oficial da nuvem. Tanto o cliente quanto o servidor Cloudflare bloqueiam qualquer envio ou compactação vazia acidental sobre uma base populada (`Anti-Wipe Guard`).

---

## 📝 6. Logs de Auditoria e Alterações no Banco Online

Todas as movimentações financeiras relevantes (criação, edição e exclusão de contas, lançamentos, categorias e conciliações) são registradas no **Log de Auditoria**:

- **No Modo Online:** As alterações são enviadas e armazenadas de forma segura na tabela `user_audit_logs` do banco online **Cloudflare D1**, com retenção automática de **30 dias**.
- **Histórico Unificado:** Todas as alterações feitas por você pelo celular, tablet ou computador ficam visíveis em um só lugar.
- **Acesso:** No menu lateral, clique em **"Logs de Alterações"**. Você pode filtrar por período, tipo de entidade (Lançamentos, Contas, Categorias) ou pesquisar por texto.
- **No Desktop:** Além de salvar no banco online, o desktop espelha os registros no arquivo local `openmoney-cloud-[email].log`, permitindo abrir o arquivo ou visualizá-lo offline.

---

## 🔑 7. Alterando o E-mail da Conta Online

1. Abra o painel **Cloud & Sincronização** e clique na aba **"Configurações da Conta"**.
2. No campo **"Alterar E-mail"**, digite o novo endereço desejado e clique em **"Enviar Código de Confirmação"**.
3. Acesse a caixa de entrada do seu novo e-mail, copie o código de 6 dígitos, cole no aplicativo e confirme. O login da conta é atualizado mantendo todos os seus dados intactos.

---

## ⚠️ 8. Exclusão Segura da Base ou da Conta (Com Backup por E-mail)

Caso você deseje excluir seus dados:

1. No painel **Cloud & Sincronização**, clique na opção de exclusão.
2. Você pode optar entre:
   - **Excluir apenas os dados da base:** Reinicia sua conta com uma base em branco.
   - **Excluir a conta definitivamente:** Remove o usuário, histórico de sincronização e todos os dados associados.
3. **Trava de Segurança:** É obrigatório digitar a palavra `"EXCLUIR"` em maiúsculas para confirmar a operação.
4. **Backup Preventivo por E-mail:** Antes de apagar qualquer informação, o servidor gera automaticamente um arquivo compactado `.zip` contendo o `openmoney.json` dos seus dados e **envia para o seu e-mail cadastrado via Resend**. Assim, mesmo em caso de exclusão acidental, você sempre terá uma cópia do seu histórico financeiro na sua caixa de entrada.

---

## 🌐 9. Diferenças entre a Versão Web e Desktop

A versão Web (`openmoney.app.br`) foi desenhada com foco na agilidade e tempo real, ocultando automaticamente recursos que dependem de arquivos ou programas instalados no computador:

- **Rodapé da Barra Lateral:** No navegador, não é exibido o botão "Local", mantendo apenas o indicador em tempo real da sua conta online.
- **Módulos Ocultados no Menu Lateral Web:**
  - *Backups de Segurança:* Na Web, seus dados contam com os snapshots automáticos dos últimos 15 dias na nuvem.
  - *Importar Carteira (CSV), Importar Comprovantes (OCR) e Importar do Celular (.json):* Otimizados para o Desktop e manipuladores locais de arquivos.
  - *Buscar Atualizações:* Não se aplica no navegador (o site é atualizado instantaneamente a cada nova versão publicada).
- **Logs de Alterações:** Na Web, o visualizador de logs exibe todas as alterações em tempo real direto do banco Cloudflare D1, ocultando os botões de abrir arquivo `.log` local.

---

## 🗑️ 10. Gerenciamento e Alternância de Contas Salvas no Dispositivo

No painel **OpenMoney Cloud & Sincronização**:

1. **Card da Conta Ativa:** Exibe o nome, e-mail, badge `ATIVA` e revisão na nuvem em linhas organizadas, com o botão **Desconectar Conta (Logout)** posicionado na linha inferior do card (sem repetição redundante no cabeçalho da janela).
2. **Card Alternar entre Contas e Bases:**
   - Permite alternar com 1 clique entre múltiplas contas salvas (ex.: Pessoal e Consultoria/Empresa), exibindo o **nome** na linha principal e o **e-mail** e revisão nas linhas seguintes para leitura clara mesmo em telas pequenas.
   - Os controles de topo utilizam **ícones compactos com tooltip de ajuda**: **Ordenar A-Z / Z-A**, **Desconectar Todas as Contas Salvas**, **Conectar Outra Conta Existente** e **+ Criar Nova Conta / Base na Nuvem**.
3. **Acesso Rápido na Tela de Login:** Ao desconectar de uma conta, você também pode removê-la definitivamente do dispositivo clicando no ícone de fechar/lixeira.

---

## 🤖 11. Infraestrutura da Assistente de IA na Nuvem (Cloudflare Pages & D1)

A sincronização em nuvem também alimenta a **Assistente Financeira com IA** no modo **Nuvem Cloud (Gerenciado)**. Usuários autenticados no OpenMoney Cloud podem utilizar consultas assistidas sem precisar configurar chaves pessoais externas:

- **Endpoints da API:**
  - `GET /api/ai/capabilities`: Valida se o servidor possui chaves gerenciadas ativas e informa a cota diária do usuário.
  - `POST /api/ai/chat`: Processa requisições de linguagem natural e extração com proxy seguro anti-CORS e injeção do modelo de IA.
- **Variáveis de Ambiente no Cloudflare Pages:**
  - `AI_MANAGED_GEMINI_KEY`: Chave de API do Google Gemini (definida como *Secret/Encrypted* no painel do Pages em **Settings › Environment variables**).
  - `AI_MANAGED_OPENROUTER_KEY`: Chave de API do OpenRouter.ai (acesso unificado a dezenas de provedores e modelos).
  - `AI_MANAGED_ANTHROPIC_KEY`: Chave de API do Claude (opcional, para instâncias que oferecem Claude gerenciado).
  - `AI_MANAGED_OPENAI_KEY`: Chave de API do ChatGPT (opcional, para instâncias que oferecem OpenAI gerenciado).
  - `AI_DAILY_LIMIT`: Cota diária padrão por usuário (padrão: `25` consultas/dia).
- **Controle de Cotas Atômico no D1:**
  - O servidor gerencia o consumo diário na tabela `user_ai_usage` (`user_id`, `usage_date`, `request_count`), que é provisionada automaticamente via D1 sem necessidade de migrações manuais.
