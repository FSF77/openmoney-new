# ADR 036 — Servidor MCP Remoto (Streamable HTTP), OAuth 2.1, PKCE S256 e Isolamento de Segurança

## Status
Aprovado e Implementado (Novembro/2026).

---

## 1. Contexto e Motivação
Com o avanço dos Modelos de Linguagem de Grande Porte (LLMs) como Claude (Anthropic), ChatGPT (OpenAI) e Gemini (Google), usuários do OpenMoney demandavam a capacidade de interagir com seus dados financeiros pessoais a partir de seus assistentes externos favoritos (desktop, web e mobile).

Embora a Assistente nativa do aplicativo já fornecesse suporte a BYOK e Nuvem Cloud interna (ADR 030), era necessário prover uma interface padronizada via **Model Context Protocol (MCP)** e **OpenAPI**, permitindo que clientes externos consumissem ferramentas financeiras de forma segura, sem expor credenciais de login ou chaves mestras e garantindo isolamento total de dados.

---

## 2. Decisões de Arquitetura

### 2.1. Transporte Streamable HTTP (Substituição de SSE Legado)
- **Descontinuação do SSE Puro**: Conforme diretriz dos ecossistemas MCP e Claude, o transporte baseado exclusivamente em Server-Sent Events (SSE) foi substituído pelo padrão **Streamable HTTP** (`POST /api/mcp` e `/mcp`).
- **Compatibilidade e Negociação**:
  - `POST /api/mcp`: Processa comandos JSON-RPC 2.0 com retorno direto `application/json`.
  - `GET /api/mcp`: Responde com status `200 OK` para verificação de disponibilidade (*health-check* e sondagens do ChatGPT / Claude).
  - Suporte a negociação dinâmica da versão do protocolo MCP (`protocolVersion`: `2024-11-05` / `2025-03-20`).
  - Implementação de handlers para todas as sondagens de capacidade do MCP (`tools/list`, `tools/call`, `resources/list`, `resources/templates/list`, `prompts/list`).

### 2.2. Autenticação e Autodescoberta OAuth 2.1
Para permitir a experiência de conexão "1-clique" no ChatGPT e Claude Web sem necessidade de copiar e colar tokens manualmente, foram implementadas as especificações oficiais de autodescoberta:
1. **RFC 9728 (OAuth Protected Resource Metadata)**:
   - Endpoint: `/.well-known/oauth-protected-resource`
   - Fornece metadados do recurso protegido e aponta para o servidor de autorização emissor.
2. **RFC 8414 & OpenID Connect Discovery**:
   - Endpoints: `/.well-known/oauth-authorization-server` e `/.well-known/openid-configuration`
   - Expõe endpoints de autorização (`/oauth/authorize`), emissão de token (`/api/oauth/token`), registro dinâmico de clientes (`/api/oauth/register`) e suporte a PKCE (`code_challenge_methods_supported: ["S256"]`).
3. **RFC 7591 (Dynamic Client Registration - DCR)**:
   - Endpoint: `/api/oauth/register`
   - Permite que assistentes como ChatGPT gerem credenciais de cliente (`client_id`, `client_secret`) dinamicamente no ato da conexão, registradas na tabela `oauth_clients` do Cloudflare D1.
4. **Proteção PKCE S256 e Mitigação de Mix-Up (RFC 9207)**:
   - O fluxo de autorização exige Code Challenge `S256`.
   - O redirecionamento de autorização inclui explicitamente o parâmetro `iss` (`https://openmoney.app.br`), prevenindo ataques de redirecionamento cruzado (*authorization server mix-up*).

### 2.3. Chaves de API Estáticas (Bearer Tokens `opm_live_...`)
Para clientes locais como **Claude Desktop**, **Cursor**, **LM Studio** e scripts de automação:
- Geração de tokens de alta entropia com prefixo identificador `opm_live_`.
- **Armazenamento com Hash Criptográfico SHA-256**: O valor do token bruto é exibido ao usuário **uma única vez** no modal de criação. No banco de dados Cloudflare D1 (`api_tokens`), é gravado estritamente o hash SHA-256 do token.
- **Prefixos Públicos**: Apenas o prefixo truncado (ex: `opm_live_abc123...`) e o nome do token são mantidos em texto claro para exibição na lista de chaves.
- **Revogação Instantânea com Confirmação**: A interface exige confirmação do usuário antes de revogar chaves, e a exclusão da linha no banco D1 invalida o acesso do assistente de imediato.

### 2.4. Isolamento Multi-Inquilino e Segurança de Dados
- **Isolamento por `user_id`**: O middleware de autenticação (`/api/mcp`, `/api/openapi/*`) extrai o `user_id` criptograficamente validado da sessão OAuth ou do token Bearer. Nenhuma consulta tem acesso a dados de outros usuários.
- **Criptografia Zero-Knowledge Cloud**: As bases de dados sincronizadas no Cloudflare D1 (`chunked:*`) utilizam criptografia AES-256-GCM com chave derivada da credencial do usuário.
- **Permissões Granulares**:
  - `read_only`: Acesso restrito a relatórios, extratos, contas, categorias e orçamentos. Operações de mutação retornam `403 Forbidden`.
  - `read_write`: Permite inclusão, atualização e exclusão pontual de transações.
- **Trilha de Auditoria nos Logs**: Qualquer modificação executada via conector MCP remoto gera uma entrada na trilha de auditoria do sistema com o marcador visual `[MCP Remoto]` e carimbo de data/hora.
- **Salvaguardas Anti-Wipe**: A API do MCP não disponibiliza ferramentas para exclusão em massa, eliminação de contas ou substituição de arquivos da base de dados.

### 2.5. Cálculo Determinístico de Saldos (Saldo Atual vs. Saldo Previsto)
Para prevenir alucinações de modelos de linguagem onde transações futuras ou não conciliadas eram somadas ao saldo bancário disponível do dia:
- **Saldo Atual do Dia (Conciliado)**:
  $$\text{Saldo Atual} = \text{opening} + \sum_{t \in \text{txs}, t.\text{rec} = \text{true}, t.\text{date} \le \text{hoje}} t.\text{amt}$$
  Calcula rigorosamente o valor em caixa/bancos conciliado até a data atual, em estrita paridade com o `MoneyStore.rebuildIndexes()` do aplicativo Flutter.
- **Saldo Previsto no Mês**:
  $$\text{Saldo Previsto} = \text{Saldo Atual} + \sum_{t \in \text{txs}, t.\text{rec} = \text{false}, t.\text{date} \le \text{fim\_do\_mês}} t.\text{amt}$$
  Projeta a posição esperada ao término do mês corrente considerando contas a pagar e a receber ainda pendentes.

---

## 3. Ferramentas Expostas pelo Servidor MCP

| Ferramenta | Escopo | Finalidade |
| :--- | :--- | :--- |
| `openmoney_get_financial_overview` | Leitura | Caixa líquido conciliado por conta, carteira de investimentos bruta, patrimônio consolidado, saldo previsto no mês, despesas e receitas do mês corrente. |
| `openmoney_list_accounts` | Leitura | Listagem de contas com identificadores, nomes, tipos, saldo atual conciliado e saldo previsto. |
| `openmoney_list_categories` | Leitura | Listagem de categorias e subcategorias cadastradas, tipos e status em relatórios. |
| `openmoney_query_transactions` | Leitura | Consulta filtrada de lançamentos por período (mês/ano), conta, beneficiário, status de conciliação ou busca textual. |
| `openmoney_add_transaction` | Leitura/Escrita | Inclusão de novos lançamentos (receitas, despesas) com beneficiário, valor em reais, conta, categoria e tags. |
| `openmoney_update_transaction` | Leitura/Escrita | Atualização de transação existente por ID. |
| `openmoney_delete_transaction` | Leitura/Escrita | Exclusão unitária de transação específica por ID com verificação de existência. |
| `openmoney_transfer_funds` | Leitura/Escrita | Criação de transferência entre duas contas de forma atômica e consistente. |
| `openmoney_get_predictions_and_budgets` | Leitura | Consulta do limite de gastos e previsões orçamentárias do mês, comparando valor orçado vs realizado. |
| `openmoney_get_investments_overview` | Leitura | *(v2.6.0 · ADR 039)* Resumo da carteira, alocação por classe e insights automáticos (concentração, altas/baixas, vencimentos ≤ 90d e queda de IR ≤ 30d). |
| `openmoney_list_investment_positions` | Leitura | *(v2.6.0 · ADR 039)* Listagem filtrável das posições da carteira (classe, corretora, busca e posições encerradas). |
| `openmoney_list_investment_operations` | Leitura | *(v2.6.0 · ADR 039)* Extrato de operações da carteira filtrável por ativo, tipo, corretora e período. |
| `openmoney_create_investment_operation` | Leitura/Escrita | *(v2.6.0 · ADR 039)* Registro de compras, vendas e proventos na carteira com movimentação opcional de caixa e Sync v2. |

---

## 4. Consequências e Resultados
- Conexão nativa e transparente no **ChatGPT** (via conector de aplicativo 1-clique com OAuth 2.1) e no **Claude Desktop/Web** (via Streamable HTTP).
- Suporte a agentes de terminal e clientes locais (**Cursor**, **LM Studio**, **Claude Code**) através de tokens Bearer criptograficamente seguros.
- Total preservação da integridade contábil e do isolamento multi-usuário no Cloudflare D1.
- Eliminação definitiva de ambiguidades de saldos bancários nos relatórios gerados por inteligências artificiais.
