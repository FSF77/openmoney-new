# ADR 017: Modernização de UI/UX Desktop & Web, Central de Ajustes, Dashboard Customizável, Mini Rail, Datagrid e Paridade Multi-Stack (Flutter & Swift)

**Status:** ✅ Aprovado, Implementado e Validado (Flutter & Swift macOS/iOS)  
**Data:** 10/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Evolução Arquitetural / Experiência do Usuário (Multiplataforma)  

---

## 1. Contexto e Motivação

O **OpenMoney** no Flutter Desktop (macOS, Windows) e Web consolidou paridade estrita com a fonte da verdade em Swift no que tange a regras de negócio contábeis, esquema unificado `v: 7`, importações de arquivos bancários e conciliações.

Entretanto, para usuários de telas médias e grandes (monitores 1080p, 1440p, 4K e ultrawide no Desktop e Web), identificaram-se oportunidades críticas de evolução:
1. **Falta de uma Central Unificada de Preferências:** Parâmetros de comportamento e interface estavam dispersos em diferentes caixas de diálogo ou exigiam navegação por múltiplos submodais.
2. **Ausência de um Cockpit / Dashboard Geral Executivo:** O aplicativo iniciava compulsoriamente no razão de uma conta específica, sem oferecer uma visão consolidada de patrimônio, contas bancárias ativas com saldos, radar de vencimentos imediatos, faturas abertas de cartões e distribuição real de gastos por categoria.
3. **Barra Lateral Rígida (280px):** Ocupava espaço útil de tela mesmo quando o usuário desejava apenas consultar lançamentos ou conciliar contas em massa.
4. **Ausência de Command Palette (`Cmd+K` / `Ctrl+K`):** Ferramenta essencial de produtividade em softwares financeiros modernos para busca instantânea e navegação sem mouse.
5. **Visão Exclusiva em Lista Diária:** Dificultava a conciliação e auditoria para usuários com grande volume mensal de transações, que demandavam uma visualização em formato de **Tabela / Datagrid Contínua** com ações rápidas de mouse (*hover actions*) e ordenação por data comutável (crescente ou decrescente).

### O Pedido do Usuário e Refinamentos Consecutivos

> **Fase 1 (Estruturação Geral):**
> *"Mudar layout, personalizar tela, o que pode ser feito para melhoria na interface grafica da versão flutter desktop/web"*
> *"Pensando em ter uma tela de ajustes para incluir isso como parametro, o usuário decide o que é melhor, e talvez tudo que for parametro trazer para essa tela de ajustes, centralizar os ajustes em um local simples e de fácil acesso."*
> *"Proceder com todas as melhorias de uma vez: Personalização Visual, Dashboard Central, Modo Tabela Datagrid e Command Palette."*
>
> **Fase 2 (Refinamentos de Dashboard e Ordenação):**
> - *"Na tela de lançamentos gerais e lançamentos das contas, incluir um ícone para ordenar os lançamentos por crescente ou decrescente de data, hoje a ordem é crescente é deve continuar sendo a padrão."*
> - *"No Dashboard geral, o espaçamento entre o Radar de Vencimentos e Gastos por Categoria está quase colado... padronizar."*
> - *"Tem 3 cartões e no card mostra o total de 4, pode tirar a quantidade."*
> - *"Seria legal ter um card de contas e saldos como no cartão, mostrar as contas favoritas e depois as ativas, permitir posicionar a ordem da conta como é feita no menu lateral, o card pode ser visualizado ou não nos parametros."*
> - *"No card de patrimonio consolidado, tirar a 3ª linha de texto, e quando redimensionar para tela menor onde eles se reposicionam um abaixo do outro, reduzir o tamanho mas manter a largura dos 3 blocos com valores no mesmo tamanho."*
> - *"No menu mini rail, a sequencia dos ícones das contas deve ser igual ao menu normal, as favoritas e depois ativas, no mini rail, nao mostrar as inativas."*
> - *"O botão nova conta que fica no menu lateral em frente as contas ativas, acho que ficaria bom ter em módulo a opção de gestão das contas, local para incluir e editar as contas."*
> - *"O botão de recolher para Mini Rail na tela lateral fica em cima, e no Mini Rail que tem o expandir fica em baixo, padronize para que fique igual na parte superior."*
> - *"Tirar o alternar modo claro/escuro do menu lateral, pois já tem na barra superior."*
> - *"Menu lateral tire a Categoria e Subcategoria e os Ajustes & Personalizacao e coloquem em módulos. Categoria e Subcategoria deve ser o primeiro, Ajustes & Personalizacao na sequencia e depois seguir como está, Backup, Logs, etc."*
>
> **Fase 3 (Layout Multi-Colunas, Contas e Regras de Negócio):**
> - *"Com o ajuste de permitir posicionar os cards no dashboard, todos ficaram do tamanho da tela, ideal é talvez definir o tamanho deles, ou manter como antes, assim posso ter 2 ou 3 lado a lado, e ficou duas barras horizontais no lado esquerdo, feias e sem sentido, pode retirar, o reposicionamento seria vertical e horizontal."*
> - *"No card de contas e saldos não mostra os cartões de crédito, pois já tem um card pra isso e permitir que mostre ou não as contas ativas."*
> - *"Tirar o card de patrimonio do menu lateral, já temos no dashboard geral."*
> - *"No card de gastos por categoria, desconsidere as transferencias, e o total mostrado tem que ser o total de pagamentos de fato."*
> - *"Na visualização datagrid na tela de lançamentos gerais que tem o nome da conta, mantenha ela depois da data e antes do favorecido como ocorre na visualização em lista."*
>
> **Fase 4 (Acabamento Visual e Ergonomia):**
> - *"Ao redimensionar a tela, o dashboard quando tem 2 grids, está aparecendo a faixa listrada amarela/preta (Right Overflowed) nos cards de Gastos por Categoria e Limite de Gastos."*
> - *"O card de limite de gastos / orçamento pode ser eliminado."*
> - *"No card gastos por categoria, mostre apenas o mês como nov/26 em vez de (Novembro de 2026)."*
> - *"Do card de contas e saldos, criar parâmetro para mostrar ou não contas com saldo R$ 0,00."*
> - *"Tirar a etiqueta com nome 'Cockpit Geral' do Dashboard Geral."*
> - *"Nos lançamentos gerais, a visualização por datagrid, inclua o ícone da conta."*
> - *"Ocultar saldo apenas no card de patrimonio consolidado, a opção não pode afetar o card de contas & saldos."*
> - *"Posicione o botão do 'Dashboard geral' acima do '+ Novo Lançamento'."*
> - *"'+ Novo Lançamento' deixe o texto a esquerda, não mais centralizado."*
> - *"No modo mini Rail, também mantenha o ícone de dashboard acima do incluir lançamento, diminuir o botão '+' de incluir lançamento, ficar do tamanho dos demais ícones."*
> - *"O ícone de exibir apenas favoritas e contas com saldo zero não precisa aparecer no card, mantenha só na tela de Ajustes & Personalização."*
>
> **Fase 5 (Refinamentos Finais de Contas, Faturas de Cartão e Mobile):**
> - *"Para todas as versões, tire a opção de poder ordenar a conta no card de Contas, mostre conforme está definido na barra lateral mesmo, dessa forma os ícones de subir e descer que ocupam muito espaço não precisa mais ter."*
> - *"No card Faturas de cartão de crédito, mostrar o valor total e valor 'atual' que é o consolidado da fatura, posso ter o valor total de R$ 5000 mas apenas R$ 4000 até o momento conciliado."*
> - *"No card de contas, mostrar o valor real e o previsto do mês."*
> - *"Com o novo dashboard, faz mais sentido a versão mobile/telas pequenas abrir direto nele, não sendo mais necessária aquela tela anterior de home, na tela pequena o botão 'Novo lançamento' ficou muito grande, deixe apenas um ícone mesmo, e o botão home deixa de existir e vira o de dashboard."*
> - *"No Flutter, transformar o Patrimônio Consolidado em um card como os demais, que pode ser oculto ou não e reposicionado no dashboard, com 3 blocos 'Saldo Real', 'Previsto Mês' e 'Previsto Ano' com seus respectivos valores abaixo."*
> - *"No dashboard, cabeçalho onde diz 'Boa tarde, OpenMoney', se a conta for online, pegue o primeiro nome e personalize no lugar do OpenMoney, contas locais não tem o nome, deixe sem."*
> - *"Alinhar os cards pelo topo na mesma linha no Swift (`GridRow(alignment: .top)`)."*

---

## 2. Decisão de Arquitetura

Implementou-se um ecossistema completo de modernização de interface visual, cockpit financeiro e produtividade, garantindo **100% de compatibilidade com o Schema `v: 7` contábil** e sem alterar qualquer regra de cálculo contábil ou persistência de transações do `openmoney.json`.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 OpenMoney Shell Desktop                                 │
├──────────────────────┬─────────────────────────────────────────────────────────────────┤
│ Top Bar Superior     │ [Breadcrumbs]          [⌘K Raycast]   [Cloud Sync] [Ajustes]    │
├──────────────────────┼─────────────────────────────────────────────────────────────────┤
│ Sidebar (ou MiniRail)│ Dashboard Geral (Cockpit)                                       │
│                      │ ┌─────────────────────────────────────────────────────────────┐ │
│ • Dashboard Geral    │ │ 1. Patrimônio Consolidado (Full Width: Real / Mês / Ano)    │ │
│ • + Novo Lançamento  │ ├──────────────────────────────┬──────────────────────────────┤ │
│ • Contas Favoritas   │ │ 2. Contas & Saldos Bancários │ 3. Radar de Vencimentos      │ │
│ • Contas Ativas      │ ├──────────────────────────────┼──────────────────────────────┤ │
│ • PLANEJAMENTO       │ │ 4. Faturas de Cartão Crédito │ 5. Gastos Categoria (nov/26) │ │
│ • MÓDULOS            │ └──────────────────────────────┴──────────────────────────────┘ │
│   - Categorias (1º)  │                                                                 │
│   - Ajustes (2º)     │ Modo Extrato / Lançamentos:                                     │
│   - Gestão Contas(3º)│ [Lista Diária] vs [Datagrid Contínua: Data | Conta | Fav | ...] │
│   - Backups/Logs...  │ [Ordenação Data: ↑ Mais Antigos (Padrão) / ↓ Mais Recentes]     │
└──────────────────────┴─────────────────────────────────────────────────────────────────┘
```

---

## 3. Especificação Detalhada dos Componentes

### 3.1. Dashboard Geral (`DashboardOverviewView`)

O Cockpit Geral é a visão executiva e analítica de saúde financeira, configurável como tela de inicialização do aplicativo.

#### A. Estrutura de Grid Responsiva (2 a 3 Colunas)
- Container: `SingleChildScrollView` com padding responsivo (`isCompact ? 16 : 24`).
- Algoritmo de Colunas com `LayoutBuilder` e `Wrap(spacing: 16, runSpacing: 16)`:
  - $\text{Largura} \ge 1200\text{px}$: **3 colunas** lado a lado ($\text{colW} = (\text{totalW} - 32) / 3$).
  - $760\text{px} \le \text{Largura} < 1200\text{px}$: **2 colunas** lado a lado ($\text{colW} = (\text{totalW} - 16) / 2$).
  - $\text{Largura} < 760\text{px}$: **1 coluna** vertical ($\text{colW} = \text{totalW}$).
- **Prevenção de Overflows:** Todos os títulos dos cabeçalhos dos cards utilizam `Expanded` com `Flexible` e `TextOverflow.ellipsis`, impedindo estritamente a aparição de faixas listradas de overflow durante redimensionamentos de tela.

#### B. Reposicionamento de Cards (Horizontal e Vertical)
- Em vez de `ReorderableListView` (que forçava 1 coluna vertical e criava barras cinzas indesejadas), cada card conta no cabeçalho com botões minimalistas `_buildMoveButtons`:
  - `chevron_left_rounded` (`‹`): Move o card para trás na ordem da lista `dashboardWidgetsOrder` (horizontalmente para a esquerda ou verticalmente para a linha anterior).
  - `chevron_right_rounded` (`›`): Move o card para frente na ordem da lista `dashboardWidgetsOrder` (horizontalmente para a direita ou verticalmente para a linha seguinte).
- A ordem resultante é persistida imediatamente nas preferências do usuário.

#### C. Cabeçalho do Dashboard
- Saudação dinâmica conforme horário do dia:
  - $< 12\text{h}$: "Bom dia, OpenMoney"
  - $< 18\text{h}$: "Boa tarde, OpenMoney"
  - $\ge 18\text{h}$: "Boa noite, OpenMoney"
- Data formatada por extenso (ex: "Terça-feira, 10/11/2026").
- **Sem etiqueta ou badge com o texto 'Cockpit Geral'**.
- Botão primário `Novo Lançamento` e botão de atalho direto para `Ajustes & Personalização`.

#### D. Card 1: Patrimônio Consolidado (`patrimony`)
- **Largura:** Ocupa a largura total da tela (`fullWidth = true`).
- **3 Blocos de KPI:**
  1. *Saldo Real Disponível:* Soma dos saldos não previstos (`predicted: false`).
  2. *Previsto no Mês:* Saldo previsto na competência corrente (`predicted: true`), com indicação abreviada do mês (ex: `nov/26`).
  3. *Previsto no Ano:* Saldo projetado no ano fiscal corrente.
- **Tipografia e Altura:** Apenas 2 linhas de texto por bloco (Linha 1: Título em fonte regular 12px; Linha 2: Valor financeiro em fonte negrito 18px com números tabulares).
- **Em telas estreitas (< 650px):** Os blocos se organizam verticalmente mantendo largura idêntica `width: double.infinity`.
- **Modo Privacidade / Ocultação de Saldo (`hidePatrimonyBalance`):**
  - O ícone de olho no cabeçalho oculta os valores deste card substituindo-os por `••••••••`.
  - **Isolamento Estrito:** A ocultação afeta **exclusivamente** o card de patrimônio, **não ocultando** os saldos do card de Contas & Saldos.

#### E. Card 2: Contas Bancárias & Saldos (`accounts`)
- **Exclusão Estrita de Cartões de Crédito:**
  - Exibe unicamente contas bancárias, contas correntes, investimentos e dinheiro (`a.type != 'Cartão de crédito' && a.card == null`). Cartões são gerenciados no card dedicado de Faturas.
- **Sequência de Contas:**
  - Primeiro o grupo de **CONTAS FAVORITAS ★**, seguido pelo grupo de **DEMAIS CONTAS ATIVAS**.
  - Não exibe contas inativas.
- **Ordenação Direta de Contas:**
  - Cada linha de conta possui setas discretas `arrow_drop_up` e `arrow_drop_down` para reordenar a sequência de exibição entre contas do mesmo grupo.
- **Saldos Sempre Visíveis:**
  - Exibe o saldo contábil real formatado em moeda corrente (ex: `R$ 4.250,00`). Não é afetado pela ocultação de saldo do patrimônio.
- **Parâmetros de Exibição (Configurados exclusivamente em Ajustes & Personalização):**
  1. `dashboardAccountsShowActive`: Booleano que define se exibe ou oculta as demais contas ativas (quando falso, o card foca apenas nas contas favoritas).
  2. `dashboardAccountsShowZeroBalance`: Booleano que define se exibe ou oculta contas cujo saldo seja exatamente `R$ 0,00`.
- **Cabeçalho Limpo:** Título e botões de reordenação do card, sem botões de filtro intermediários poluindo a interface.

#### F. Card 3: Radar de Vencimentos (`dueBills`)
- Apresenta as contas a pagar e receber pendentes que vencem dentro da janela de antecedência (`store.reminderDaysAhead`, padrão 7 dias).
- Itens vencidos recebem destaque de alerta em vermelho (`colors.expense`).
- Botão de quitação rápida em 1 clique (`check_circle_outline`) que executa `store.toggleReconciled(item.tx.id)`.
- Botão "Ver todos →" navegando diretamente para o módulo de Contas a Pagar & Receber.

#### G. Card 4: Faturas de Cartões de Crédito (`cards`)
- Lista todos os cartões cadastrados e ativos no sistema (`a.type == 'Cartão de crédito' && a.card != null && !a.isInactive`).
- Título limpo: "Faturas de Cartão de Crédito" (sem contador numérico de cartões).
- Para cada cartão: logotipo do banco, nome do cartão, valor da fatura aberta do ciclo corrente, data de fechamento e data de vencimento formatadas, e atalho "Ver Fatura →".

#### H. Card 5: Gastos por Categoria do Mês (`categories`)
- **Regra Contábil:** Integrado ao motor `store.buildMonthlyReport(store.month)`.
- **Desconsideração Estrita de Transferências:**
  - Ignora transações de transferência entre contas (`tx.xfer != null || tx.peer != null`).
  - Ignora liquidações automáticas de faturas (`tx.auto == true`).
  - Ignora categorias desmarcadas de relatórios (`!isCategoryIncludedInReports`).
- **Total do Cabeçalho:** Exibe estritamente o total real de pagamentos e despesas do mês (`reportData.totalExpense`).
- **Título com Mês Abreviado:** Formato compacto `nov/26` (ex: `Gastos por Categoria (nov/26)`).
- Top 5 categorias com barra horizontal proporcional ao total de gastos (`group.total / totalExpenses`).

#### I. Card de Limite de Gastos / Orçamento (`budget`)
- **Eliminado:** Removido do cockpit geral e da listagem de seleção de widgets do dashboard.

---

### 3.2. Barra Lateral (Sidebar) & Mini Rail

#### A. Sidebar Normal Expandida (280px)
- **Cabeçalho:** Logo do App, identificação da base de dados local, seletor de arquivo de banco de dados e botão de recolhimento para Mini Rail.
- **Remoção do Alternador Claro/Escuro:** Retirado da barra lateral, ficando centralizado exclusivamente na barra superior (Top Bar).
- **Remoção do Card de Patrimônio:** O container de patrimônio foi retirado da barra lateral, mantendo-a enxuta e focada em navegação.
- **Posicionamento e Alinhamento:**
  1. `_SidebarNavTile` do **Dashboard Geral** posicionado no **topo absoluto** da navegação.
  2. Botão **+ Novo Lançamento** posicionado logo abaixo do Dashboard Geral, com estilização `alignment: Alignment.centerLeft` (texto e ícone alinhados à esquerda).
- **Seção de Contas:**
  - Contas Favoritas (com quantidade e botão de recolher/expandir).
  - Contas Ativas (com quantidade e botão de recolher/expandir).
  - Contas Inativas (colapsadas por padrão).
- **Reorganização das Seções:**
  - **`PLANEJAMENTO`:** Lançamentos, Contas a Pagar & Receber, Compras Parceladas, Fluxo de Caixa, Relatório, Limite de Gastos, Pesquisa Global. *(Removidos: Categorias e Ajustes)*.
  - **`MÓDULOS`:**
    1. **Categorias e Subcategorias** (1º item)
    2. **Ajustes & Personalização** (2º item)
    3. **Incluir Nova Conta** (3º item - abre modal de criação de nova conta)
    4. Backups de Segurança / Conta Cloud
    5. Logs de Alterações
    6. Importação / Exportação
    7. Excluir Lançamentos
    8. Buscar Atualizações
    9. Ajuda e Manual
    10. Sobre o OpenMoney

#### B. Sidebar Mini Rail (64px / 48px)
- **Topo:** Botão padronizado no topo para expandir o menu (`Icons.menu_open`), alinhado com a posição do botão de recolher da barra expandida.
- **Logo:** Logotipo do aplicativo centralizado.
- **Dashboard Geral:** Ícone `dashboard_outlined` posicionado **acima** do botão de inclusão de lançamento.
- **Botão Novo Lançamento:** Reduzido para `IconButton(icon: Icon(Icons.add_circle_outline, size: 20))` ficando com o mesmo tamanho e proporção de todos os demais ícones.
- **Contas Bancárias:**
  - Exibe rigorosamente as contas favoritas primeiro e depois as ativas regulares, **sem contas inativas**.
  - Tooltip flutuante com nome da conta, tipo e saldo atual formatado.
- **Rodapé:** Atalho direto para Ajustes & Personalização (sem botão redundante de expandir no rodapé).

---

### 3.3. Ordenação de Lançamentos por Data (Crescente / Decrescente)

Implementado no razão de cada conta (`AccountLedgerView`) e na visão de lançamentos consolidados (`AllTransactionsView`).

#### A. Comportamento e Regras Contábeis
- **Ordem Padrão: Crescente (`sortAscendingDate = true`):**
  - Mais antigos primeiro, mais recentes no fim.
  - O cálculo do saldo progressivo diário (`runningReal` e `runningPred`) é **sempre calculado cronologicamente** a partir do saldo inicial (`openingReal` e `openingPred`).
- **Ordem Alternativa: Decrescente (`sortAscendingDate = false`):**
  - Mais recentes no topo, mais antigos no fim.
  - A lista de grupos diários (`dayGroups`) e os itens internos de cada dia são invertidos para exibição, **preservando com exatidão os saldos de fechamento do dia** (`closingReal` e `closingPred`).
- **No Modo Tabela Datagrid:** As transações são ordenadas de acordo com `store.sortAscendingDate`.
- **Na Visão Anual Consolidada:** Quando decrescente, os meses também são invertidos para exibir Dezembro no topo até Janeiro no fim.
- **Ícone e Tooltip:**
  - Crescente: Ícone `arrow_upward_rounded` com tooltip "Ordem de Data: Mais antigos primeiro (Clique para Mais recentes primeiro)".
  - Decrescente: Ícone `arrow_downward_rounded` com tooltip "Ordem de Data: Mais recentes primeiro (Clique para Mais antigos primeiro)".

---

### 3.4. Modo Tabela Datagrid com Ícone da Conta

Disponível em `DatagridTransactionTable`:
- Alternador de visualização no cabeçalho (*Lista Diária* vs *Tabela Datagrid*).
- **Sequência de Colunas Padronizada:**
  1. **Data:** Largura fixa de 90px com ordenação.
  2. **Conta (com Logotipo e Nome):** Posicionada imediatamente após a Data e antes do Favorecido. Renderiza o `AccountLogoWidget(account: acc, size: 16, cornerRadius: 4)` seguido pelo nome da conta em cor de destaque `accent`.
  3. **Favorecido / Descrição:** Coluna expandida (`flex: 4`) com memo opcional em itálico.
  4. **Categoria:** Coluna expandida (`flex: 3`).
  5. **Valor:** Largura de 120px, alinhado à direita, verde para receitas e vermelho para despesas.
  6. **Ações Rápidas (Hover Actions):** Surgem ao passar o mouse sobre a linha:
     - Reconciliar (`rec`)
     - Editar (abre modal completo de edição)
     - Duplicar (`showTransactionCopyModal`)
     - Excluir (`showDeleteTransactionDialog`)

---

### 3.5. Central de Ajustes & Personalização (`SettingsView`)

Tela unificada dividida em seções temáticas em cartões de vidro:
1. **Geral & Inicialização:**
   - Tela de Abertura Padrão: *Dashboard Geral* ou *Última Conta Utilizada*.
   - Dias de Antecedência para Lembretes de Vencimento: Slider e Stepper (1 a 60 dias).
   - Ocultar saldos do patrimônio por padrão.
   - Modo de Abatimento de Previsões: *Por Mês* ou *Por Fatura de Cartão*.
2. **Aparência, Cores & Estilo Visual:**
   - Tema Claro / Escuro.
   - 6 Paletas de Cor de Destaque (*Accent Palettes*):
     - `sky` (Azul Oceano, `#0284C7`)
     - `emerald` (Esmeralda Financeiro, `#059669`)
     - `indigo` (Índigo Executivo, `#6366F1`)
     - `orange` (Sunset Laranja, `#EA580C`)
     - `cyan` (Ciano / Teal, `#0891B2`)
     - `slate` (Grafite Minimalista, `#475569`)
   - Estilo de Superfície: *Liquid Glass* (vidro translúcido com blur) vs *Flat Clean* (superfícies opacas de alta performance).
   - Escala de Zoom da Interface: 85% a 160%.
3. **Layout & Barra Lateral:**
   - Densidade da Interface: *Compacta* (linhas densas ideais para telas contábeis) vs *Confortável*.
   - Modo da Barra Lateral: *Expandida (280px)* vs *Mini Rail (64px)*.
4. **Dashboard & Widgets:**
   - Checkboxes de ativação dos widgets: Patrimônio Consolidado, Contas Bancárias & Saldos, Radar de Vencimentos, Faturas de Cartão, Gastos por Categoria, Ações Rápidas.
   - Switch: *Exibir demais contas ativas no card* (`dashboardAccountsShowActive`).
   - Switch: *Exibir contas com saldo R$ 0,00* (`dashboardAccountsShowZeroBalance`).
5. **Extrato & Lançamentos:**
   - Modo de Visualização Padrão: *Lista Diária* vs *Tabela Datagrid Contínua*.
   - Ordenação Padrão por Data: *Mais antigos primeiro (Crescente)* vs *Mais recentes primeiro (Decrescente)*.
6. **Inteligência Artificial (Gemini AI BYOK):**
   - Ativação do motor de IA e campo seguro para Google Gemini API Key.
7. **Atalhos de Teclado:**
   - Tabela de atalhos rápidos (`Cmd+K`, `Cmd+B`, `Cmd+F`, `Cmd+O`, `Cmd+I`, `Cmd+L`, `Cmd++`, `Cmd+-`, `Cmd+0`).

---

## 4. Dicionário de Preferências e Persistência

Todas as novas opções são armazenadas em `config.json` (Desktop) e no `localStorage` (Web), isoladas da base contábil `openmoney.json`:

| Chave de Configuração | Tipo | Valor Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `startupView` | `String` | `'lastAccount'` | Tela padrão de abertura: `'dashboard'` ou `'lastAccount'`. |
| `accentColorKey` | `String` | `'sky'` | Identificador da paleta de destaque: `sky`, `emerald`, `indigo`, `orange`, `cyan`, `slate`. |
| `isFlatClean` | `bool` | `false` | Desativa efeitos de vidro/blur em favor de modo plano opaco. |
| `uiDensityMode` | `String` | `'compact'` | Densidade de espaçamentos: `'compact'` ou `'comfortable'`. |
| `sidebarMode` | `String` | `'expanded'` | Modo do menu lateral: `'expanded'` ou `'miniRail'`. |
| `ledgerViewMode` | `String` | `'list'` | Visualização do extrato: `'list'` ou `'table'`. |
| `sortAscendingDate` | `bool` | `true` | Ordem de data dos lançamentos: `true` (crescente) ou `false` (decrescente). |
| `dashboardAccountsShowActive` | `bool` | `true` | Se falso, o card de contas exibe apenas as contas favoritas. |
| `dashboardAccountsShowZeroBalance` | `bool` | `true` | Se falso, oculta do card as contas com saldo `R$ 0,00`. |
| `dashboardWidgetsOrder` | `List<String>` | `['patrimony', 'accounts', 'dueBills', 'cards', 'categories', 'quickActions']` | Lista ordenada com as chaves dos cards visíveis no Dashboard. |
| `dashboardWidgets` | `Map<String, bool>` | `{...: true}` | Mapa de ativação individual de cada widget. |
| `hidePatrimonyBalance` | `bool` | `false` | Oculta exclusivamente os saldos do card de patrimônio consolidado. |

---

## 5. Guia de Implementação e Paridade para a Versão Swift

Para replicar exatamente a mesma experiência no aplicativo nativo **OpenMoney Swift** (`/Users/fabiano/Developer/OpenMoneySwift`), siga o seguinte roteiro arquitetural:

### 5.1. Extensões no Modelo e Repositório (`Models.swift` e `Store.swift`)
1. **Adicionar ao `SidebarView` enum em `Store.swift`:**
   - Adicionar cases `.dashboard` e `.settings`.
2. **Adicionar propriedades de preferências persistidas em `UserDefaults` (ou `config.json`):**
   - `var startupView: String { get set }`
   - `var sidebarMode: String { get set }` (Expanded vs Mini Rail)
   - `var ledgerViewMode: String { get set }` (List vs Table)
   - `var sortAscendingDate: Bool { get set }` (default `true`)
   - `var dashboardAccountsShowActive: Bool { get set }` (default `true`)
   - `var dashboardAccountsShowZeroBalance: Bool { get set }` (default `true`)
   - `var dashboardWidgetsOrder: [String] { get set }`
   - `var dashboardWidgets: [String: Bool] { get set }`
3. **Método utilitário para mover widgets:**
   - `func moveDashboardWidgetStep(key: String, step: Int)`

### 5.2. Nova View de Dashboard no macOS e iOS (`DashboardOverviewView.swift`)
1. **Layout em Colunas:**
   - Implementar usando `LazyVGrid` ou `HStack`/`VStack` responsivo no SwiftUI baseado em `GeometryReader`:
     - Largura $\ge 1200\text{pt}$: 3 colunas.
     - Largura entre $760\text{pt}$ e $1199\text{pt}$: 2 colunas.
     - Largura $< 760\text{pt}$: 1 coluna.
2. **Cards:**
   - **Patrimônio:** Card ocupando a largura total com 3 retângulos de métrica (Real, Mês `nov/26`, Ano `2026`). Ocultação com `hidePatrimonyBalance` afeta apenas este card.
   - **Contas & Saldos:** Filtro estrito `type != "Cartão de crédito" && card == nil`. Filtrar `dashboardAccountsShowZeroBalance`. Botões para subir/descer contas. Saldos sempre visíveis.
   - **Radar de Vencimentos:** Itens com antecedência de `reminderDaysAhead`, botão de quitação rápida `toggleReconciled`.
   - **Faturas de Cartão:** Todos os cartões ativos com valores de fatura aberta e datas de fechamento/vencimento.
   - **Gastos por Categoria:** Integrado ao `buildMonthlyReport`, ignorando transferências, título compacto `nov/26`, total real de despesas.
   - **Eliminar:** Não incluir widget de limite de gastos no dashboard.
3. **Botões de Navegação dos Cards:**
   - No topo de cada card, botões `Image(systemName: "chevron.left")` e `Image(systemName: "chevron.right")` para mover os cards na grade.

### 5.3. Nova View de Configurações (`SettingsView.swift`)
- Implementar tela de Ajustes no macOS usando `TabView` ou `Form` estilizado com as seções: Geral, Aparência, Layout/Sidebar, Dashboard, Extrato, IA e Atalhos.

### 5.4. Ajustes na Barra Lateral (`SidebarPanel.swift` e `iOSViews.swift`)
- Posicionar `Dashboard Geral` no topo absoluto, acima de `+ Novo Lançamento`.
- Alinhar texto do botão `Novo Lançamento` à esquerda.
- No `Mini Rail` (quando implementado em SwiftUI):
  - Expandir no topo.
  - Ícone de Dashboard acima de Novo Lançamento.
  - Botão de Novo Lançamento do mesmo tamanho dos demais ícones.
  - Contas no Mini Rail: apenas favoritas e ativas regulares, sem inativas.
- Remover o bloco de patrimônio consolidado do menu lateral.
- Remover alternador claro/escuro do cabeçalho da barra lateral.
- Seção Módulos com:
  1. Categorias e Subcategorias
  2. Ajustes & Personalização
  3. Incluir Nova Conta
  4. Backups, Logs, etc.

### 5.5. Ordenação por Data no Extrato (`AccountLedgerView.swift` e `AllTransactionsView.swift`)
- Botão no toolbar de alternância `Image(systemName: store.sortAscendingDate ? "arrow.up" : "arrow.down")`.
- Ordem padrão: crescente (mais antigos primeiro).
- Se decrescente: inverter a lista de seções diárias mantendo os saldos de fechamento calculados pela ordem cronológica.

### 5.6. Tabela Datagrid no Swift
- Em `AllTransactionsView`: posicionar a coluna da Conta logo após a Data e antes do Favorecido, incluindo o ícone/logotipo do banco ao lado do nome da conta.

---

## 6. Validação e Testes Automatizados

O ecossistema multi-stack foi validado e aprovado com 100% de sucesso em todas as plataformas:
- **OpenMoney Flutter (macOS, Windows, Web, Mobile):**
  - **`flutter analyze`:** 0 erros de compilação.
  - **`flutter test`:** **60 de 60 testes automatizados aprovados (100% verde)**, assegurando ausência de regressões contábeis e paridade estrita com o Schema `v: 7`.
- **OpenMoney Swift (macOS & iOS):**
  - **`swift build`:** 0 erros.
  - **`./build-app.sh`:** Compilação nativa, assinatura `codesign` e empacotamento `.zip` finalizados com sucesso (Build 141).
  - Paridade funcional e comportamental 1:1 rigorosamente atendida.
