# Guia do Usuário: Conectando o OpenMoney ao Gemini, ChatGPT, Claude e Agentes de IA

Conecte seus assistentes de Inteligência Artificial favoritos — **Google Gemini**, **ChatGPT**, **Anthropic Claude**, **Cursor** ou **LM Studio** — diretamente à sua base de dados financeira do OpenMoney.

Com essa integração, você pode perguntar seu saldo no banco, analisar seus gastos por categoria, registrar despesas ou receitas por texto ou voz e acompanhar limites do mês diretamente pela conversa com a sua IA de preferência.

---

## 1. Passo a Passo de Conexão (Foco no Usuário)

No OpenMoney, abra o menu **Ajustes & Personalização** › **Servidor MCP & Acesso Externo**.

Nessa tela você encontra a URL do servidor MCP e o gerador de chaves de acesso. Escolha abaixo o seu assistente e siga o passo a passo correspondente:

---

### 1.1. Google Gemini

O Gemini permite conectar o OpenMoney com autenticação segura e automática em 1 clique:

1. No **Google Gemini** (navegador ou app), acesse as configurações de **Ferramentas / Custom MCP / Conectores**.
2. Clique em **Adicionar Novo Servidor / Conector**.
3. No campo de endereço do servidor, insira a URL oficial:
   ```text
   https://openmoney.app.br/api/mcp
   ```
4. O Gemini detectará o servidor e abrirá automaticamente a tela oficial de login do OpenMoney.
5. Digite seu **e-mail e senha** do OpenMoney Cloud e clique em **Autorizar**.
6. Pronto! O conector será ativado e você já pode conversar com o Gemini sobre o seu dinheiro.

*(Alternativa via Gemini Gems / OpenAPI: importe a especificação `https://openmoney.app.br/api/openapi.json` e adicione o Bearer Token gerado no OpenMoney).*

---

### 1.2. ChatGPT (OpenAI)

O ChatGPT suporta tanto o novo **Conector de Aplicativo (1-Clique)** quanto **Custom GPTs**:

#### Opção A: Conector de Aplicativo / MCP (Mais Simples — 1 Clique)
1. No ChatGPT (Web ou Desktop), acesse **Settings (Configurações)** › **Connected Apps (Aplicativos Conectados)** ou Ferramentas de Desenvolvedor.
2. Adicione a URL:
   ```text
   https://openmoney.app.br/api/mcp
   ```
3. A janela de login do OpenMoney abrirá automaticamente. Entre com sua conta e confirme a autorização.
4. O ChatGPT confirmará a conexão e as ferramentas ficarão prontas para uso em qualquer conversa.

#### Opção B: Custom GPT (Ações Customizadas via OpenAPI)
1. Acesse **Explore GPTs** › **Create a GPT** › aba **Configure**.
2. Role até a seção **Actions** e clique em **Create new action**.
3. Clique em **Import from URL** e cole:
   ```text
   https://openmoney.app.br/api/openapi.json
   ```
4. Em **Authentication**:
   - Selecione **API Key** › Tipo **Bearer** e cole a chave de acesso gerada no OpenMoney (começa com `opm_live_...`); ou
   - Selecione **OAuth** e indique as URLs `https://openmoney.app.br/api/oauth/authorize` e `https://openmoney.app.br/api/oauth/token`.
5. Salve o GPT como privado.

---

### 1.3. Anthropic Claude (Claude Desktop & Claude Web)

O Claude conecta-se ao OpenMoney através do protocolo oficial **Streamable HTTP**:

#### No Claude Desktop (Mac e Windows)
1. No OpenMoney, em **Servidor MCP & Acesso Externo**, clique em **Novo Token MCP**.
2. Dê um nome (ex.: `Claude Desktop`) e escolha as permissões (**Leitura e Escrita** ou **Somente Leitura**).
3. Na janela de confirmação, clique em **Copiar JSON para o Claude Desktop**.
4. Abra o arquivo de configuração do Claude no seu computador:
   - **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
5. Cole o bloco do OpenMoney dentro da seção `"mcpServers"`:
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
6. Reinicie o Claude Desktop. O ícone de ferramentas (martelo) exibirá as funções do OpenMoney prontas para uso.

#### No Claude Web (claude.ai)
1. Nas configurações do Claude Web, acesse a área de **MCP Connectors**.
2. Adicione a URL `https://openmoney.app.br/api/mcp` e autorize com sua conta OpenMoney.

---

### 1.4. LM Studio, Cursor, Claude Code e Agentes Locais

#### LM Studio (Modelos Locais)
1. Abra a aba **MCP Servers** no LM Studio.
2. Adicione um servidor HTTP com:
   - **URL:** `https://openmoney.app.br/api/mcp`
   - **Header:** `Authorization: Bearer opm_live_...`
3. Qualquer modelo local compatível com function calling (Qwen 2.5, Llama 3.3, Mistral) poderá ler e lançar gastos no OpenMoney!

#### Cursor (IDE)
1. Abra **Cursor Settings** › **Features** › **MCP**.
2. Clique em **Add New MCP Server**:
   - **Type:** `http`
   - **URL:** `https://openmoney.app.br/api/mcp`
   - **Headers:** `{"Authorization": "Bearer opm_live_..."}`

---

## 2. Exemplos de Perguntas e Comandos para Fazer à IA

Com a IA conectada, você pode falar em linguagem natural como se estivesse conversando com um assistente financeiro pessoal:

### Consultas de Saldo e Posição Geral
- *"Qual é o meu saldo bancário atual no Itaú hoje?"*
- *"Quanto eu tenho de saldo disponível somando todas as minhas contas?"*
- *"Qual é a projeção de saldo previsto para o final deste mês?"*
- *"Como está a fatura aberta do meu cartão de crédito Nubank?"*

### Análise de Extrato e Gastos
- *"Quanto eu gastei com Alimentação este mês comparado ao mês passado?"*
- *"Liste os 5 maiores gastos que tive nas últimas duas semanas."*
- *"Quais assinaturas ou pagamentos recorrentes estão previstos até o fim do mês?"*
- *"Estou perto de estourar algum limite no meu orçamento?"*

### Análise de Carteira e Investimentos
- *"Qual o resumo da minha carteira de investimentos, rentabilidade e score de diversificação?"*
- *"Quais ativos da minha carteira estão com maior alta, maior baixa ou concentração acima de 25%?"*
- *"Tenho títulos de Renda Fixa vencendo nos próximos 90 dias ou prestes a cair de alíquota de IR?"*
- *"Registre a compra de 50 cotas de PETR4 a R$ 38,50 hoje na minha corretora XP."*

### Lançamentos Rápidos e Transferências
- *"Almocei no restaurante Sabor da Terra e paguei R$ 45,00 no débito Itaú hoje. Lança pra mim na categoria Alimentação com a tag #trabalho."*
- *"Comprei uma mesa de escritório de R$ 600,00 em 3x no cartão Nubank hoje."*
- *"Transfira R$ 800,00 da minha Conta Corrente para a Poupança."*
- *"Atualize o valor do lançamento da farmácia de ontem para R$ 52,00."*

---

## 3. Gerenciamento de Acesso e Revogação

Você tem controle total sobre quais aplicativos e IAs têm acesso aos seus dados:

- **Visualização de Chaves Ativas**: Em **Ajustes & Personalização** › **Servidor MCP & Acesso Externo**, você vê todos os assistentes conectados, a data de criação e a data/hora do último uso.
- **Revogação Instantânea com Confirmação**: Para desconectar qualquer IA, clique no ícone de lixeira. O aplicativo perguntará se você confirma a exclusão. Ao confirmar, o acesso é revogado no mesmo milissegundo em todos os servidores da nuvem.
- **Identificação Clara de Ações**: Qualquer lançamento, alteração ou exclusão feita por uma IA externa aparece identificada nos registros e relatórios do OpenMoney com a marcação **`[MCP Remoto]`**.

---

## 4. Dúvidas Frequentes do Usuário (FAQ)

### O assistente de IA pode apagar minha base de dados inteira?
**Não.** O conector não disponibiliza comandos para apagar contas, zerar saldos ou deletar a base. As exclusões permitidas são sempre unitárias (um lançamento específico por ID) e passam por salvaguardas que impedem alterações em massa.

### O que acontece se eu estiver com o app aberto no celular/computador e pedir para a IA criar um gasto?
Graças à sincronização em tempo real (**Sync v2**), o lançamento criado pela IA é gravado na nuvem e transmitido imediatamente via WebSocket. Ele **aparece na tela do seu aplicativo na mesma hora**, sem conflito de dados e sem risco de ser sobrescrito pelo app.

### Qual a diferença entre "Saldo Atual" e "Saldo Previsto" que a IA informa?
- **Saldo Atual do Dia (Conciliado):** É o dinheiro real disponível na conta hoje, considerando apenas os lançamentos que você já conferiu e conciliou até a data presente. Esse é o número que bate com o extrato do seu banco.
- **Saldo Previsto no Mês:** É a projeção matemática calculada até o último dia do mês, somando as receitas a receber e subtraindo contas a pagar e faturas pendentes.

### Posso conectar a IA apenas para ler meus dados, sem permissão para criar lançamentos?
**Sim.** Ao autorizar uma conexão OAuth ou criar um token de acesso, selecione a opção **"Somente Leitura" (`read_only`)**. O assistente poderá responder dúvidas, montar relatórios e gráficos, mas o servidor rejeitará qualquer tentativa de criar, editar ou apagar registros com erro de permissão.

---

## 5. Informações Técnicas e Arquitetura (Documentação Complementar)

Esta seção documenta a arquitetura técnica, padrões de segurança e especificações de rede para desenvolvedores e administradores do sistema.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   SEUS CLIENTES E ASSISTENTES DE IA                     │
│    (ChatGPT, Claude Desktop/Web, Gemini, Cursor, LM Studio, Agentes)   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │  HTTPS / Streamable HTTP (JSON-RPC)
                                    ▼  (OAuth 2.1 PKCE S256 ou Bearer Token)
┌────────────────────────────────────────────────────────────────────────┐
│               GATEWAY DE BORDA: CLOUDFLARE PAGES FUNCTIONS             │
│  - Autodescoberta RFC 8414 (OAuth Server) e RFC 9728 (Protected Res)  │
│  - Dynamic Client Registration (RFC 7591) com mitigação RFC 9207 (iss) │
│  - Resolução de inquilino (user_id) e isolamento multi-tenant          │
│  - Validação estrita de escopo (read_only vs read_write)               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                  ┌─────────────────┴─────────────────┐
                  ▼                                   ▼
┌───────────────────────────────────┐ ┌───────────────────────────────────┐
│     INTEGRAÇÃO SYNC V2 & D1       │ │       DURABLE OBJECTS (WS)        │
│ - user_sync_records: deltas reais │ │ - UserSyncRoom: broadcast em tempo│
│ - user_databases: snapshot seguro │ │   real para apps conectados       │
│ - Hash SHA-256 de API tokens      │ │ - 0ms de atraso visual no desktop │
└───────────────────────────────────┘ └───────────────────────────────────┘
```

### 5.1. Padrões OAuth 2.1 e Autodescoberta
- **RFC 9728 (Protected Resource Metadata)**: Endpoint `/.well-known/oauth-protected-resource/api/mcp` orienta clientes externos sobre as autoridades emissoras e escopos suportados.
- **RFC 8414 & OpenID Connect Discovery**: Endpoints `/.well-known/oauth-authorization-server` e `/.well-known/openid-configuration` expõem os endpoints de autorização, token, registro dinâmico e suporte PKCE `S256`.
- **RFC 7591 (Dynamic Client Registration - DCR)**: Endpoint `/api/oauth/register` permite registro dinâmico de clientes (`client_name`, `redirect_uris`, `client_secret_post`).
- **RFC 9207 (Mix-Up Mitigation)**: Parâmetro `iss` retornado no redirecionamento do código de autorização garante a procedência do servidor.

### 5.2. Especificação do Transporte MCP (Streamable HTTP)
- **Endpoint Principal**: `POST /api/mcp` (e alias `/mcp`). Processa requisições JSON-RPC 2.0 em formato `application/json; charset=utf-8`.
- **Negociação de Protocolo**: Suporte à versão `protocolVersion: "2025-03-26"` e retrocompatibilidade com versões anteriores (`2024-11-05`).
- **Tratamento de GET / HEAD**:
  - `HEAD /api/mcp`: Retorna `200 OK` com cabeçalhos de sessão para sondagens de conectividade.
  - `GET /api/mcp` (com `Accept: text/event-stream`): Retorna `405 Method Not Allowed` com cabeçalho `Allow: POST, DELETE, OPTIONS, HEAD` conforme a seção 3.3 da especificação MCP Streamable HTTP, instruindo o cliente a operar em modo request-response sobre POST sem aguardar streaming reverso.
  - `GET /api/mcp` (com `Accept: application/json`): Retorna `200 OK` com metadados do servidor.

### 5.3. Segurança de Dados e Isolamento
- **Tokens Bearer com Hash Criptográfico**: O segredo bruto `opm_live_...` é exibido apenas no momento da criação. O banco Cloudflare D1 armazena exclusivamente o hash **SHA-256** da chave.
- **Criptografia Zero-Knowledge**: Bases de dados armazenadas no Cloudflare D1 utilizam criptografia `AES-256-GCM` com chave derivada da credencial do usuário.
- **Auditoria de Sistema**: Toda mutação externa é registrada na tabela `user_audit_logs` com identificação do `tokenId`, carimbo de data/hora e marcador `[MCP Remoto]`.
- **Salvaguardas Anti-Wipe**: Bloqueio compulsório `HTTP 409` no backend contra uploads truncados (`< 50 KB`) em bases populadas.

### 5.4. Catálogo de Ferramentas MCP (Tools Reference)

| Ferramenta | Método | Escopo | Finalidade |
| :--- | :--- | :--- | :--- |
| `openmoney_get_financial_overview` | Leitura | `read_only` | Resumo financeiro consolidado: caixa líquido conciliado por conta, carteira de investimentos bruta, patrimônio consolidado, saldo previsto no mês, receitas, despesas e resultado líquido. |
| `openmoney_list_accounts` | Leitura | `read_only` | Relação detalhada de contas bancárias, tipos, identificadores e saldos. |
| `openmoney_list_categories` | Leitura | `read_only` | Estrutura hierárquica de categorias e subcategorias cadastradas. |
| `openmoney_query_transactions` | Leitura | `read_only` | Busca e filtro de lançamentos por data, conta, texto, tag ou status de conciliação. |
| `openmoney_add_transaction` | Escrita | `read_write` | Criação de despesas, receitas, compras parceladas e transferências com gravação no Sync v2. |
| `openmoney_update_transaction` | Escrita | `read_write` | Edição de campos de lançamentos existentes por ID. |
| `openmoney_delete_transaction` | Escrita | `read_write` | Remoção unitária e segura de transação por ID (e de contraparte em transferências). |
| `openmoney_get_predictions_and_budgets` | Leitura | `read_only` | Avaliação completa dos limites de gastos (orçamento mensal configurado em Limite de Gastos) e previsões de gastos do mês, com teto planejado, gastos realizados, % consumido e saldo restante. Suporta alias `openmoney_get_budget_status`. |
| `openmoney_get_investments_overview` | Leitura | `read_only` | Resumo da carteira de investimentos (aplicado, bruto, IR estimado, líquido, rentabilidade, realizado, proventos, caixa livre em corretoras), alocação por classe e **insights automáticos** (concentração, maiores altas/baixas, vencimentos ≤ 90d e queda de faixa de IR ≤ 30d). |
| `openmoney_list_investment_positions` | Leitura | `read_only` | Lista posições da carteira filtráveis por classe, corretora, busca ou posições encerradas, com quantidade, PM, preço atual, valor bruto/líquido, rentabilidade e proventos. |
| `openmoney_list_investment_operations` | Leitura | `read_only` | Extrato de operações da carteira (compra, venda, dividendo, JCP, rendimento FII, amortização, posição inicial) filtrável por ticker, tipo, corretora e período. |
| `openmoney_create_investment_operation` | Escrita | `read_write` | Registra nova operação na carteira (compra, venda, dividendo, JCP, rendimento FII ou amortização) com movimentação opcional de caixa e Sync v2. |
