# ADR 032: Sugestões Inteligentes de Favorecido com Filtro de Tipo, Janela de Histórico e Escopo de Campos Configurável

## Status
Aprovado / Implementado

## Contexto
O auto-preenchimento ao digitar o campo "Favorecido / Descrição" (`payee`) busca os lançamentos anteriores do usuário e preenche automaticamente a categoria, tipo (despesa/receita) e conta associada.

Identificaram-se três necessidades de refinamento na usabilidade desse mecanismo:
1. **Filtro Estrito por Tipo de Operação Selecionada:** Ao estar no modo "Despesa", as sugestões e o preenchimento automático devem sugerir apenas lançamentos históricos de despesas. De modo similar, ao estar em "Receita", apenas receitas anteriores devem ser sugeridas.
2. **Escopo de Preenchimento Configurável nos Ajustes:** Por padrão, a maioria dos usuários deseja que a sugestão autocomplete apenas o **Nome** e a **Categoria**, sem alterar a conta que já estava selecionada na tela. Deve haver um parâmetro nos Ajustes para alternar entre "Apenas Nome e Categoria" (Padrão) e "Nome, Categoria e Conta".
3. **Janela de Tempo / Período do Histórico Configurável:** Deve ser possível configurar nos Ajustes o intervalo de tempo retroativo considerado para aprender sugestões de favorecidos (30 dias, 60 dias, 90 dias [Padrão], 6 meses [180d], 1 ano [365d] ou todo o histórico).

## Decisões Tomadas

### 1. Separação de Cache de Favorecidos por Tipo (Despesa vs. Receita)
- Em `MoneyStore.rebuildIndexes()`, o mapa `payeeMap` passa a registrar chaves compostas pelo tipo e nome em minúsculas:
  - `exp:<favorecido>` para despesas.
  - `inc:<favorecido>` para receitas.
- Isso assegura que favorecidos com o mesmo nome que ocorrem em despesas e receitas não se sobrescrevam no cache e possam ser consultados de forma isolada.

### 2. Filtro por Tipo (`isExpense`) nas Buscas de Histórico
- Os métodos `MoneyStore.payeeSuggestions(query, {int limit, bool? isExpense})` e `MoneyStore.lastCategoryAndType(payee, {bool? isExpense})` recebem o parâmetro opcional `isExpense`.
- Quando fornecido:
  - Em telas de criação ou edição em modo Despesa (`_isExpense == true`), apenas transações de despesa são sugeridas.
  - Em modo Receita (`_isExpense == false`), apenas transações de receita são sugeridas.
  - Ao alternar entre os botões de Despesa e Receita na interface com texto já digitado, as sugestões exibidas são imediatamente recalculadas para o novo tipo selecionado.

### 3. Janela de Lookback Retroativa (`payeeSuggestionLookbackDays`)
- Adicionada a preferência `payeeSuggestionLookbackDays` (padrão `90` dias).
- Opções disponíveis: 30, 60, 90 (padrão), 180 (6 meses), 365 (1 ano) e 0 (todo o histórico).
- O `payeeSuggestionCutoffDate` calcula a data de corte em formato ISO a partir de `DateTime.now().subtract(Duration(days: days))`. Transações cuja data mais recente (`lastDate`) seja anterior ao corte são descartadas das sugestões.

### 4. Escopo Configurável de Inclusão da Conta (`payeeSuggestionIncludeAccount`)
- Adicionada a preferência `payeeSuggestionIncludeAccount` (booleano, padrão `false` - Apenas Nome e Categoria).
- No modal de criação de lançamentos (`_TransactionCreateDialog`):
  - Quando `false` (padrão): ao clicar numa sugestão ou fazer match exato de histórico, preenche o Nome e Categoria, mantendo intacta a Conta que o usuário selecionou. Os chips de sugestão não exibem o nome da conta.
  - Quando `true`: ao selecionar a sugestão, altera adicionalmente a conta para a conta aprendida do histórico. Os chips de sugestão exibem o nome da conta (`Nome • Categoria • Conta`).

### 5. Controles na Tela de Ajustes (`SettingsView`)
- Na seção **Extrato & Visualização de Lançamentos**, foram adicionados dois controles dedicados:
  - **Preenchimento Automático por Histórico:** Dropdown ("Apenas Nome e Categoria (Padrão)" / "Nome, Categoria e Conta").
  - **Período do Histórico para Sugestões:** Dropdown com as 6 opções de tempo.
- Ambos os parâmetros são sincronizados com o `config.json` e persistidos via `MoneyStore`.

## Consequências
- A experiência de digitação e auto-preenchimento tornou-se previsível e não troca inesperadamente a conta do usuário, a menos que ele explicitamente ative essa preferência nos Ajustes.
- A restrição por tipo impede cruzamentos indevidos (ex.: despesa sugerindo categoria de receita).
- 100% dos testes unitários e de integração (100 testes) validados com sucesso.
