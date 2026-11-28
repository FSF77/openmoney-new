# ADR 018: Arquitetura Multi-Moeda, Câmbio em Transferências e Cotações Históricas

**Status:** ✅ Aprovado, Implementado e Validado (Flutter Multiplataforma + Swift macOS & iOS)  
**Data:** 11/11/2026  
**Decisores:** Arquitetura OpenMoney  
**Escopo:** Schema `v: 7`, Motor de Câmbio Diário e Histórico (`CurrencyRateService`), Relatórios, Fluxo de Caixa, CSV Export/Import e UI Multi-Stack  

---

## 1. Contexto e Motivação

O **OpenMoney** operava originalmente assumindo uma única moeda implícita (Real Brasileiro — `BRL`). Com a necessidade de controlar contas no exterior, carteiras em espécie em viagens e cartões internacionais sem perder a visão consolidada do patrimônio, identificaram-se os seguintes requisitos:

1. **Contas em Múltiplas Moedas:** Permitir que cada conta opere em uma moeda própria (`BRL`, `USD`, `EUR`, `CAD`, `AUD`, `GBP`, `PYG`, `ARS`, `UYU`, `CHF`, `CLP`), mantendo os valores nominais (`opening`, `Transaction.amt`) exatamente na moeda da conta.
2. **Moeda Padrão / Base Configurável:** Embora o `BRL` seja o padrão inicial, qualquer moeda suportada deve poder ser definida como `baseCurrency` do sistema em **Ajustes & Personalização → Moedas & Cotações**.
3. **Economia de Requisições Online (Regra Diária):** Evitar consultas repetitivas a APIs gratuitas a cada tela ou lançamento, realizando atualização automática no máximo **1 vez a cada 24 horas** e somente quando existirem contas ativas em moeda diferente da moeda base, com suporte a cotação manual persistente e data da última atualização visível na interface.
4. **Fidelidade de Câmbio em Transferências:** Transferências entre contas de moedas distintas (ex.: `BRL → USD`) possuem IOF, spread bancário ou taxa negociada na época. O sistema deve sugerir os valores pela cotação do dia/data, permitir ajuste livre nos dois campos (valor de origem/destino e taxa) e gravar a taxa efetiva da operação.
5. **Fidelidade Histórica de Lançamentos Passados:** Lançamentos antigos (ex.: despesas de **2012** em uma conta `USD`) não podem aparecer convertidos pela taxa de hoje nos relatórios, fluxo de caixa e listas históricas. O usuário precisa tanto de **sugestão histórica automática** (transferência de câmbio da época + consulta oficial histórica no Banco Central / AwesomeAPI) quanto de **campo editável por lançamento** e **ferramenta de correção em lote** (`Corrigir Passados`) para registros já cadastrados.
6. **Preservação em CSV:** Exportações e importações CSV devem incluir valor oficial na moeda da conta, valor convertido na moeda base, taxa de câmbio e dados completos da contrapartida de transferências entre moedas.

---

## 2. Decisão Arquitetural e Invariante Canônico (Schema `v: 7`)

Para manter **100% de compatibilidade retroativa com o Schema `v: 7`** sem exigir versão `v: 8` nem quebrar leitores antigos ou a liberdade de o usuário trocar sua `baseCurrency` a qualquer momento, adotaram-se as seguintes decisões estruturais em `openmoney.json`:

### 2.1. Extensões Retrocompatíveis no Schema `v: 7`

| Entidade | Campo | Tipo | Padrão / Omissão | Papel Semântico |
| :--- | :--- | :--- | :--- | :--- |
| `Database` | `baseCurrency` | `String?` | `"BRL"` | Moeda padrão/base de consolidação exibida em dashboards, somatórios e relatórios globais. |
| `Database` | `rates` | `Map<String, CurrencyRateInfo>?` | `{}` | Cotações correntes persistidas em relação ao `BRL`, contendo `rate` (`Double`), `updatedAt` (`String` ISO 8601), `manual` (`Bool?`) e `source` (`String?`). |
| `Account` | `currency` | `String?` | `"BRL"` | Moeda contábil exclusiva da conta. Todos os `amt` e `opening` dessa conta estão nesta moeda. |
| `Transaction` | `rate` | `Double?` | `null` | Taxa histórica registrada na transação no instante do lançamento ou transferência. |

### 2.2. O Invariante Canônico de `Transaction.rate` (`Moeda da Conta → BRL`)

> **Regra Invariante:** O campo `Transaction.rate` é **SEMPRE** persistido como a taxa de conversão **da moeda da conta para `BRL`** (`1 unidade da moeda da conta = rate BRL`), **independentemente de qual seja a `baseCurrency` configurada pelo usuário**.

**Por que essa decisão é crítica:**
- **Imunidade à mudança de moeda base:** Se o usuário definir `baseCurrency = "USD"` hoje e voltar para `"BRL"` ou `"EUR"` no futuro, as taxas históricas gravadas em cada transação continuam matematicamente válidas.
- **Triangulação uniforme:** Para exibir um lançamento `tx` (em moeda `A`) na moeda destino `B` (por exemplo `baseCurrency` ou moeda da conta destino):
  - Se $A = B$: fator $= 1{,}0$.
  - Obtém-se $\text{rateToBrl}(A)$ usando primeiramente `tx.rate` (quando positivo e `A != "BRL"`), ou a cotação corrente em `Database.rates[A]` / fallback.
  - Obtém-se $\text{rateToBrl}(B)$ de `Database.rates[B]` (ou $1{,}0$ se $B = \text{"BRL"}$).
  - Valor convertido considerando diferentes casas decimais (`decimals` de $A$ e $B$, ex.: `PYG`/`CLP` com `0` casas vs `USD`/`BRL` com `2` casas):

$$\text{factor} = \frac{\text{rateToBrl}(A)}{\text{rateToBrl}(B)}, \quad \text{minorScale} = \frac{10^{\text{decimals}(B)}}{10^{\text{decimals}(A)}}, \quad \text{convertedMinor} = \operatorname{round}(\text{amt} \times \text{factor} \times \text{minorScale})$$

- **Tradução UI ↔ Armazenamento (`brlRateToUiRate` / `uiRateToBrlRate`):** Na interface de lançamento/edição, o campo editável exibe e aceita `1 <moeda da conta> = ? <baseCurrency>` para leitura natural do usuário; ao gravar, o sistema converte `uiRate` para `brlRate` quando `baseCurrency != "BRL"`.

---

## 3. Catálogo de Moedas Suportadas (`11 moedas`)

Implementado de forma idêntica em `kSupportedCurrencies` (`openmoney_models.dart`) e `SUPPORTED_CURRENCIES` (`Models.swift`):

| Código | Símbolo | Moeda | Bandeira | Decimais |
| :--- | :--- | :--- | :---: | :---: |
| `BRL` | `R$` | Real Brasileiro | 🇧🇷 | `2` |
| `USD` | `US$` | Dólar Americano | 🇺🇸 | `2` |
| `EUR` | `€` | Euro | 🇪🇺 | `2` |
| `CAD` | `C$` | Dólar Canadense | 🇨🇦 | `2` |
| `AUD` | `A$` | Dólar Australiano | 🇦🇺 | `2` |
| `GBP` | `£` | Libra Esterlina | 🇬🇧 | `2` |
| `PYG` | `₲` | Guarani Paraguaio | 🇵🇾 | `0` |
| `ARS` | `ARS$` | Peso Argentino | 🇦🇷 | `2` |
| `UYU` | `$U` | Peso Uruguaio | 🇺🇾 | `2` |
| `CHF` | `CHF` | Franco Suíço | 🇨🇭 | `2` |
| `CLP` | `CLP$` | Peso Chileno | 🇨🇱 | `0` |

---

## 4. Cotações Diárias: Atualização Automática, Cache Local e Modo Manual

Para evitar bloqueio por *rate limit* nas APIs gratuitas:

1. **Verificação `shouldRefreshOnline(db)`:**
   - Retorna `false` imediatamente se **todas** as contas ativas estiverem na `baseCurrency` do usuário.
   - Caso exista ao menos uma conta ativa estrangeira (`acc.effectiveCurrency != baseCurrency`), verifica se alguma moeda ativa está sem cotação ou com `updatedAt` anterior a **24 horas**.
   - Se já atualizada dentro das últimas 24h, nenhuma requisição de rede é disparada ao abrir o aplicativo.
2. **Endpoint de Cotação Diária:**
   - `https://economia.awesomeapi.com.br/last/USD-BRL,EUR-BRL,CAD-BRL,AUD-BRL,GBP-BRL,PYG-BRL,ARS-BRL,UYU-BRL,CHF-BRL,CLP-BRL`
3. **Preservação do Modo Manual (`manual: true`):**
   - Cotações editadas manualmente pelo usuário em **Ajustes & Personalização → Moedas & Cotações** exibem selo `Manual` + data da última alteração e **não são sobrescritas** pelo refresh automático diário até que o usuário clique explicitamente em **Auto**.
4. **Atualização sob Demanda:**
   - Botão **Atualizar Agora** força consulta online para moedas automáticas e atualiza `updatedAt`.

---

## 5. Solução Híbrida para Cotações Históricas por Lançamento

### 5.1. O Problema Original (Exemplo de 2012)

Se um usuário cadastra despesas de **2012** em uma conta em `USD`, a gravação de `tx.rate` com a cotação corrente de hoje (ex.: `R$ 5,75`) distorce todos os relatórios históricos e fluxos de caixa desse período. Além disso, muitas compras de dólar da época tiveram taxa manual em transferências (`BRL → USD`) que incluíam IOF/spread.

### 5.2. Fluxo de Resolução de Prioridades (`resolveDefaultRateToBrl`)

```
Lançamento não-transferência em conta estrangeira (data D)
   │
   ├──► 1. Transferência de Câmbio na Conta (<= D)?
   │         └─ lastTransferRateForAccount(accId, onOrBeforeDate: D)
   │            (Prioriza entradas de câmbio na conta e desempata por proximidade de data)
   │         └─ Encontrada? ──► Usa rateToBrl da transferência!
   │
   ├──► 2. Cache / Consulta Histórica Oficial (D < Hoje)?
   │         └─ Primária: Banco Central do Brasil Olinda PTAX (CotacaoMoedaPeriodo)
   │            • Janela de 7 dias anteriores a D (cobre fins de semana e feriados)
   │            • Prefere boletim "Fechamento" e campo `cotacaoVenda` (fallback `cotacaoCompra`)
   │         └─ Fallback: AwesomeAPI diária (/json/daily/<CUR>-BRL/10?start_date=...&end_date=...)
   │         └─ Cache em memória + deduplicação de requests simultâneos em voo
   │
   └──► 3. Fallback Corrente:
             └─ Database.rates[currency] (ou kFallbackRatesBrl / FALLBACK_RATES_BRL)
```

### 5.3. Campo Editável e Atalhos na UI

1. **Modais de Novo Lançamento, Edição e Cópia (`_ForeignTransactionRateBox` no Flutter / `ForeignTransactionRatePanel` no Swift macOS & iOS):**
   - Exibido automaticamente sempre que `!isCrossCurrencyTransfer && !isTransfer && accountCurrency != "BRL" && accountCurrency != baseCurrency`.
   - Campo numérico editável `1 <moeda> = ? <baseCurrency>` com cálculo em tempo real `≈ <valor na moeda base>`.
   - **Chips / Botões de sugestão rápida:**
     - **Transf. (data)** *(quando houver transferência cross-currency anterior na conta)*;
     - **Buscar BCB (data)** *(para datas passadas, consulta PTAX/AwesomeAPI e aplica sem precisar sair da tela)*;
     - **Atual** *(aplica a cotação corrente cadastrada)*.
   - **Proteção na Edição (`preserveInitialValue: true`):** Ao abrir um lançamento existente para edição, a taxa já salva (`tx.rate`) é preservada e exibida exatamente como gravada, evitando sobrescrita acidental ao simplesmente abrir a janela; a sugestão só é recalculada se o usuário trocar a conta, a data ou clicar nos chips.
2. **Barra de Lançamento Rápido da Conta (Desktop Flutter & Swift macOS):**
   - Ao lado do campo `Valor` em contas estrangeiras diferentes da `baseCurrency`, exibe campo compacto **Taxa (`<base>`)** sincronizado reativamente quando a data ou a conta muda (inclusive disparando consulta PTAX assíncrona em segundo plano caso o usuário digite uma data passada sem transferência prévia e ainda não tenha editado o campo manualmente).
3. **Transferências entre Moedas (`_CrossCurrencyTransferBox` / `CrossCurrencyTransferPanel`):**
   - Permite edição bidirecional da taxa e do valor recebido na conta destino.
   - Em datas passadas (`dateIso < todayISO`), exibe botão **BCB (data)** para buscar o câmbio oficial da data da transferência.

### 5.4. Correção em Lote de Lançamentos Antigos (`Corrigir Passados`)

Em **Ajustes & Personalização → Moedas & Cotações**:
- **`countPastForeignTransactionsForRateSync()`:** Conta lançamentos não-transferência em moedas estrangeiras com `date < hoje`.
- **`recalculatePastTransactionRates()`:** Para cada lançamento antigo elegível:
  1. Tenta resolver via `lastTransferRateForAccount(tx.acc, onOrBeforeDate: tx.date)`.
  2. Se não houver transferência até a data, consulta `fetchHistoricalRateToBrl(accCur, tx.date)` (usando o cache em memória para não repetir chamadas HTTP para a mesma moeda + data).
  3. Atualiza `tx.rate` apenas quando houver diferença superior a `0.00005`, persiste com `save()`, reindexa e registra evento de auditoria (`AuditLogManager`).

---

## 6. Regras de Exibição em Dashboards, Extratos, Relatórios, Fluxo de Caixa e CSV

### 6.1. Saldos e Dashboards
- **Contas Individuais / Extratos / Faturas:** Valores principais sempre na **moeda da conta**; quando `accountCurrency != baseCurrency`, exibe linha discreta `≈ <valor convertido para baseCurrency>`.
- **Patrimônio Consolidado & Cards Globais:** Somatório de todas as contas ativas sempre convertido para a `baseCurrency` configurada.

### 6.2. Relatórios Mensais/Anuais e Fluxo de Caixa (`≈` Histórico vs Saldo Atual)
- **Filtro Global ou Múltiplas Moedas:**
  - **Receitas, Despesas e Categorias:** Consolidação na `baseCurrency` utilizando o `tx.rate` histórico de cada lançamento.
  - **Saldos Acumulados no Fluxo de Caixa (`Saldo Anterior Acumulado` e `Saldo Final Acumulado`):** Acumulam o saldo de cada conta em sua **moeda nativa** (`a.opening + movimentações nativas + valor de mercado de investimentos`) e convertem o saldo acumulado de cada conta para a `targetCurrency` utilizando a **cotação corrente** (`Database.rates`), garantindo paridade exata ao centavo com `MoneyStore.totalBalance` mesmo quando há lançamentos antigos em `USD`/`EUR` com `tx.rate` histórico diferente da cotação de hoje.
- **Filtro por Conta ou Contas de Mesma Moeda Estrangeira:**
  - Os totais principais (categorias, meses, receitas, despesas e resultado) são exibidos diretamente na **moeda da conta filtrada** (`USD`, `EUR`, etc.).
  - Os subtítulos `≈` dos cards KPI (`Total de Receitas`, `Total de Despesas`, `Resultado Líquido` / `Saldo do Mês/Ano`) utilizam **`totalIncomeInBase`, `totalExpenseInBase` e `netTotalInBase` / `netGrandTotalInBase`**, calculados somando cada transação convertida pelo seu respectivo `tx.rate` histórico (e não convertendo o total agregado pela taxa atual).
  - *Nota contábil:* Quando o filtro seleciona uma conta única, transferências de entrada/saída dessa conta integram os totais líquidos utilizando exatamente a taxa efetiva da transferência registrada no par.

### 6.3. Exportação e Importação CSV (`17 colunas`)

Cabeçalho unificado nas duas stacks:
```
"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura";"Conta Favorita";"Conta Ativa";"Moeda";"Moeda Padrão";"Valor Moeda Padrão";"Taxa Câmbio";"Valor Contrapartida";"Moeda Contrapartida";"Taxa Transferência"
```
- `Valor`: valor oficial na moeda da conta.
- `Moeda` / `Moeda Padrão` / `Valor Moeda Padrão` / `Taxa Câmbio`: preservam integralmente moeda original, equivalente histórico convertido na moeda base (`tx.rate`) e fator de conversão utilizado.
- `Valor Contrapartida` / `Moeda Contrapartida` / `Taxa Transferência`: preservam os dois lados e a taxa efetiva de transferências cross-currency tanto na exportação quanto na reimportação.

---

## 7. Mapeamento de Arquivos por Plataforma

| Camada | Swift (`OpenMoneySwift` — macOS & iOS) | Flutter (`OpenMoneyFlutter` — Desktop, Web & Mobile) |
| :--- | :--- | :--- |
| Modelos & Schema `v: 7` | [`Sources/OpenMoney/Models.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Models.swift) | [`lib/models/openmoney_models.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/models/openmoney_models.dart) |
| Motor de Cotações Diárias e Históricas | [`Sources/OpenMoney/Store.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Store.swift) (`CurrencyRateService`) | [`lib/services/currency_rate_service.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/services/currency_rate_service.dart) |
| Store & Resolução Histórica | [`Sources/OpenMoney/Store.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Store.swift) (`MoneyStore`) | [`lib/store/money_store.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/store/money_store.dart) |
| Fluxo de Caixa Histórico | [`Sources/OpenMoney/ImportersExporters.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/ImportersExporters.swift) (`CashFlowEngine`) | [`lib/services/cash_flow_engine.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/services/cash_flow_engine.dart) |
| CSV Export & Import | [`Sources/OpenMoney/ImportersExporters.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/ImportersExporters.swift) | [`lib/services/importers_exporters.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/services/importers_exporters.dart) |
| Configurações ("Moedas & Cotações") | [`Sources/OpenMoney/SettingsView.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/SettingsView.swift) | [`lib/ui/views/settings_view.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/ui/views/settings_view.dart) |
| Lançamentos, Edição, Cópia e Rápido | [`Sources/OpenMoney/Views.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Views.swift), [`Sources/OpenMoney/iOSViews.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/iOSViews.swift) | [`lib/ui/modals/transaction_modal.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/ui/modals/transaction_modal.dart), [`lib/ui/views/account_ledger_view.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/ui/views/account_ledger_view.dart) |
| Relatórios & Fluxo UI | [`Sources/OpenMoney/Views.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Views.swift), [`Sources/OpenMoney/iOSViews.swift`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/iOSViews.swift) | [`lib/ui/views/reports_view.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/ui/views/reports_view.dart), [`lib/ui/views/cash_flow_view.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/ui/views/cash_flow_view.dart) |
| Testes Automatizados | Build validado via `swift build` e `xcodebuild` (iOS) | [`test/multi_currency_test.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/test/multi_currency_test.dart) |
