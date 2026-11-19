# Guia do Usuário: Gestão e Acompanhamento de Previsões Orçamentárias

Este documento descreve o funcionamento, as regras contábeis e o fluxo operacional da tela dedicada de **Previsões** no OpenMoney (disponível para macOS, Windows, Web e Mobile).

---

## 1. O que são as Previsões Orçamentárias?

No OpenMoney, uma **Previsão** é uma transação planejada que funciona como uma **reserva prévia de teto de gastos** para uma categoria dentro de uma competência mensal (ex.: *Previsão Mercado*, *Previsão Combustível*, *Previsão Farmácia*).

Diferente do *Limite de Gastos* (que atua como um teto teórico global em relatórios), a **Previsão afeta ativamente o saldo projetado e o fluxo de caixa**, garantindo que o dinheiro reservado para essas despesas essenciais conste como comprometido no orçamento.

---

## 2. A Tela de Previsões

Acessível na seção **PLANEJAMENTO** do menu lateral (acima de *Limite de Gastos*) com o ícone de varinha mágica / ajuste (`wand.and.stars` / `auto_fix_high`).

### 2.1 Barra Superior e Controles
- **Seletor de Competência (`< Mês/Ano >`)**: Permite navegar pelos meses do ano para analisar tanto o planejamento corrente quanto meses futuros ou passados.
- **Modo de Apuração**: Alterna entre:
  - **Por Mês**: Abate despesas reais cuja data do lançamento pertence ao mês civil.
  - **Por Fatura do Cartão**: Abate despesas bancárias com data no mês e despesas de cartão cuja fatura vence no mês (regime de desembolso de caixa).
- **Botão "Ajustar"**: Executa a rotina automática que calcula todos os gastos reais das categorias e abate dos tetos previstos, exibindo o modal de resumo com status semânticos.
- **Botão "+ Nova Previsão"**: Abre o formulário padronizado de criação.

### 2.2 Cards de Indicadores (KPIs)
No topo da tela são exibidos 4 cards consolidados da competência:
1. **TETO PREVISTO**: Soma dos valores base originais planejados para o mês.
2. **TOTAL ABATIDO**: Soma dos valores efetivamente consumidos pelas compras reais das categorias previstas.
3. **SALDO REMANESCENTE**: O que resta de orçamento livre nas previsões ($Base - Abatido$). Exibido em verde quando positivo e em vermelho caso esgotado.
4. **PREVISÕES**: Quantidade total de lançamentos de previsão cadastrados no mês.

### 2.3 Visão por Categoria (Barras de Progresso e Drill-Down)
Cada categoria que possui previsões ganha um card estruturado:
- **Cabeçalho da Categoria**: Ícone, nome da categoria, valor base original, total gasto real e saldo remanescente.
- **Barra de Progresso Dinâmica**:
  - 🟢 **Verde**: Consumo saudável (< 70% do teto).
  - 🟡 **Amarelo**: Atenção (entre 70% e 99% do teto).
  - 🔴 **Vermelho**: Teto atingido / esgotado (≥ 100%).
- **Lista de Previsões Cadastradas**:
  - Exibe a conta associada, a descrição e o valor atual disponível.
  - Previsões com saldo zerado ganham o badge **ESGOTADA**.
  - Ações rápidas:
    - ✏️ **Editar**: Abre o modal de edição do lançamento.
    - 🔄 **Restaurar Teto**: Reseta o valor atual de volta para o valor base original gravado no memo.
- **Acordeão "Ver lançamentos que abateram este teto"**:
  - Exibe a lista completa de todas as despesas reais que causaram o abatimento da previsão.
  - Colunas: **Data (`dd/mm/aaaa`)**, **Favorecido / Estabelecimento**, **Notas / Observações (`• Nota`)** e **Valor**.

---

## 3. Regras de Negócio e Comportamento Contábil

### 3.1 Convenção de Nomenclatura e Identificação
- Uma transação é reconhecida como previsão quando a descrição inicia com o prefixo **`Previsão`** (validado por `isPredictionPayee`).
- Na criação manual, o sistema preenche ou preserva automaticamente esse prefixo.

### 3.2 Preservação do Teto Base Original
- Ao criar ou salvar uma previsão, a base orçamentária é gravada de forma transparente no campo de notas (`memo`):
  ```
  [Previsão base: R$ 1.500,00] Notas adicionais opcionais...
  ```
- Isso permite que o usuário clique em **"Ajustar"** quantas vezes quiser ao longo do mês à medida que novas compras forem inseridas, sem que ocorra dupla dedução: o recálculo sempre parte do teto original.

### 3.3 Regra de Previsão Esgotada (Valor Zerado)
- **Não exclusão**: Quando as despesas reais atingem ou superam o teto da previsão, a transação **NÃO é excluída** do banco de dados.
- O seu valor (`amt`) é atualizado para **R$ 0,00**, mantendo a base original memorizada.
- **Motivo**: Preservar o histórico completo do planejamento, permitindo ao usuário auditar o que havia sido planejado e restaurar o teto a qualquer momento.

### 3.4 Modos de Abatimento (`predMode`)
- **`month` (Padrão)**: Considera os gastos com data dentro do mês alvo.
- **`invoice` (Por Fatura)**: Considera os gastos com cartão cuja fatura vence no mês alvo + despesas em contas correntes/dinheiro do mês alvo. O escopo estendido projeta a apuração para o mês corrente e os 2 meses seguintes.

---

## 4. Modal de Nova Previsão

A tela de inclusão conta com campos proporcionais e alinhados:
- **Conta**: Escolha da conta de débito ou cartão.
- **Data**: Data do lançamento (formato `dd/mm/aaaa`), definindo a competência da previsão.
- **Categoria**: Dropdown hierárquico com categorias e subcategorias devidamente indentadas (`   ↳ Subcategoria`).
- **Descrição**: Campo limpo com prompt explicativo `Previsão (ex: Mercado, Combustível, Farmácia...)`.
- **Valor do Teto**: Valor planejado em centavos/moeda da base.
- **Observações**: Anotações livres.
- **Toggle "Ajustar com gastos do mês imediatamente"**: Ao salvar, já executa a rotina de abatimento caso já existam gastos reais cadastrados na categoria naquele mês.
