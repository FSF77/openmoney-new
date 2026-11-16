# ADR 024: Aperfeiçoamento do Modal de Detalhe de Lançamentos (Drill-Down), Filtro de Conciliação e Limpeza Visual

**Status:** ✅ Aprovado, Implementado e Validado (Flutter & Swift macOS/iOS)  
**Data:** 15/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Experiência do Usuário / Design System / Produtividade  

---

## 1. Contexto e Motivação

O modal de detalhamento e auditoria de lançamentos (`CategoryDrillDownDialog` no Flutter / `CategoryTransactionsDetailSheet` no Swift) é o componente central acionado ao clicar em uma categoria (no catálogo de Categorias ou em gráficos de Relatórios), em uma Tag (na gestão de Tags) ou nos blocos do Fluxo de Caixa.

Identificaram-se três melhorias visuais e operacionais essenciais:
1. **Filtro Direto de Conciliação:** Usuários necessitavam filtrar instantaneamente lançamentos conciliados ou não conciliados diretamente dentro do modal, posicionado ao lado direito da barra de pesquisa de texto, permitindo auditar pendências sem precisar fechar o diálogo ou alterar os filtros da tela de fundo.
2. **Botão de Exportação Compacto:** O botão "Exportar CSV" continha rótulo textual extenso que ocupava espaço desnecessário no cabeçalho; a conversão para botão compacto contendo apenas o ícone `Icons.download` (ou `square.and.arrow.up` no Swift) com tooltip informativo garante leveza visual e economia de espaço.
3. **Título Limpo e Conciso:** O prefixo redundante `"Auditoria de Lançamentos:"` poluía o cabeçalho e causava truncamento em telas menores; a exibição direta do nome do alvo (ex.: `Alimentação`, `#projeto`, `Sem tag`, `Lançamentos`) torna o diálogo mais elegante e direto.

---

## 2. Decisões Arquiteturais e de Interface

### 2.1. Filtro de Status de Conciliação à Direita da Busca
- Implementado seletor dropdown (`DropdownButton<CashFlowStatusFilter>` no Flutter / `Picker` no Swift) posicionado à direita do campo de texto `TextField` de busca (entre a busca e a ordenação):
  - **Todos os status:** Exibe o conjunto completo de lançamentos.
  - **Conciliados:** Filtra rigorosamente transações onde `t.rec == true`.
  - **Não Conciliados:** Filtra rigorosamente transações onde `t.rec == false`.
- Funciona de forma totalmente reativa recalculando somatórios, contagens e exportação CSV em tempo real.

### 2.2. Botão de Exportação CSV com Apenas Ícone e Tooltip
- Substituição do botão com texto por botão tonal compacto:
  - **Ícone:** `Icons.download` (Flutter) / `square.and.arrow.up` (Swift).
  - **Tooltip:** `"Exportar CSV"` / `"Exportar CSV (Cmd+E)"`.
  - Dimensão reduzida harmonizada com os demais controles de cabeçalho.

### 2.3. Remoção do Prefixo "Auditoria de Lançamentos:"
- Título simplificado para o identificador direto:
  - Para categorias: `widget.categoryPath` (ex.: `Alimentação > Restaurante`).
  - Para tags: `#tag` ou `Sem tag`.
  - Para tipos: `Receita` ou `Despesa`.
  - Fallback geral: `Lançamentos`.

---

## 3. Validação e Testes Multi-Stack

1. **OpenMoney Flutter:**
   - 86 testes unitários e de integração passando com sucesso (`All tests passed!`).
   - 0 erros em `flutter analyze`.
2. **OpenMoney Swift (macOS & iOS):**
   - Compilação limpa em 0.38s (`Build complete!`).
   - Paridade estrita de comportamento e layout no macOS e iOS.
