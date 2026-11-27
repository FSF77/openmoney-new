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

#### Opção C: Migração limpa quando a conta já tem saldo histórico (sem mexer no passado)
Se você já transferia dinheiro da Conta Corrente (ex: *Nubank*) para a Conta Investimento (*Nubank Investimentos*) antes deste módulo existir, o extrato da conta de investimentos já acumula esse saldo histórico (inclusive eventuais rendimentos lançados no passado):
1. No extrato da conta de investimentos, faça **1 único lançamento de ajuste negativo** na data de hoje no valor já aplicado (ex: `-R$ 200.000,00`), deixando no extrato apenas o **caixa livre real** parado hoje (geralmente `R$ 0,00`).
2. **Importante:** use para esse ajuste uma categoria com **"Incluir em relatórios" DESMARCADO** (ex: `Investimentos (-) › Ajuste de Carteira`), para não distorcer despesas ou gráficos do mês.
3. Em seguida, cadastre todos os seus títulos antigos como **Posição Inicial** com **"Movimentar caixa da conta selecionada" DESMARCADO**. Ao final, `Caixa Livre + Carteira Atualizada` refletirá exatamente o seu patrimônio real sem duplicação.

### Rotina do dia a dia (daqui para frente)
1. **Antes ou no momento de aplicar:** faça uma **Transferência** da sua Conta Corrente (ex: *Nubank*) para a Conta Investimento (*Nubank Investimentos*).
2. **Ao comprar o ativo:** lance a **Compra** na tela de **Investimentos** selecionando a conta *Nubank Investimentos* e deixando **"Movimentar caixa da conta selecionada" MARCADO**. O dinheiro sai do caixa livre da corretora e passa a compor sua carteira de ativos.
3. **Ao resgatar ou receber proventos:** lance a **Venda** ou **Dividendo/JCP/Rendimento** com **"Movimentar caixa" MARCADO** para creditar o valor na conta da corretora; quando enviar de volta ao banco, faça uma **Transferência** da corretora para a conta corrente.

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

### Exemplo 4: Proventos e Agendamento Automático B3 (FIIs e Ações)
- Lance manualmente como **Dividendo**, **JCP** ou **Rendimento**, ou clique em **Proventos B3** no cabeçalho da tela de Investimentos.
- Em **Proventos B3**, o OpenMoney consulta automaticamente na **B3** os dividendos, JCP e rendimentos anunciados para todos os seus **FIIs e Ações B3 ativos**, multiplica pela quantidade que você possuía na **Data-Com** em cada corretora (aplicando automaticamente o desconto de **15% de IR na fonte** no caso de JCP) e agenda o lançamento pendente na **Agenda** para a data de pagamento (sem duplicar proventos já lançados).
- A categoria padrão é **`Investimentos (+) › Dividendos`** (customizável diretamente no modal de agendamento ou nos lançamentos de proventos).

---

## 3. Multi-Corretora, Detalhes, Inativação e Exclusão

- **Mesmo ativo em mais de uma corretora:** a custódia fica vinculada à **operação**. Você pode comprar `PETR4` na XP e também na Rico usando o seletor **"Conta / Corretora de Custódia"** em cada operação. O filtro por corretora mostra a posição individual de cada conta, enquanto a visão geral consolida seu Preço Médio unificado.
- **Ver e editar movimentações de um ativo:** clique diretamente sobre o nome/código do ativo na tabela **Posição Atual** (ou no card no mobile) para abrir o histórico completo do título, com botões para **Editar** ou **Excluir** qualquer operação (sempre com confirmação).
- **Inativar ou Excluir um ativo:** abra **Editar Ativo** para ativar **"Ativo inativo (arquivado)"** (oculta da lista principal e de novos lançamentos, preservando o histórico; pode ser exibido pelo filtro **"Mostrar inativos"**) ou clique em **Excluir Ativo** (com opção de remover também os lançamentos vinculados no caixa).

---

## 4. Cotações Automáticas, Preço Manual, ANBIMA e Relatórios

- **Atualização automática (botão `Cotações`):**
  - **Ações, FIIs, ETFs, BDRs:** Yahoo Finance (B3 `.SA` e exterior).
  - **Tesouro Direto (Marcação a Mercado):** busca automática do **PU de Resgate oficial (`PU Venda`)** no **Tesouro Transparente (Gov.br)**. Você pode cadastrar múltiplos títulos com suas taxas no nome (ex: `TESOURO IPCA+ 2029 / IPCA + 7,89%`, `TESOURO IPCA+ 2040 / IPCA + 6,91%`, `Tesouro Prefixado 2032`, `Tesouro Selic 2029`) — basta conter o **tipo** (`IPCA+`, `Prefixado`, `Selic`, `Renda+`, `Educa+`, com ou sem `Juros Semestrais`) e o **ano** (no nome ou no campo Vencimento) para atualizar automaticamente.
  - **Criptomoedas (`BTC`, `USDC`, `ETH`, etc.):** cadeia automática **Binance → Coinbase → Mercado Bitcoin → CoinGecko → AwesomeAPI → Yahoo Finance**.
  - **Indicadores Renda Fixa:** **CDI**, **Selic**, **IPCA** e a **série histórica diária oficial do CDI** (BCB SGS `12`), além do **calendário bancário oficial ANBIMA** embutido (descontando fins de semana e feriados nacionais como Carnaval, Sexta-Feira Santa, Corpus Christi e 20/11). Com isso, CDBs pós-fixados acompanham automaticamente as mudanças da taxa do CDI dia a dia, e CDBs pré-fixados/IPCA+ contam os dias úteis bancários exatos.
- **Saldo Bruto como padrão (com Líquido e IR complementar):**
  - Assim como os bancos e corretoras, a coluna **Valor Atual**, os cards de resumo e o patrimônio total exibem o **Valor Bruto** atualizado do ativo.
  - Quando há IR estimado (ex: CDBs e Tesouro Direto), o **Valor Líquido Estimado** e o **IR Estimado** aparecem logo abaixo como informação complementar e na aba **Renda Fixa & Tesouro**.
- **Edição manual de preço:** clique sobre o preço na coluna **Preço Atual** para editar manualmente (exibe badge **`M`**). Para reativar a atualização automática, clique no preço e selecione **"Voltar p/ Automático"**.
- **Ordenação, Filtros e Responsividade:**
  - A tabela sempre abre ordenada por **Ativo (A → Z)** e permite clicar em qualquer coluna (ou usar o seletor **Ordenar por**) para ordenar por Ativo, Classe, Quantidade, Valores, Rentabilidade ou Proventos.
  - Em telas menores e dispositivos móveis, os 6 botões superiores aparecem como ícones compactos com `Tooltip`, os cartões de resumo se organizam lado a lado em grade **2×2** recolhível e a barra de filtros pode ser ocultada/expandida com 1 toque.
- **Relatórios e Exportação:**
  - **Posição Atual:** exibe Ativo, Classe, Qtde, Valor Compra (Aplicado), PM Compra, PM Venda, Preço Atualizado, Valor Atual Bruto (com Líquido estimado em Renda Fixa), Rentabilidade (R$ e %) e Proventos.
  - **Renda Fixa & Tesouro:** exibe indexador, vencimento, dias corridos, valor bruto atual, valor líquido estimado, IR estimado e valor aplicado.
  - **Análise & Alocação:** gráfico de alocação por classe (`fl_chart`).
  - **Exportação:** botão **PDF** (relatório A4 Paisagem) e botão **CSV** com opção de escolher entre **Posição Consolidada** (resumo atual por ativo) ou **Operações Detalhadas** (histórico cronológico completo de todas as compras, vendas, proventos, taxas e IR), ambos compatíveis com Excel no macOS e Windows (UTF-8 BOM).

---

## 5. Perguntas Frequentes (FAQ)

- **Como o saldo da minha conta de Investimentos aparece no Dashboard e no menu lateral?**  
  O saldo exibido é **`Caixa Livre + Valor Atualizado Bruto dos Ativos`**. Sempre que as cotações sobem/caem ou são editadas manualmente, o saldo total da conta e o **Patrimônio Líquido Total** são atualizados na hora.
- **Preciso criar um ativo de Renda Fixa novo a cada aporte?**  
  Se for o **mesmo título** (ex: vários aportes no mesmo *Tesouro Selic 2029* ou *CDB Liquidez Diária 100% CDI*), **não precisa** — lance todas as compras no mesmo ativo, pois o motor controla lote a lote com a data de cada aporte. Crie ativos separados apenas para títulos com emissor, taxa, indexador ou vencimento diferentes.
- **A venda altera meu Preço Médio de Compra?**  
  Não. Seguindo a regra contábil e fiscal padrão, a venda mantém o Preço Médio de Compra inalterado, apura o **Lucro/Prejuízo Realizado** e calcula o **Preço Médio de Venda**.

---

## 6. Detalhes Técnicos (Desenvolvedores)

- **Schema `v: 7` (`openmoney.json`):** campos opcionais `investAssets`, `investOps`, `investIndicators` (incluindo `cdiDailySeries`) no objeto `Database`, e `investOpId` em `Transaction` (omitidos quando vazios/nulos). Ver [Dicionário de Dados](../architecture/dicionario-de-dados.md) e [ADR 039](../adr/039-investment-portfolio-management.md).
- **Cloud Sync v2:** coleções granulares `investAssets/<id>`, `investOps/<id>` e `meta/investIndicators` sincronizadas via WebSocket/D1 entre Desktop, Web e Mobile.
- **Proxy CORS (Web):** endpoints `GET /api/market/quotes` e `GET /api/market/indicators?cdiFrom=YYYY-MM-DD` em Cloudflare Pages Functions (`functions/api/[[route]].js`).
