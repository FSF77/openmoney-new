# Guia do Usuário: Servidor MCP Remoto & Agentes de IA Externos (ChatGPT, Claude, Gemini, Cursor e LM Studio)

O OpenMoney disponibiliza um **Servidor MCP Remoto (Model Context Protocol)** e uma **API OpenAPI** nativa hospedada diretamente na infraestrutura do **OpenMoney Cloud (Cloudflare Workers & D1)**.

Essa integração permite conectar seus assistentes de Inteligência Artificial favoritos — **ChatGPT**, **Claude Desktop / Claude Web**, **Google Gemini**, **Cursor**, **LM Studio**, **Claude Code** ou qualquer agente autônomo compatível com MCP — diretamente aos seus dados financeiros com total segurança, privacidade e rastreabilidade.

---

## 1. Arquitetura de Segurança, Privacidade e Anti-Wipe

A segurança e a soberania dos seus dados financeiros são os pilares centrais da integração externa do OpenMoney. Todas as conexões utilizam padrões modernos da indústria e múltiplas camadas de proteção:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   SEUS CLIENTES E ASSISTENTES DE IA                     │
│    (ChatGPT, Claude Desktop/Web, Gemini, Cursor, LM Studio, Agentes)   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │  Transporte Seguro HTTPS
                                    ▼  (OAuth 2.1 PKCE S256 ou Bearer Token)
┌────────────────────────────────────────────────────────────────────────┐
│               GATEWAY DE BORDA: CLOUDFLARE WORKERS                     │
│  - Autodescoberta RFC 8414 & RFC 9728                                  │
│  - Dynamic Client Registration (RFC 7591)                              │
│  - Middleware de Autenticação e Resolução de Inquilino (user_id)       │
│  - Validação de Escopo: Leitura Estrita (read_only) vs Leitura/Escrita │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│              SALVAGUARDAS E AUDITORIA (ANTI-WIPE GUARD)                │
│  - [MCP Remoto]: Toda ação de inserção/edição é marcada nos logs       │
│  - Operações unitárias por ID (impossível apagar base em lote via IA)  │
│  - Bloqueio HTTP 409 contra uploads vazios ou corrompidos (< 50 KB)   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     BANCO DE DADOS CLOUDFLARE D1                       │
│  - api_tokens: Hash SHA-256 do token (o segredo nunca é gravado)       │
│  - Bases de dados com criptografia de ponta a ponta (AES-256-GCM)      │
│  - Isolamento estrito por chave de usuário (Multi-Tenant Zero Leak)    │
└────────────────────────────────────────────────────────────────────────┘
```

### 1.1. Autodescoberta OAuth 2.1 (Conexão 1-Clique)
- **Zero Compartilhamento de Senhas**: O ChatGPT ou Claude conectam-se usando o protocolo **OAuth 2.1**, abrindo uma tela oficial de autorização no próprio domínio seguro `openmoney.app.br`. O modelo de IA nunca recebe sua senha mestra.
- **Dynamic Client Registration (RFC 7591)**: Suporte completo ao registro dinâmico de clientes, permitindo que os assistentes de IA se cadastrem automaticamente no servidor sem que você precise preencher formulários manuais de credenciais.
- **Proteção PKCE S256**: O fluxo de login utiliza Prova Criptográfica de Chave (*Proof Key for Code Exchange*) com hash `S256`, impedindo qualquer tentativa de interceptação de códigos de autorização em trânsito.
- **Mitigação de Authorization Server Mix-Up (RFC 9207)**: Todas as respostas de autorização incluem explicitamente o parâmetro `iss`, garantindo que o assistente confie unicamente no emissor oficial.

### 1.2. Tokens de API Bearer (`opm_live_...`)
- **Tokens de Alta Entropia**: Gerados via gerador criptográfico pseudo-aleatório (`crypto.getRandomValues`).
- **Armazenamento Seguro com Hash SHA-256**: Ao gerar uma nova chave no aplicativo, o token é exibido na tela **uma única vez**. O banco de dados Cloudflare D1 armazena estritamente o hash **SHA-256** do token. Caso o banco de dados venha a ser auditado, nenhuma chave utilizável pode ser recuperada.
- **Confirmação Obrigatória na Revogação**: Ao clicar no ícone de lixeira para revogar um token, o aplicativo solicita confirmação explícita. Uma vez revogado, o token é removido imediatamente do banco D1 e qualquer sessão de IA associada perde o acesso no mesmo instante.

### 1.3. Permissões Granulares (Escopos de Acesso)
Ao gerar um token ou autorizar uma conexão OAuth, você escolhe o nível de acesso do assistente:
- **Somente Leitura (`read_only`)**: O assistente pode consultar extratos, saldos, categorias, faturas e relatórios orçamentários, mas qualquer tentativa de criar, editar ou excluir transações é bloqueada imediatamente com erro `HTTP 403 Forbidden`.
- **Leitura e Escrita (`read_write`)**: O assistente pode também registrar novos lançamentos, atualizar transações e efetuar transferências entre contas.

### 1.4. Trilha de Auditoria e Rastreabilidade Transparente
Toda operação de inclusão, alteração ou exclusão de lançamentos realizada por agentes externos ou assistentes de IA é automaticamente carimbada com a etiqueta **`[MCP Remoto]`** (ou `[Assistente IA]`) nos registros e na linha do tempo do OpenMoney. Você sempre saberá exatamente o que foi criado ou modificado por uma inteligência artificial.

### 1.5. Salvaguardas Anti-Wipe (Anti-Wipe Guardrails)
O servidor MCP foi desenhado com limites rígidos para proteger seu patrimônio de alucinações de modelos de linguagem:
- Não existem ferramentas para apagar bases de dados inteiras, redefinir saldos ou excluir múltiplas contas.
- Operações de exclusão são unitárias, exigindo o ID exato da transação previamente validada.
- O backend mantém o bloqueio de segurança `HTTP 409` contra qualquer substituição suspeita de banco de dados com tamanho inferior a 50 KB sem autorização explícita de força.

---

## 2. Diferença Conceitual de Saldos: Atual vs. Previsto

Para evitar que assistentes de IA se confundam ao comparar o saldo do aplicativo com extratos bancários, o OpenMoney fornece dois conceitos contábeis distintos via MCP:

| Conceito | Descrição | Fórmula / Critério |
| :--- | :--- | :--- |
| **Saldo Atual do Dia (Conciliado)** | O valor financeiro **realmente disponível na conta hoje**, exatamente igual ao extrato bancário ou carteira. | $\text{Saldo Atual} = \text{opening} + \sum (\text{transações com } \text{rec} = \text{true} \text{ até a data de hoje})$. Ignora transações futuras ou ainda não conferidas. |
| **Saldo Previsto no Mês** | A projeção financeira calculada até o último dia do mês corrente. | $\text{Saldo Previsto} = \text{Saldo Atual} + \sum (\text{transações pendentes com } \text{rec} = \text{false} \text{ que vencem até o fim do mês})$. Considera contas a pagar e a receber programadas. |

Ao perguntar para a IA *"Qual é o meu saldo no banco?"*, o servidor informa com precisão o **Saldo Atual (Conciliado)** para que você confira com o aplicativo do seu banco, além de informar o **Saldo Previsto** para projeção orçamentária.

---

## 3. Guia Prático de Conexão Passo a Passo

Para acessar a central de configuração, abra o OpenMoney e navegue até:
**Ajustes & Personalização** › **Servidor MCP & Acesso Externo (ChatGPT, Claude, Gemini e agentes)**.

---

### 3.1. ChatGPT (OpenAI)

O ChatGPT suporta tanto conexão via **Conector de Aplicativo (OAuth 2.1)** quanto via **Custom GPT Actions**.

#### Opção A: Conexão via Aplicativo / Conector MCP (Recomendado — 1 Clique)
1. No ChatGPT (Web ou Desktop), acesse **Settings (Configurações)** › **Connected Apps (Aplicativos Conectados)** ou crie um conector customizado.
2. Informe a URL do Servidor MCP:
   ```text
   https://openmoney.app.br/api/mcp
   ```
3. O ChatGPT detectará automaticamente os metadados de autorização (RFC 8414 / RFC 9728) e abrirá a tela de login do OpenMoney.
4. Digite seu e-mail e senha do OpenMoney Cloud e clique em **Autorizar**.
5. O ChatGPT confirma a conexão e passa a responder perguntas sobre suas contas instantaneamente!

#### Opção B: Custom GPT com OpenAPI Spec
1. No ChatGPT, acesse **Explore GPTs** › **Create a GPT** › aba **Configure**.
2. Role até a seção **Actions** e clique em **Create new action**.
3. No campo **Schema**, clique em **Import from URL** e insira:
   ```text
   https://openmoney.app.br/api/openapi.json
   ```
4. Em **Authentication**:
   - Escolha **API Key** › Tipo **Bearer** e cole seu token `opm_live_...` gerado na central do OpenMoney; ou
   - Escolha **OAuth** e preencha as URLs de autorização (`https://openmoney.app.br/oauth/authorize`) e de token (`https://openmoney.app.br/api/oauth/token`).
5. Salve o GPT (privado para você).

---

### 3.2. Anthropic Claude (Claude Desktop & Claude Web)

O Claude suporta conexão nativa utilizando o transporte moderno **Streamable HTTP**.

#### Claude Desktop
1. No OpenMoney, abra o modal **Servidor MCP & Acesso Externo** e clique em **Novo Token MCP**.
2. Defina um nome (ex: `Claude Desktop Mac`) e selecione as permissões (**Leitura e Escrita** ou **Somente Leitura**).
3. Ao gerar, o OpenMoney exibirá o snippet de configuração pronto. Clique em **Copiar JSON para o Claude Desktop**.
4. No seu computador, abra o arquivo de configuração do Claude Desktop:
   - **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
5. Adicione o servidor dentro do bloco `"mcpServers"`:
   ```json
   {
     "mcpServers": {
       "openmoney": {
         "type": "http",
         "url": "https://openmoney.app.br/api/mcp",
         "headers": {
           "Authorization": "Bearer SEU_TOKEN_OPM_LIVE_AQUI"
         }
       }
     }
   }
   ```
6. Reinicie o Claude Desktop. O ícone de martelo (ferramentas) exibirá as ferramentas do OpenMoney ativas!

#### Claude Web (claude.ai)
1. No Claude Web, acesse as configurações de conectores ou integrações MCP.
2. Adicione a URL `https://openmoney.app.br/api/mcp` e autorize via OAuth 2.1 ou insira o Bearer Token.

---

### 3.3. Google Gemini / Gemini Live

1. Crie uma **Gemini Gem** ou configure uma extensão com chamada de ferramentas.
2. Conecte através do endpoint OpenAPI oficial:
   ```text
   https://openmoney.app.br/api/openapi.json
   ```
3. Defina a autenticação com o cabeçalho `Authorization: Bearer opm_live_...`.

---

### 3.4. LM Studio, Cursor, Claude Code e Agentes Locais

#### LM Studio
1. No LM Studio, navegue até a aba **MCP Servers**.
2. Adicione um novo servidor HTTP apontando para:
   - **URL:** `https://openmoney.app.br/api/mcp`
   - **Header:** `Authorization: Bearer opm_live_...`
3. Qualquer modelo local com suporte a function calling (como Qwen 2.5, Llama 3.3, Mistral) poderá consultar e registrar lançamentos na sua base OpenMoney!

#### Cursor (IDE)
1. Acesse **Cursor Settings** › **Features** › **MCP**.
2. Clique em **Add New MCP Server**:
   - **Type:** `command` ou `http`
   - **URL:** `https://openmoney.app.br/api/mcp`
   - **Headers:** `{"Authorization": "Bearer opm_live_..."}`

---

## 4. Catálogo de Ferramentas Expostas (MCP Tools Reference)

Os assistentes externos possuem acesso às seguintes ferramentas estruturadas:

### 1. `openmoney_get_financial_overview`
- **Descrição:** Retorna a posição financeira geral consolidada do usuário no mês atual: saldo atual conciliado de todas as contas, saldo previsto até o fim do mês, total de receitas realizadas e pendentes, total de despesas realizadas e pendentes e resultado líquido.

### 2. `openmoney_list_accounts`
- **Descrição:** Lista todas as contas financeiras cadastradas com seus respectivos nomes, identificadores (`id`), tipos (`Corrente`, `Cartão de crédito`, `Poupança`, `Investimento`, `Dinheiro`), saldo atual do dia (conciliado) e saldo previsto.

### 3. `openmoney_list_categories`
- **Descrição:** Lista a árvore completa de categorias e subcategorias cadastradas, indicando seus tipos (`income`, `expense`) e se estão marcadas para participar dos relatórios oficiais.

### 4. `openmoney_query_transactions`
- **Descrição:** Consulta o extrato de lançamentos com filtros granulares:
  - `month`: Mês de competência (1 a 12).
  - `year`: Ano de competência (ex: 2026).
  - `accountId`: Filtro por conta específica.
  - `reconciledOnly`: Se `true`, retorna apenas transações já conciliadas.
  - `search`: Busca textual por beneficiário, anotação ou tag.
  - `limit`: Quantidade máxima de registros retornados.

### 5. `openmoney_add_transaction` *(Requer permissão de Escrita)*
- **Descrição:** Insere um novo lançamento na base de dados com recálculo automático de saldos e fatura:
  - `accountId`: Identificador da conta.
  - `date`: Data no formato `YYYY-MM-DD`.
  - `amount`: Valor monetário em reais (ex: `45.90` para despesas ou receitas).
  - `type`: `expense` (despesa) ou `income` (receita).
  - `payee`: Nome do favorecido ou estabelecimento.
  - `category`: Nome da categoria (ex: `"Alimentação › Supermercado"`).
  - `tags`: Lista opcional de tags (ex: `["#trabalho", "#reembolsavel"]`).
  - `notes`: Observações adicionais.

### 6. `openmoney_update_transaction` *(Requer permissão de Escrita)*
- **Descrição:** Atualiza campos de uma transação existente informando seu `id`.

### 7. `openmoney_delete_transaction` *(Requer permissão de Escrita)*
- **Descrição:** Exclui uma transação específica por seu `id`. A exclusão é unitária e segura.

### 8. `openmoney_transfer_funds` *(Requer permissão de Escrita)*
- **Descrição:** Efetua uma transferência entre duas contas cadastradas, criando simultaneamente a perna de débito e a perna de crédito vinculadas.

### 9. `openmoney_get_predictions_and_budgets`
- **Descrição:** Retorna a situação do Limite de Gastos e Previsões Orçamentárias do mês, comparando o limite planejado contra o total efetivamente gasto por categoria.

---

## 5. Exemplos de Prompts para Usar no seu Assistente

Uma vez conectado, você pode conversar naturalmente com o ChatGPT, Claude ou Gemini:

- *"Qual é o meu saldo atual conciliado no banco hoje?"*
- *"Quanto eu ainda tenho de saldo previsto para terminar o mês?"*
- *"Liste os meus 5 maiores gastos com Alimentação neste mês."*
- *"Acabei de almoçar no Restaurante Sabor da Terra e paguei R$ 42,00 no cartão Itaú. Registre para mim com a tag #trabalho."*
- *"Quanto eu gastei com Combustível no mês passado comparado a este mês?"*
- *"Estou estourando alguma previsão orçamentária no Limite de Gastos?"*
- *"Transfira R$ 500,00 da minha Conta Corrente para a Poupança."*

---

## 6. Dúvidas Frequentes (FAQ)

### O assistente de IA pode apagar todos os meus dados?
**Não.** O servidor MCP não expõe nenhuma ferramenta de exclusão em lote, eliminação de contas ou substituição de arquivos da base. Todas as exclusões são unitárias por ID e passam por validação prévia. Além disso, as salvaguardas Anti-Wipe da Cloudflare rejeitam qualquer tentativa de upload de base com payload truncado.

### O que acontece se eu revogar um token de acesso?
No mesmo milissegundo em que você confirma a exclusão do token no OpenMoney, o hash correspondente é apagado do banco de dados Cloudflare D1. Qualquer requisição futura feita pelo ChatGPT, Claude ou agente externo usando aquele token receberá o erro `HTTP 401 Unauthorized`.

### Posso usar o conector apenas para consulta sem permitir lançamentos?
**Sim.** Ao criar o token ou autorizar a conexão, selecione a permissão **"Somente Leitura" (`read_only`)**. O assistente poderá responder todas as suas dúvidas financeiras, mas o servidor rejeitará qualquer instrução de inserção ou alteração.

### Como sei se um lançamento foi feito por uma IA ou por mim?
Todos os lançamentos gerados por assistentes externos recebem o marcador **`[MCP Remoto]`** nos registros e na auditoria do sistema, garantindo transparência total.
