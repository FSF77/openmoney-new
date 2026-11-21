# ADR 034: Validação Estrita de Datas, Alertas de Janela Temporal e Exclusão de Previsões no Autocompletar

## Status
**Aprovado e Implementado** (Novembro/2026)

---

## Contexto

Durante a inserção e edição de lançamentos financeiros no ecossistema OpenMoney, identificaram-se duas necessidades cruciais para assegurar a integridade e a usabilidade do cadastro de transações:

1. **Prevenção de Inclusão de Lançamentos em Datas Inválidas ou Erradas:**
   - Ao digitar datas manualmente, erros de digitação poderiam gerar datas inexistentes no calendário (como `31/02/2026`, `31/04/2026` ou anos bissextos incorretos).
   - Além disso, lapsos na digitação do ano (ex.: digitar ano anterior acidentalmente ou décadas à frente) poderiam criar lançamentos distantes do fluxo corrente sem percepção imediata do usuário.
   - Havia a necessidade de alertar preventivamente quando a data informada fosse anterior a mais de 30 dias da data atual, ou posterior a mais de 12 meses da data atual, solicitando confirmação explícita antes de persistir o registro.

2. **Poluição de Sugestões de Favorecido por Lançamentos de Previsão Orçamentária:**
   - O aplicativo calcula e exibe previsões orçamentárias automáticas baseadas em metas ou despesas/receitas recorrentes (registros iniciados por `"Previsão"` / `"Previsao"`).
   - Ao digitar o campo "Favorecido / Descrição" em novos lançamentos ou na barra rápida, essas previsões eram retornadas nas listas de sugestões e ativavam o preenchimento automático de categoria/tipo, causando ruído para lançamentos manuais reais.

---

## Decisão e Arquitetura

### 1. Validação Estrita de Datas e Teclado Numérico Mobile (`date_validator.dart` e `DateInputFormatter`)

1. **Teclado Numérico Direto em Dispositivos Móveis (Smartphone, iPad e Tablets):**
   - Todos os campos de **Data** utilizam `keyboardType: TextInputType.number` (visto que o `DateInputFormatter` insere as barras `/` automaticamente), abrindo diretamente o teclado numérico nos sistemas iOS, iPadOS e Android (nativo e Web PWA) em vez do teclado alfanumérico padrão de `TextInputType.datetime`.
   - Todos os campos de **Valor** utilizam `keyboardType: const TextInputType.numberWithOptions(decimal: true)`, abrindo diretamente o teclado numérico com separador decimal em dispositivos móveis, enquanto mantêm suporte ao botão da Mini Calculadora integrada e expressões matemáticas via teclado físico no Desktop.
2. **Clamping Ativo durante a Digitação (`DateInputFormatter`):**
   - No preenchimento automático das barras (`DD/MM/AAAA`), o formatador intercepta e ajusta imediatamente valores inviáveis:
     - Dia inicial limitado a no máximo `31`.
     - Mês limitado a no máximo `12`.
     - Dias de Fevereiro ajustados para no máximo `29` antes de definir o ano e validados com o ano quando bissexto.
2. **Validador Completo de Calendário (`validateTransactionDate`):**
   - Converte strings no formato brasileiro `DD/MM/AAAA` ou ISO `AAAA-MM-DD` para `DateTime`.
   - Verifica a igualdade estrita dos componentes (`dt.year == y && dt.month == m && dt.day == d`) para interceptar o comportamento padrão do Dart de transbordamento automático de datas (onde `DateTime(2026, 2, 31)` viraria `DateTime(2026, 3, 3)`).
   - Rejeita formatos incompletos ou dias impossíveis com mensagem de erro amigável, impedindo o salvamento da transação.
3. **Verificação de Janela Temporal e Confirmação (`confirmDateWarningDialog`):**
   - Compara a data da transação com o dia de hoje (`todayISO()`):
     - **Anterior a mais de 30 dias:** gera aviso `"A data informada (DD/MM/AAAA) é anterior a mais de 30 dias da data atual."`
     - **Posterior a 12 meses:** gera aviso `"A data informada (DD/MM/AAAA) é posterior a 12 meses da data atual."`
   - O aviso é exibido visualmente em tempo real logo abaixo do campo de data nos modais de formulário.
   - Ao clicar em Salvar, o aplicativo abre um diálogo modal (`confirmDateWarningDialog`) com as opções **"Corrigir Data"** e **"Salvar Mesmo Assim"**, prevenindo gravações acidentais.
   - Na edição de um lançamento existente (`_TransactionEditDialogState`), o aviso visual e o diálogo de confirmação de data só são exibidos caso a data tenha sido efetivamente alterada pelo usuário (`res.isoDate != widget.tx.date`), evitando alertas redundantes ao editar lançamentos antigos/conciliados cuja data não foi modificada.
   - O mesmo fluxo de validação e confirmação protege a barra de inserção rápida do extrato (`_submitQuickEntry`) e as datas de término de recorrências (`_endDateCtrl`).

### 2. Exclusão de Previsões e Limpeza de Números de Parcela no Autocompletar (`MoneyStore`)

1. **Remoção Automática de Números de Parcela (`stripInstallmentFromPayee`):**
   - Lançamentos históricos ou parcelados com marcações de parcela (ex.: `"Amazon 1/3"`, `"Logitech Mouse Bluetooth 8/12"`, `"Mercado Livre 7/24"`, `"Amazon (2/3)"`, `"Loja - Parcela 01/10"`) têm o sufixo/token de parcela removido automaticamente antes da indexação no cache (`_cachedPayeeSuggestions`), consolidando todas as parcelas sob o nome limpo (`"Amazon"`, `"Logitech Mouse Bluetooth"`, `"Mercado Livre"`).
2. **Filtro de Cache e Indexação de Previsões:**
   - Em `MoneyStore.rebuildIndexes()`, transações onde `isPredictionPayee(tx.payee)` retorna `true` são estritamente excluídas do cache de sugestões (`_cachedPayeeSuggestions`).
3. **Filtro em Tempo Real:**
   - No método `payeeSuggestions(query, isExpense: ...)`:
     - Se a consulta do usuário for ela própria um termo de previsão (`isPredictionPayee(cleanQ)`), retorna lista vazia.
     - As sugestões filtradas descartam qualquer item cujo nome atenda a `isPredictionPayee(v.name)`.
   - No método `lastCategoryAndType(payee, isExpense: ...)`:
     - Ignora consultas ou históricos correspondentes a previsões, assegurando que metas orçamentárias não preencham indevidamente tipos e categorias de despesas reais.

---

## Consequências

- **Confiabilidade Aumentada:** Eliminação de erros de digitação em datas de transações e bloqueio de datas inexistentes no calendário.
- **Segurança Operacional:** Alerta e confirmação explícita para lançamentos muito antigos ou muito no futuro, mantendo a flexibilidade para usuários que queiram registrar retrospectivas ou planejamentos de longo prazo.
- **Experiência Limpa:** O campo Favorecido sugere exclusivamente beneficiários e históricos de compras e recebimentos reais, sem interferência das previsões automáticas do sistema.
