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

### 1. Validação Estrita de Datas (`date_validator.dart` e `DateInputFormatter`)

1. **Clamping Ativo durante a Digitação (`DateInputFormatter`):**
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
   - O mesmo fluxo de validação e confirmação protege a barra de inserção rápida do extrato (`_submitQuickEntry`) e as datas de término de recorrências (`_endDateCtrl`).

### 2. Exclusão de Previsões no Autocompletar (`MoneyStore`)

1. **Filtro de Cache e Indexação:**
   - Em `MoneyStore.rebuildIndexes()`, transações onde `isPredictionPayee(tx.payee)` retorna `true` são estritamente excluídas do cache de sugestões (`_cachedPayeeSuggestions`).
2. **Filtro em Tempo Real:**
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
