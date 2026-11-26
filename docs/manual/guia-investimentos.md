# 📈 Guia Completo da Carteira de Investimentos — OpenMoney

Gerencie sua carteira de **Ações**, **FIIs**, **ETFs**, **BDRs**, **Renda Fixa (CDB, RDB, LC, LCI, LCA, Debêntures, CRI/CRA)**, **Tesouro Direto** e **Criptomoedas** diretamente no OpenMoney (macOS, Windows, Web e Mobile), com cálculo automático de **Preço Médio de Compra e Venda**, **IR Regressivo**, **Proventos** e **Saldo Atualizado da Conta de Investimentos**.

---

## 1. Passo a Passo de Configuração e Uso

### Acessando a Carteira
- No menu lateral esquerdo, clique em **Investimentos** (posicionado logo abaixo de **Lançamentos**).
- No **Dashboard**, o card **Investimentos** também exibe o resumo atualizado (`Caixa Livre + Carteira Atualizada`) e o botão de atalho **Carteira**.

### Como começar sem duplicar seu saldo histórico
Se você já possuía uma conta do tipo `Investimento` com transferências antigas vindas da conta corrente:

#### Opção A: Importar planilha da Área do Investidor B3 (`.xlsx` ou `.csv`)
1. Acesse a **Área do Investidor B3** e exporte o relatório de **Posição** ou **Movimentação** em `.xlsx` (multi-aba) ou `.csv`.
2. Em **Investimentos**, clique em **Importar B3** e selecione a **Conta de Destino (Corretora)**.
3. O sistema identifica automaticamente as abas e classes (**Ações**, **FIIs**, **ETFs**, **BDRs**, **Tesouro Direto**, **Renda Fixa**) e preserva as datas originais do arquivo (inclusive formato serial do Excel).
4. Escolha como tratar o caixa da conta:
   - **Deixar desmarcado** se você quer apenas registrar os ativos sem mexer no saldo atual da conta; ou
   - **Marcar "Converter saldo atual da conta em Posição Inicial (Transferência -)"** para abater o valor aplicado do caixa da conta com um único lançamento `Transferência (-)`. Assim, `Caixa Livre + Ativos Atualizados` reflete exatamente o seu patrimônio real na corretora, sem dupla contagem.

#### Opção B: Cadastrar Posição Inicial manualmente
1. Clique em **+ Novo Ativo**, preencha **Classe**, **Ticker** (ex: `PETR4`, `HGLG11`, `BTC`, `USDC`, `CDB Inter 110% CDI`), **Nome**, **Moeda** e **Corretora de Custódia**.
2. Clique em **+ Nova Operação**, escolha **Posição Inicial**, informe **Data** (digite apenas os números que as `/` são inseridas automaticamente), **Quantidade** e **Preço Unitário** (ou **Total da Operação**).
3. Marque **"Converter saldo da conta Investimento (Transferência -)"** caso o valor já esteja somado no saldo antigo da conta.

---

## 2. Operações do Dia a Dia e Exemplos Práticos

### Exemplo 1: Compra e Venda de Ações / FIIs (sem poluir Relatórios)
- Ao registrar uma **Compra** com **"Movimentar caixa da conta selecionada"** ativado, o OpenMoney debita o valor total (incluindo corretagem/taxas) da conta escolhida usando a categoria **`Transferência (-)`**.
- Ao registrar uma **Venda**, a quantidade disponível em custódia já vem **pré-preenchida e editável**; o crédito cai na conta usando **`Transferência (+)`**.
- Por usarem categorias de transferência, compras e vendas **não distorcem** suas despesas, receitas, orçamentos ou Fluxo de Caixa.

### Exemplo 2: Criptomoedas (`BTC`, `USDC`, `ETH`, `SOL`) com edição pelo Total
- Para **Criptomoedas**, o campo **Quantidade** suporta até **8 casas decimais** (ex: `10,036` USDC ou `0,00452100` BTC), sem alterar a precisão de **2 casas decimais** (centavos) dos valores financeiros e saldos das contas.
- **Preenchimento bidirecional:** você pode informar `Quantidade` e `Preço Unitário` (ex: `10,036 × 5,5639697 → R$ 55,84`) **ou** digitar `Quantidade` e editar diretamente o campo **Total da Operação** (ex: `55,84`) para que o preço unitário seja recalculado automaticamente.

### Exemplo 3: Venda / Resgate de Renda Fixa e Tesouro Direto com IR Regressivo
- Para títulos tributados (**CDB**, **RDB**, **LC**, **Debêntures comuns**, **Tesouro Direto**), ao selecionar **Venda**:
  1. Informe o **Valor Bruto da Venda** (e a quantidade — já pré-preenchida com o total disponível).
  2. O campo **IR Retido na Fonte** é **pré-preenchido automaticamente** em ordem FIFO pela Tabela Regressiva de IR (contando dias corridos a partir da data de cada aporte: `22,5%` até 180d, `20,0%` de 181 a 360d, `17,5%` de 361 a 720d, `15,0%` acima de 720d), exibindo a alíquota e o valor líquido estimado.
  3. Confira ou ajuste o valor do IR se necessário e escolha a **Categoria do lançamento de IR** (padrão **`Investimentos (-) › IR`**, criada automaticamente se ainda não existir).
  4. Ao salvar com movimentação de caixa ativa, o OpenMoney gera o crédito bruto (`Transferência (+)`) e o débito do IR (`IR Resgate <Ativo>`), resultando no valor líquido exato na conta destino.
- Títulos isentos (**LCI**, **LCA**, **CRI**, **CRA**) têm IR zerado automaticamente.

### Exemplo 4: Proventos (Dividendos, JCP, Rendimentos FII)
- Lance como **Dividendo**, **JCP** ou **Rendimento**.
- Ao movimentar caixa, o crédito usa por padrão a categoria configurável **`Investimentos (-) › Rendimentos`**.

---

## 3. Multi-Corretora, Detalhes, Inativação e Exclusão

- **Mesmo ativo em mais de uma corretora:** a custódia fica vinculada à **operação**. Você pode comprar `PETR4` na XP e também na Rico usando o seletor **"Conta / Corretora de Custódia"** em cada operação. O filtro por corretora mostra a posição individual de cada conta, enquanto a visão geral consolida seu Preço Médio unificado.
- **Ver e editar movimentações de um ativo:** clique diretamente sobre o nome/código do ativo na tabela **Posição Atual** (ou no card no mobile) para abrir o histórico completo do título, com botões para **Editar** ou **Excluir** qualquer operação.
- **Inativar ou Excluir um ativo:** abra **Editar Ativo** para ativar **"Ativo inativo (arquivado)"** (oculta da lista principal e de novos lançamentos, preservando o histórico; pode ser exibido pelo filtro **"Mostrar inativos"**) ou clique em **Excluir Ativo** (com opção de remover também os lançamentos vinculados no caixa).

---

## 4. Cotações Automáticas, Preço Manual e Relatórios

- **Atualização automática (botão `Cotações`):**
  - **Ações, FIIs, ETFs, BDRs:** Yahoo Finance (B3 `.SA` e exterior).
  - **Criptomoedas (`BTC`, `USDC`, `ETH`, etc.):** cadeia automática **Binance → Coinbase → Mercado Bitcoin → CoinGecko → AwesomeAPI → Yahoo Finance**.
  - **Indicadores Renda Fixa:** **CDI**, **Selic** e **IPCA** oficiais do Banco Central (BCB SGS).
- **Edição manual de preço:** clique sobre o preço na coluna **Preço Atual** para editar manualmente (exibe badge **`M`**). Para reativar a atualização automática, clique no preço e selecione **"Voltar p/ Automático"**.
- **Relatórios e Exportação:**
  - **Posição Atual:** exibe Ativo, Classe, Qtde, Valor Compra (Aplicado), PM Compra, PM Venda, Preço Atualizado, Valor Atual, Rentabilidade (R$ e %) e Proventos.
  - **Renda Fixa & Tesouro:** exibe indexador, vencimento, dias corridos, bruto atual, IR estimado e valor líquido.
  - **Análise & Alocação:** gráfico de alocação por classe (`fl_chart`).
  - **Exportação:** botões **PDF** (relatório A4 Paisagem) e **CSV** completo (incluindo coluna **`Corretora / Conta`** e todas as métricas).

---

## 5. Perguntas Frequentes (FAQ)

- **Como o saldo da minha conta de Investimentos aparece no Dashboard e no menu lateral?**  
  O saldo exibido é **`Caixa Livre + Valor Atualizado dos Ativos`**. Sempre que as cotações sobem/caem ou são editadas manualmente, o saldo total da conta e o **Patrimônio Líquido Total** são atualizados na hora.
- **Preciso criar um ativo de Renda Fixa novo a cada aporte?**  
  Se for o **mesmo título** (ex: vários aportes no mesmo *Tesouro Selic 2029* ou *CDB Liquidez Diária 100% CDI*), **não precisa** — lance todas as compras no mesmo ativo, pois o motor controla lote a lote com a data de cada aporte. Crie ativos separados apenas para títulos com emissor, taxa, indexador ou vencimento diferentes.
- **A venda altera meu Preço Médio de Compra?**  
  Não. Seguindo a regra contábil e fiscal padrão, a venda mantém o Preço Médio de Compra inalterado, apura o **Lucro/Prejuízo Realizado** e calcula o **Preço Médio de Venda**.

---

## 6. Detalhes Técnicos (Desenvolvedores)

- **Schema `v: 7` (`openmoney.json`):** campos opcionais `investAssets`, `investOps`, `investIndicators` no objeto `Database`, e `investOpId` em `Transaction` (omitidos quando vazios/nulos). Ver [Dicionário de Dados](../architecture/dicionario-de-dados.md) e [ADR 039](../adr/039-investment-portfolio-management.md).
- **Cloud Sync v2:** coleções granulares `investAssets/<id>`, `investOps/<id>` e `meta/investIndicators` sincronizadas via WebSocket/D1 entre Desktop, Web e Mobile.
- **Proxy CORS (Web):** endpoints `GET /api/market/quotes` e `GET /api/market/indicators` em Cloudflare Pages Functions (`functions/api/[[route]].js`).
