# ADR 030: Indentação de Categorias em Lote, Ações Rápidas no Extrato, Auto-Preenchimento de Transferência e Seletor de Logos

## Status
Aprovado / Implementado

## Contexto
Durante o refinamento contínuo da experiência de uso do **OpenMoney Flutter** (Desktop, Web e Mobile), foram identificadas quatro melhorias de usabilidade e interface:

1. **Hierarquia de Categorias na Edição em Lote:** Na tela de edição em lote de lançamentos (`BatchEditTransactionsModal`), a listagem de categorias apresentava nomes planos sem a hierarquia visual (`↳`) usada nas telas de criação e edição individual.
2. **Acesso Rápido no Extrato/Faturas com Barra Oculta:** Quando a barra de inserção rápida em linha (`showInlineTransactionEntry`) é ocultada pelo usuário nas configurações ou no cabeçalho, a tela exibia apenas um botão genérico `+` antes de "Editar Conta". Desejava-se 3 botões específicos de acesso direto (Despesa, Receita e Transferência) posicionados à direita do ícone de edição de conta.
3. **Auto-Preenchimento e Isolamento de Histórico em Transferências:** Ao criar um novo lançamento e selecionar o tipo "Transferência", o campo de descrição deve ser automaticamente preenchido com `"Transferência"`, sem consultar ou autocompletar sugestões de histórico (categorias/contas aprendidas) que poluiriam o fluxo de transferências.
4. **Persistência da Busca no Seletor de Logos de Bancos:** Ao editar uma conta e abrir o modal de escolha de logo (`_openLogoPicker`), o filtro digitado no campo de busca era resetado de forma intermitente para vazio (exibindo todos os logos novamente) devido à reinicialização de escopo em `StatefulBuilder`.

## Decisões Tomadas

### 1. Categorias e Subcategorias Indentadas na Edição em Lote
- Em `BatchEditTransactionsModal`, a lista de opções do `DropdownButtonFormField<String>` agora utiliza as funções `allCategoryOptions('Despesa')` e `allCategoryOptions('Receita')` do `MoneyStore`.
- As opções preservam o formato padrão: categorias principais (`Alimentação`) e subcategorias com recuo visual (`   ↳ Restaurante`), mantendo como valor subjacente o caminho canônico `Top:Sub`.

### 2. Três Botões de Ação Rápida no Extrato e Fatura
- Em `AccountLedgerView` (tanto no cabeçalho Desktop quanto no Mobile):
  - Quando `widget.store.showInlineTransactionEntry == false` e a conta está ativa, o botão único de adicionar antes de "Editar Conta" é substituído por 3 botões circulares compactos à direita do ícone de "Editar Conta":
    - **Nova Despesa:** Ícone `Icons.arrow_downward_rounded`, fundo vermelho suave, abrindo o modal com `initialTxType: 'expense'`.
    - **Nova Receita:** Ícone `Icons.arrow_upward_rounded`, fundo verde suave, abrindo o modal com `initialTxType: 'income'`.
    - **Nova Transferência:** Ícone `Icons.swap_horiz_rounded`, fundo na cor de destaque suave (`colors.accent`), abrindo o modal com `initialTxType: 'transfer'`.

### 3. Auto-Preenchimento e Supressão de Histórico para Transferências
- Adicionado o parâmetro `initialTxType` ao método `showTransactionCreateModal` e ao widget `_TransactionCreateDialog`.
- Ao entrar ou alternar para o tipo `'transfer'`:
  - Se a descrição estiver vazia ou com o valor padrão anterior, define automaticamente o campo como `"Transferência"`.
  - O método `_onPayeeChanged` detecta o tipo `'transfer'` e retorna precocemente, zerando a lista `_suggestions` e impedindo buscas ou auto-preenchimentos de categorias/contas a partir do histórico de lançamentos.
  - Ao alternar de `'transfer'` de volta para `'expense'` ou `'income'`, limpa a descrição caso ainda seja `"Transferência"`.

### 4. Componente Dedicado `_BankLogoPickerDialog` com Estado Seguro
- O seletor de logos foi extraído para o widget `_BankLogoPickerDialog`, que gerencia seu próprio ciclo de vida, `TextEditingController` e foco.
- A busca mantém o texto pesquisado de forma estável, inclui botão de limpar busca (`Icons.clear`) quando há texto, e exibe mensagem amigável ("Nenhum banco encontrado") quando não houver resultados correspondentes.
- Corrigido o `RenderFlex` overflow no dropdown de tipo de conta adicionando `isExpanded: true`.

## Consequências
- A experiência de inserção e edição em lote ficou totalmente homogênea com as telas principais de lançamentos.
- Extrato e faturas oferecem agora atalhos imediatos em um clique para os 3 tipos de operações financeiras.
- O seletor de logos opera com busca estável e sem conflitos de renderização ou reconstrução de árvores de widgets.
- 100% dos testes unitários e de widget (99 testes) validados com sucesso.
