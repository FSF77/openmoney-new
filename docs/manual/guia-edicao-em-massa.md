# Guia do Usuário: Filtros Avançados e Edição em Massa (Lote)

Este manual apresenta o guia operacional para uso dos **Filtros Combináveis** e da **Edição e Exclusão em Massa (Lote)** na tela de **Lançamentos Gerais** do **OpenMoney** (Desktop macOS/Windows, Web e Mobile).

---

## 1. 🎛️ Filtros Avançados Combináveis

Na tela **Lançamentos** (visão consolidada de todas as contas), você pode combinar livremente os filtros de **Período (Dia / Mês / Ano)**, **Contas**, **Cartão (Data da Compra vs. Fatura)** e **Busca Textual** com os seguintes filtros:

- **Categoria:** Todas, Sem categoria ou categoria/subcategoria específica.
- **Tag:** Todas, Sem tag ou `#tag` específica.
- **Tipo:** Todos, Despesas, Receitas ou Transferências.
- **Conciliação:** Todos, Conciliados ou Pendentes.

Quando algum filtro avançado estiver ativo, utilize o botão **Limpar filtros** para restaurar a visualização padrão.

---

## 2. ☑️ Seleção Múltipla e Barra Contextual

1. Clique no botão **Selecionar** na barra de filtros para exibir os checkboxes nas linhas dos lançamentos.
   > **Nota de segurança:** Lançamentos automáticos de pagamento de fatura (`FATURA AUTO`) ficam bloqueados para seleção para preservar a integridade contábil das faturas.
2. Marque os lançamentos desejados (ou utilize **Selecionar todos** / **Limpar** na barra contextual).
3. A barra contextual no topo da lista exibe a **quantidade de itens selecionados** e a **soma líquida** na moeda de consolidação, além das ações rápidas:
   - **Conciliar:** marca todos os selecionados como conciliados (`rec = true`).
   - **Pendente:** marca todos os selecionados como pendentes (`rec = false`).
   - **Editar em Lote:** abre o modal/sheet de edição em massa.
   - **Excluir:** remove todos os selecionados em lote após confirmação.

---

## 3. ✏️ Edição em Lote

No modal **Edição em Lote**, cada campo possui uma caixa de seleção individual para que você altere **apenas o que desejar**, mantendo os demais dados originais de cada lançamento:

- **Nome / Favorecido:** redefine a descrição dos lançamentos selecionados.
- **Categoria:** altera a categoria *(não altera transferências entre contas)*. O menu suspenso exibe a árvore completa com categorias principais em destaque e subcategorias indentadas com o indicador visual `↳` para localização imediata.
- **Tags:** permite escolher entre três modos de aplicação:
  - **Adicionar:** acrescenta as tags informadas às tags já existentes em cada lançamento.
  - **Substituir:** substitui todas as tags dos lançamentos selecionados pelas novas tags informadas (deixar vazio limpa as tags).
  - **Remover:** remove apenas as tags informadas dos lançamentos selecionados.
- **Notas (Memo):** atualiza ou limpa as observações dos lançamentos.
- **Valor:** atualiza o valor com três opções de sinal *(não altera transferências entre contas)*:
  - **Manter sinal original:** preserva se cada lançamento era receita ou despesa.
  - **Forçar Despesa (-):** aplica o valor como negativo.
  - **Forçar Receita (+):** aplica o valor como positivo.
- **Data:** altera a data dos lançamentos e recalcula a competência da fatura (`ik`) caso a conta seja cartão de crédito.
- **Conta:** move os lançamentos para outra conta *(não altera transferências entre contas)*.
- **Status de Conciliação:** define em lote como **Conciliado** ou **Pendente**.

---

## 4. 🗑️ Exclusão em Lote com Backup Preventivo

Ao clicar em **Excluir** na barra contextual:
1. O sistema solicita confirmação explícita informando a quantidade de lançamentos selecionados.
2. Caso algum item seja uma transferência entre contas, sua contrapartida também é removida para não deixar lançamentos órfãos.
3. Antes da remoção, o OpenMoney cria automaticamente um **Backup de Segurança** preventivo e registra a operação nos **Logs de Alterações**.

---

## 5. 📱 Visualização em Telas Pequenas e Mobile (Ocultar / Expandir Filtros)

Em dispositivos móveis ou janelas compactas (largura `< 720px`), a barra superior da tela de **Lançamentos** adota o mesmo comportamento ergonômico da tela de extrato:

1. **Botão de Ajustes (`Icons.tune` / `Icons.expand_less`):** Localizado no canto superior direito ao lado do botão `+` (Novo Lançamento).
2. **Modo Recolhido (Padrão):**
   - Mantém visíveis apenas o título, os **KPIs de Resumo Financeiro** (Receitas, Despesas e Resultado Líquido) e a **Navegação Temporal** (Dia / Mês / Ano com setas e atalho "Hoje").
   - Todos os filtros secundários, busca textual, exportadores e ferramentas de edição em lote ficam ocultos para liberar espaço total para visualização dos lançamentos.
3. **Modo Expandido:**
   - Ao tocar no botão de ajustes, abre-se a gaveta com: filtro de Cartão (Data vs. Fatura), Multicontas, Previsões, Exportação CSV/PDF, busca rápida, ordenação/modo de exibição (Lista/Tabela) e os filtros avançados de Categoria, Tag, Tipo, Conciliação e o botão **Selecionar**.
4. **Indicador de Filtros Ativos:**
   - Se houver filtros ativos com o cabeçalho recolhido, o ícone de ajustes fica destacado na cor de destaque (`accent`) e um badge compacto `Filtros ativos aplicados [Limpar]` é exibido no cabeçalho com atalho direto para redefinir a visualização com um único toque.
