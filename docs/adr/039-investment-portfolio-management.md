# ADR 039: Módulo Unificado de Carteira de Investimentos

**Status:** Aceito e Implementado  
**Data:** 2026-11-25  
**Escopo:** Schema `v: 7`, Modelos (`InvestAsset`, `InvestOperation`, `MarketIndicators`), Motor Contábil (`InvestmentEngine`), Cotações & Indicadores BCB, Proxy Cloudflare, Importação B3 Multi-Aba, Cloud Sync v2, UI Multiplataforma e Relatórios (PDF/CSV).

---

## 1. Contexto e Motivação

O OpenMoney já possuía o tipo de conta `Investimento`, porém ele operava apenas como conta-corrente passiva alimentada por transferências manuais (`Conta Corrente ↔ Conta Investimento`). Isso gerava quatro lacunas críticas para investidores:
1. **Ausência de marcação a mercado:** o saldo da conta não refletia a valorização/desvalorização de ações, FIIs, criptomoedas e títulos de Renda Fixa/Tesouro.
2. **Sem controle de Preço Médio e P&L:** não havia cálculo de Preço Médio de Compra (com taxas), Preço Médio de Venda, Lucro/Prejuízo Realizado ou acompanhamento de Proventos (*Yield on Cost*).
3. **Sem apuração de IR em Renda Fixa:** resgates de CDB/RDB/LC/Debêntures/Tesouro Direto exigem aplicação da Tabela Regressiva de IR por lote em dias corridos.
4. **Falta de importação automatizada:** ausência de leitor nativo para as planilhas `.xlsx`/`.csv` exportadas da Área do Investidor B3.

---

## 2. Decisões Arquiteturais

### 2.1. Modelo de Dados e Schema `v: 7` Retrocompatível
Definido em `lib/models/investment_models.dart` e `lib/models/openmoney_models.dart`:
- **Rigor Monetário e Precisão Fracionária Isolada:**
  - Todos os valores financeiros (`unitPriceCents`, `feesCents`, `taxCents`, `totalCents`, `currentPriceCents`, `avgBuyPriceCents`, `avgSellPriceCents`, `realizedPnlCents`, saldos e `Transaction.amt`) permanecem estritamente em **centavos inteiros (`int`, 2 casas decimais)**, sem qualquer interferência nas contas existentes.
  - A precisão de até **8 casas decimais** (`double`) aplica-se **exclusivamente ao campo `quantity`** de `InvestOperation` (para suportar frações de Criptomoedas como `0,00452100 BTC` e frações de `0,01` no Tesouro Direto).
- **`Database` (`openmoney.json`, `v: 7`):**
  - Novos campos opcionais: `investAssets` (`List<InvestAsset>`), `investOps` (`List<InvestOperation>`) e `investIndicators` (`MarketIndicators?`), omitidos do JSON quando vazios/nulos para manter 100% de compatibilidade com bases legadas.
- **`InvestAsset`:**
  - Identificação: `id`, `ticker`, `name`, `assetClass` (`stock`, `fii`, `etf`, `bdr`, `fixedIncome`, `tesouro`, `crypto`, `other`), `subType` (`CDB`, `RDB`, `LC`, `LCI`, `LCA`, `CRI`, `CRA`, `Debênture`, `Tesouro Selic`, `Tesouro Prefixado`, `Tesouro IPCA+`), `accountId` (corretora padrão), `currency` (`BRL`, `USD`, `EUR`).
  - Renda Fixa & Tesouro: `indexer` (`cdi`, `selic`, `ipca`, `prefixado`, `other`), `ratePct`, `maturityDate` (`YYYY-MM-DD`), `liquidity` (`daily` | `maturity`), `taxExempt` (`bool` — ativado automaticamente para `LCI`/`LCA`/`CRI`/`CRA`).
  - Cotação e Ciclo de Vida: `currentPriceCents`, `priceUpdatedAt`, `manualPrice` (`bool`), `priceSource`, `memo` e `inactive` (`bool`, padrão `false` — arquiva o ativo preservando histórico).
- **`InvestOperation`:**
  - `id`, `assetId`, `accountId` (corretora de custódia efetiva da operação), `type` (`buy`, `sell`, `dividend`, `jcp`, `fiiYield`, `amortization`, `split`, `inplit`, `bonus`, `initialPosition`), `date` (`YYYY-MM-DD`), `quantity`, `unitPriceCents`, `feesCents`, `taxCents` (IR retido na fonte), `totalCents`, `linkedTxId`, `linkedTaxTxId`, `memo`, `createdAt`.
- **`MarketIndicators`:**
  - `cdiAnnual`, `selicAnnual`, `ipca12m`, `updatedAt`, `manual`.
- **`Transaction.investOpId`:**
  - Chave estrangeira opcional ligando transações de caixa geradas pela carteira à operação de origem.

### 2.2. Motor Contábil de Preço Médio, Renda Fixa e IR Regressivo (`InvestmentEngine`)
Implementado como motor puro e determinístico em `lib/services/investment_engine.dart`:
- **Compra / Posição Inicial:** `opCost = totalCents > 0 ? totalCents : ((qty * unitPrice) + fees)`. Atualiza `currentQty`, `currentCostBasisCents` e `avgBuyPriceCents = (currentCostBasisCents / currentQty).round()`.
- **Venda:**
  - **Preço Médio de Compra (`avgBuyPriceCents`) nunca se altera na venda** (regra contábil e fiscal B3/Receita Federal).
  - Apura `avgSellPriceCents` ponderado por todas as vendas do ativo e `realizedPnlCents += (netProceeds - op.taxCents - costBasisSold)`.
  - Se `currentQty <= 1e-8`, zera custódia aberta preservando o histórico realizado e o PM de venda.
- **Eventos Corporativos e Proventos:**
  - `amortization`: reduz `currentCostBasisCents` e recalcula `avgBuyPriceCents` (padrão FIIs).
  - `split` / `inplit`: multiplica/divide `currentQty` pelo fator e ajusta `avgBuyPriceCents` mantendo o custo total intacto.
  - `bonus`: adiciona cotas e eventual custo atribuído.
  - `dividend` / `jcp` / `fiiYield`: acumulam em `totalDividendsCents` e alimentam `yieldOnCostPct` e `totalReturnCents`.
- **Renda Fixa & Tesouro Direto (Lotes FIFO + Tabela Regressiva):**
  - Mantém lotes abertos (`rfLots`) com a data exata de cada aporte (não exigindo cadastrar um ativo novo para cada compra no mesmo título).
  - Quando não há preço manual, projeta o valor bruto atualizado via juros compostos em dias úteis aproximados (`calendarDays * 252 / 365`) usando `MarketIndicators` (CDI, Selic, IPCA ou Prefixado).
  - `estimateSellIr(...)` calcula o IR sugerido no resgate em ordem **FIFO** aplicando a **Tabela Regressiva de IR** em dias corridos por lote sobre o lucro positivo:
    - Até 180 dias: **22,5%**
    - De 181 a 360 dias: **20,0%**
    - De 361 a 720 dias: **17,5%**
    - Acima de 720 dias: **15,0%**
    - Títulos `taxExempt == true` (`LCI`, `LCA`, `CRI`, `CRA`): **0%**.

### 2.3. Integração de Caixa, Categorias, Multi-Corretora e Saldo Atualizado (`MoneyStore`)
Implementado em `lib/store/money_store.dart`, `lib/services/cash_flow_engine.dart` e `lib/services/analytics_engine.dart`:
- **Lançamentos sem Poluir Relatórios:**
  - Compra e conversão de Posição Inicial → geram `Transaction` na conta selecionada com categoria **`Transferência (-)`** (`amt < 0`).
  - Venda → gera `Transaction` com categoria **`Transferência (+)`** (`amt > 0`).
  - `isTransferTransaction(tx)` e `AnalyticsEngine` excluem automaticamente tais lançamentos de despesas, receitas, orçamentos e Fluxo de Caixa.
- **Proventos e IR com Categorias Configuráveis:**
  - `investDividendCategory` (padrão **`Investimentos (-) › Rendimentos`**) e `investIrCategory` (padrão **`Investimentos (-) › IR`**), persistidos em `config.json` e sincronizados na Web.
  - `ensureCategoryPath(path, type: 'Despesa')` garante a criação automática da categoria pai e subcategoria em `db.cats` caso ainda não existam.
  - Na venda de Renda Fixa tributada com `taxCents > 0`, o sistema gera **dois lançamentos vinculados** (`linkedTxId` bruto em `Transferência (+)` e `linkedTaxTxId` negativo em `Investimentos (-) › IR`), resultando no crédito líquido exato (`Bruto - IR`) na conta destino. Edições e exclusões atualizam/removem ambos atomicamente.
- **Custódia Multi-Corretora por Operação:**
  - A custódia é determinada por `InvestOperation.accountId`. O mesmo ativo (ex: `PETR4`) pode ser comprado em múltiplas corretoras: o filtro por corretora isola cada posição, enquanto a visão global consolida o Preço Médio unificado.
  - Ao editar a conta padrão de um ativo em `addOrUpdateInvestAsset`, operações e transações vinculadas da conta antiga migram automaticamente para a nova conta.
- **Saldo Total Atualizado (`accountTotalBalance`):**
  - Para contas `Investimento` com ativos ou operações vinculadas, `accountTotalBalance(acc)` retorna `Caixa Livre (balance(acc)) + Valor Atualizado dos Ativos (portfolioMarketValue(accountId: acc.id))`.
  - Refletido no menu lateral (`app_shell.dart`), no card **Investimentos** e no **Patrimônio Líquido Total** do Dashboard (`dashboard_overview_view.dart`), e no banner de resumo da conta (`account_ledger_view.dart`).
- **Onboarding sem Dupla Contagem:**
  - Na **Posição Inicial** (manual ou via B3), o usuário escolhe entre apenas registrar os ativos ou converter parte do saldo histórico da conta em Posição Inicial (`Transferência (-)`).

### 2.4. Cotações Online, Indicadores BCB e Proxy Cloudflare
Implementado em `lib/services/investment_quote_service.dart` e `functions/api/[[route]].js`:
- **Criptomoedas (`BTC`, `USDC`, `ETH`, `SOL`, etc.):** cadeia automática com fallback progressivo: **Binance → Coinbase Spot → Mercado Bitcoin (BRL) → CoinGecko → AwesomeAPI → Yahoo Finance**, além de normalização de nomes comuns (`BITCOIN → BTC`, `USD COIN → USDC`).
- **Ações, FIIs, ETFs e BDRs:** consulta Yahoo Finance (sufixo `.SA` automático para ativos B3 em BRL).
- **Indicadores Renda Fixa:** séries oficiais do Banco Central (BCB SGS `4389` CDI, `432` Selic, `13522` IPCA 12m).
- **Proxy sem CORS na Web:** endpoints `GET /api/market/quotes` (cache de borda 5 min) e `GET /api/market/indicators` (cache de borda 1 h) no Cloudflare Worker.
- **Proteção de Preço Manual:** ativos com `manualPrice == true` exibem badge `M`, não são sobrescritos pela atualização automática e podem ser revertidos para o modo automático com 1 clique.

### 2.5. Importação B3 Multi-Aba em Dart Puro (`B3ImportService`)
Implementado em `lib/services/b3_import_service.dart` usando `package:archive`:
- Lê `xl/workbook.xml` e processa cada worksheet do `.xlsx` (e `.csv`) de forma independente com o nome da aba como pista semântica (`Tesouro Direto`, `Renda Fixa`, `Ações`, `FIIs`).
- Converte números seriais de data do Excel (ex: `45730 → 2025-03-14`) e formatos `DD/MM/AAAA` / `YYYY-MM-DD`, preservando as datas originais do arquivo.
- Deduplica operações contra `db.investOps` antes de importar.

### 2.6. Interface Multiplataforma, UX e Relatórios
Implementado em `lib/ui/views/investments_view.dart`, `lib/ui/modals/investment_modals.dart`, `lib/ui/app_shell.dart` e `lib/services/pdf_report_generator.dart`:
- **Navegação:** item **Investimentos** (`NavModule.investments`) posicionado logo abaixo de **Lançamentos** na barra lateral recolhida e expandida.
- **Responsividade (`LayoutBuilder`):** abaixo de `960px` alterna para grade adaptativa de cards (2 colunas `>= 620px`, 1 coluna `< 620px`); a partir de `960px` exibe `DataTable` completa ocupando toda a largura útil.
- **Modais Inteligentes:**
  - `Total da Operação ↔ Preço Unitário` editável bidirecionalmente com parsing `double` de alta precisão.
  - Quantidade disponível em custódia pré-preenchida e editável na **Venda**.
  - `DateInputFormatter` (`DD/MM/AAAA`) nos campos de data.
  - Seletor `CategorySelectFormField` para categoria do IR; dropdowns com `isExpanded: true` e `TextOverflow.ellipsis` sem overflow.
  - Clique no ativo abre `showAssetOperationsModal` (extrato do título com edição e exclusão de operações).
  - Edição do ativo permite **Inativar (arquivar)** ou **Excluir Ativo** (com opção de remover lançamentos vinculados no caixa).
- **Relatórios e Exportação:** 4 abas (**Posição Atual**, **Operações**, **Renda Fixa & Tesouro**, **Análise & Alocação** com `fl_chart`), exportação **PDF A4 Paisagem** (`exportInvestmentPositionPdf`) e **CSV completo** com 24 colunas (incluindo `Corretora / Conta`).

### 2.7. Cloud Sync v2 e Documentação
- `SyncEngine` (`lib/services/sync_engine.dart`) e `applySyncChangesToSnapshot` (`functions/api/[[route]].js`) sincronizam granularmente `investAssets/<id>`, `investOps/<id>` e `meta/investIndicators`.
- Dicionário de Dados (`docs/architecture/dicionario-de-dados.md`) e Guia do Usuário (`docs/manual/guia-investimentos.md`) atualizados em sincronia com o código.

---

## 3. Consequências e Verificação

- **Positivas:** unificação completa do controle de caixa e carteira em código único Flutter/Dart, sem dependências externas novas para `.xlsx`, sem distorção de despesas/receitas nos relatórios existentes e com sincronização em tempo real preservada.
- **Verificação Automatizada:** coberto por `test/investment_engine_test.dart`, `test/b3_import_service_test.dart` e `test/sync_engine_test.dart` (todos integrados à suíte `flutter test`).
