# ADR 012: Design Responsivo Mobile Web e Otimização para Telas Estreitas

- **Data:** 06 de Novembro de 2026
- **Status:** Aceito e Implementado
- **Plataformas Afetadas:** OpenMoney Flutter (Web, Mobile, Desktop)

---

## 1. Contexto e Motivação

Com o lançamento da versão Web e PWA do **OpenMoney** ([ADR 011](011-web-multiuser-cloudflare-architecture.md)), os usuários passaram a acessar o aplicativo financeiro tanto por computadores (telas largas, `width >= 1024px`) quanto por navegadores mobile em smartphones (telas estreitas, `width < 680px` / `~375px`).

Na auditoria de usabilidade mobile, foram identificados gargalos decorrentes da herança do layout estritamente desktop:
1. **Tela de Lançamentos (`AccountLedgerView`):** O cabeçalho executivo da conta somado à barra de inserção rápida (7 campos em linha) ocupava mais de 100% da altura da tela de um celular, deixando 0px para a listagem rolar e gerando sobreposição/bloqueio dos botões de ação.
2. **Fluxo de Caixa (`CashFlowView`):** Os 5 filtros contábeis e os 3 cards verticais de KPIs ocupavam ~520px de altura vertical fixa. A coluna congelada de categorias (`230px`) esmagava a tabela em celulares, e a barra de seleção de períodos quebrava o botão "Mensal" em duas linhas.
3. **Catálogo de Categorias (`CategoriesView`):** Linhas horizontais rígidas com nome, badge de lançamentos, tags de status (`BLOQUEADA`, `OCULTA`) e 4 botões de texto colidiam em telas menores que 680px.
4. **Modais e Diálogos de Ação:**
   - **Edição de Lançamento:** O `AlertDialog` padrão quebrava as 4 ações (`Copiar`, `Excluir`, `Cancelar`, `Salvar Alterações`) em 4 linhas verticais separadas.
   - **Edição de Conta:** Botões `Excluir`, `Cancelar` e `Salvar` quebravam em 3 linhas verticais.
   - **Detalhamento de Fluxo / Categorias (`CategoryDrillDownModal`):** Diálogo com tamanho rígido de `780px` x `560px` estourava a tela em dispositivos móveis.
   - **Planejamento Financeiro (`BudgetView`):** Nome da categoria, badge `ACIMA DO LIMITE` e valores colidiam horizontalmente.
   - **Logs de Auditoria (`AuditLogsModal`):** `minWidth: 540` e botões longos no rodapé desposicionavam os controles.

---

## 2. Princípio Fundamental de Design

> **Regra de Ouro:** A experiência no Desktop e em tablets (`width >= 720px`) deve permanecer **100% inalterada**. Toda compactação ou reorganização deve ser estritamente adaptativa (`isMobile = width < 720px`), ativando layouts fluidos apenas onde há restrição de espaço físico.

---

## 3. Decisões Arquiteturais e Implementações

### 3.1. Tela de Lançamentos (`AccountLedgerView`)
- **Cabeçalho Compacto:** Em telas móveis, o título da conta e os botões rápidos (`Editar`, `Opções`, `+ Lançar`) ficam na linha superior, enquanto os saldos **Conciliado (Real)** e **Previsto** são organizados em duas colunas proporcionais lado a lado (`Row` com `Expanded`), sem esmagar o nome da conta.
- **Inserção Rápida Recolhível:** No celular, a barra de inserção rápida inicia recolhida por padrão, liberando 100% da área útil vertical para rolar e auditar os lançamentos. O formulário abre sob demanda ao tocar no botão destacado **`+ Lançar`** e se recolhe automaticamente após salvar.
- **Gaveta de Opções e Exportação:** Ajuste de previsões, busca no mês, exportação CSV e extrato PDF são consolidados em um botão toggle de ferramentas no topo.
- **Itens do Extrato:** Cada lançamento adota estrutura de 2 níveis responsiva no mobile: favored e valor na linha superior; categoria, notas e badges (`PREVISÃO`, `FATURA`, etc.) dispostos na linha inferior com `Wrap`, mantendo botões de conciliar, copiar e excluir sempre acessíveis.

### 3.2. Fluxo de Caixa (`CashFlowView`)
- **Filtros e KPIs Recolhíveis:** Os 5 campos de filtro e os 3 cards de KPI ficam recolhidos sob o botão **`Filtros`**, exibindo um resumo minimalista de 1 linha (`Rec`, `Desp`, `Líq`) no celular.
- **Largura Proporcional da Coluna Fixa:** Em telas estreitas, a coluna congelada de categorias é reduzida de `230px` para `142px` (com `colWidth = 104px`), viabilizando a navegação confortável pelas colunas de período.
- **Barra de Períodos (`SegmentedButton`):** Ocultação do ícone de seleção (`showSelectedIcon: !isMobile`), garantia de `maxLines: 1` / `softWrap: false` e rolagem horizontal suave, eliminando qualquer quebra de linha de texto em botões como "Mensal".

### 3.3. Catálogo de Categorias (`CategoriesView`)
- Substituição do `Row` interno rígido por `Wrap` fluido, prevenindo colisões entre o nome da categoria, badge numérica de contagem e tags de auditoria.
- Em telas estreitas, os botões com texto por extenso (`Lançamentos`, `Subcategoria`) convertem-se automaticamente em `IconButton`s com tooltips informativos.

### 3.4. Otimização de Modais e Diálogos de Sistema
- **Modal de Transação (`TransactionModal`):**
  - Implementado `LayoutBuilder`: em telas estreitas, `Copiar` e `Excluir` ficam agrupados na linha superior, e `Cancelar` e `Salvar Alterações` na linha inferior alinhados à direita. Em telas largas, mantém-se a linha única espaçada.
- **Modal de Conta (`AccountModal`):**
  - Fixação das ações em 1 linha contínua via `Row(children: [Excluir, Spacer(), Cancelar, Salvar])`, impedindo quebra vertical.
- **Detalhamento de Categorias e Fluxo (`CategoryDrillDownModal`):**
  - Diálogo redimensionado dinamicamente com base nas dimensões da janela (`clamp(320.0, 780.0)` de largura e `clamp(440.0, 720.0)` de altura).
  - Cabeçalho mobile com título truncado, botão fechar, filtros de competência em rolagem horizontal e campo de busca reposicionado.
- **Planejamento Financeiro / Limite de Gastos (`BudgetView`):**
  - Uso de `Wrap` fluido com alinhamento justificado no teto de categorias, subcategorias e no consolidado mensal, garantindo que valores e a badge `ACIMA DO LIMITE` nunca se sobreponham.
- **Logs de Auditoria (`AuditLogsModal`):**
  - Remoção de `minWidth: 540` forçado; campo de busca empilhado com os chips de filtro em rolagem horizontal; botões de arquivo do rodapé compactados em ícones com tooltip.

### 3.5. Barra Superior Global (`AppShell`)
- Na versão mobile, a `AppBar` ganhou o botão direto de status e acesso ao modal **Cloud & Sincronização** e truncamento automático por elipse para evitar quebras em títulos longos.

---

## 4. Consequências e Resultados

1. **Paridade Móvel Sem Regressão no Desktop:** Usuários no celular agora desfrutam de um aplicativo ágil, sem travamentos de rolagem ou telas estouradas, enquanto usuários de desktop mantêm 100% da densidade de informação prévia.
2. **Compatibilidade Multi-Resolução:** O sistema adapta-se suavemente de telas ultracompactas (360px) a monitores Ultrawide sem duplicar componentes nem divergir do modelo de dados unificado (`Schema v: 7`).
