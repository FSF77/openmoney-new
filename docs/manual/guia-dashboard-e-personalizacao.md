# Guia do Usuário: Dashboard Geral, Cockpit e Central de Personalização

Este manual apresenta o guia operacional detalhado para utilização do **Dashboard Geral**, da **Central de Ajustes & Personalização**, dos novos modos de visualização em **Datagrid** e da **Navegação Adaptativa** disponíveis no ecossistema **OpenMoney** (Desktop macOS, Windows, Web, Mobile iOS e Android).

---

## 1. 🌟 O Dashboard Geral (Cockpit Executivo)

O **Dashboard Geral** funciona como a torre de controle da sua vida financeira. Em vez de abrir compulsoriamente no extrato de uma conta bancária específica, o OpenMoney consolida as métricas vitais e as decisões do dia a dia em cartões dinâmicos que podem ser reorganizados e ativados conforme sua necessidade.

### Cabeçalho Dinâmico
- **Saudação Inteligente:**
  - **No Modo Online (Cloud):** Exibe saudação temporal com o primeiro nome do usuário autenticado (ex.: *"Boa tarde, Fabiano"*).
  - **No Modo Local (Offline):** Exibe a saudação temporal elegante sem menção a nomes ou termos de sistema (ex.: *"Boa tarde"*).
- **Data Extensa:** Identificação do dia corrente formatada por extenso em português.
- **Botão "+ Novo Lançamento":** Acesso imediato à inclusão de transações em qualquer conta. Em telas de smartphones ou janelas compactas, o botão se adapta para um formato circular limpo contendo apenas o ícone de adição (`+`).
- **Botão "Ajustes":** Atalho de acesso direto à tela de **Ajustes & Personalização**.

---

## 2. 🗂️ Detalhamento dos Cards do Dashboard

Todos os cards do dashboard contam com controles superiores de reposicionamento horizontal/vertical através das setas direcionais (`←` e `→` ou `chevron`), permitindo posicionar os módulos prioritários na ordem de sua preferência.

### 2.1. Patrimônio Consolidado
Reúne o panorama patrimonial líquido de todas as contas ativas cadastradas:
- **Saldo Real:** Saldo efetivamente disponível e conciliado nos bancos e caixas.
- **Previsto Mês:** Saldo projetado até o último dia da competência do mês corrente, considerando todas as receitas e despesas pendentes.
- **Previsto Ano:** Saldo acumulado projetado até 31 de dezembro do ano corrente.
- **Privacidade com 1 Clique (Ocultar Saldos):** Botão em formato de olho (`visibility`) apenas com tooltip informativo ("Ocultar valores" / "Exibir valores"), sem rótulo textual para máxima discrição. Mascara os valores exclusivamente deste card (`••••••`).

### 2.2. Contas Bancárias ("Contas")
Apresenta o livro resumido de contas correntes e caixas financeiros ativos (excluindo cartões de crédito e contas de investimentos/poupança, que contam com cards dedicados):
- **Privacidade Individual (Ocultar Saldos):** Ícone de olho no cabeçalho com tooltip, permitindo ocultar/exibir os saldos de contas de forma totalmente independente e persistida nas preferências.
- **Ordem dos Registros:** A listagem segue rigorosamente a hierarquia visual definida na barra lateral: primeiro as **Contas Favoritas (★)** e, opcionalmente, as **Demais Contas Ativas**.
- **Design Limpo e sem Botões Manuais:** As setas de subir/descer foram removidas do card para evitar poluição visual; a ordenação é herdada diretamente do menu lateral.
- **Apresentação Clara de Saldos:**
  - O saldo real é exibido de forma direta e limpa (sem o prefixo redundante "Real").
  - A linha **Prev. mês** é exibida **apenas quando o saldo previsto for diferente do saldo real**, evitando repetições desnecessárias quando não há lançamentos futuros pendentes.
- **Filtro de Contas Zeradas:** Configuração personalizável que permite ocultar automaticamente contas com saldo R$ 0,00.
- **Acesso Rápido:** Clicar na linha da conta direciona imediatamente para o extrato detalhado dela.

### 2.3. Investimentos & Poupança ("Investimentos")
Card dedicado para a gestão das reservas financeiras e patrimoniais:
- **Privacidade Individual (Ocultar Saldos):** Ícone de olho no cabeçalho com tooltip, permitindo ocultar/exibir os saldos de investimentos e poupança de forma independente e persistida.
- **Abrangência:** Reúne exclusivamente as contas categorizadas como **Investimento** e **Poupança**.
- **Apresentação Clara de Saldos:**
  - Exibição direta do saldo consolidado no presente.
  - A linha **Prev. mês** só aparece quando houver previsões ou agendamentos que alterem a posição ao final do mês.
- **Filtro de Saldos Zerados (R$ 0,00):** Configuração personalizável para ocultar contas de investimento ou poupança que estejam temporariamente sem saldo.
- **Navegação Direta:** Clicar em qualquer investimento abre instantaneamente o extrato e histórico de aportes e resgates da conta.

### 2.4. Faturas de Cartão de Crédito
Consolida o ciclo atual de todos os cartões de crédito ativos:
- **Privacidade Individual (Ocultar Valores):** Ícone de olho no cabeçalho com tooltip para mascarar as faturas dos cartões de crédito de forma individual e persistida.
- **Valor da Fatura:** Exibido diretamente com o sinal negativo representativo da obrigação a pagar (ex.: `-R$ 1.250,00`), eliminando o rótulo redundante "Total".
- **Linha "Conciliado":** Substitui o antigo termo "Atual", destacando o valor já conferido e faturado. É exibida **apenas quando o valor conciliado for diferente do valor total da fatura**.
  > *Exemplo prático:* Se a fatura total for de R$ 5.000,00 e já foram conciliados R$ 4.000,00, a linha secundária exibe `Conciliado -R$ 4.000,00`. Se todos os R$ 5.000,00 já estiverem conciliados, a linha secundária não é exibida, mantendo o card limpo e direto.
- **Filtro de Faturas Zeradas (R$ 0,00):** Configuração personalizável que permite ocultar do card cartões que não possuam gastos no ciclo atual, destacando somente as faturas com compromissos abertos.
- **Datas do Ciclo:** Indicação visual da data de fechamento e da data de vencimento da fatura.
- **Atalho "Ver Fatura":** Direciona com um clique para a tela do cartão com a fatura aberta já pré-selecionada.

### 2.5. A Pagar (Despesas a Vencer)
Card dedicado exclusivamente para controle de saídas financeiras e compromissos:
- **Abrangência:** Reúne apenas despesas pendentes de conciliação para os próximos dias (configurável: 1 a 60 dias).
- **Valores com Sinal Negativo:** Os valores são exibidos com sinal negativo (ex.: `-R$ 150,00`) e cor semântica de saída (`omRed`), reforçando a natureza do desembolso.
- **Conciliação em 1 Clique:** Botão direto para marcar a conta como paga.
- **Badge de Alerta:** Contador de pendências e destaque de atrasos.

### 2.6. A Receber (Receitas a Vencer)
Card dedicado exclusivamente para controle de entradas financeiras e faturamentos previstos:
- **Abrangência:** Reúne apenas receitas pendentes de recebimento dentro da janela de antecedência configurada.
- **Valores em Destaque:** Exibição clara e positiva dos valores a receber com cor semântica de entrada (`omGreen`).
- **Confirmação em 1 Clique:** Botão direto para marcar a receita como recebida.

### 2.7. Gastos por Categoria do Mês
Painel gráfico com os maiores centros de custo do mês atual:
- **Título Padronizado:** Exibição amigável da competência (ex.: `nov/26`).
- **Total Real de Despesas:** Badge consolidando o total de saídas financeiras legítimas do mês com sinal negativo (ex.: `-R$ 3.450,00`).
- **Rigor Contábil:** Exclui rigorosamente transferências entre contas e quitações automáticas de faturas para evitar distorções de gastos repetidos.
- **Barras de Distribuição:** Exibe o ranking das 5 maiores categorias de gastos com percentual relativo e valor monetário com sinal negativo (ex.: `-R$ 1.200,00 (34.8%)`).

### 2.8. Ações Rápidas
Grade de atalhos rápidos com 1 clique para as principais funções do sistema:
- Lançamentos (Extrato Geral Consolidado)
- Contas a Pagar & Receber
- Compras Parceladas
- Matriz de Fluxo de Caixa
- Relatórios Mensais e Anuais
- Gestão de Categorias e Subcategorias
- Ajustes & Personalização

---

## 3. ⚙️ Central de Ajustes & Personalização (`SettingsView`)

A Central de Ajustes unifica todas as preferências operacionais e visuais do sistema em um único painel acessível pelo menu superior, pela barra lateral em **MÓDULOS › Ajustes & Personalização** ou pelo atalho `Cmd + ,` (`Ctrl + ,`):

1. **Inicialização do Sistema:**
   - Escolha entre abrir diretamente no **Dashboard Geral**, na **Última Conta Utilizada** ou em uma **Conta Específica**.
2. **Personalização do Dashboard:**
   - Ativação ou desativação individual de cada um dos cards (**Patrimônio**, **Contas**, **Investimentos**, **A Pagar**, **A Receber**, **Cartões**, **Categorias** e **Ações Rápidas**).
   - Parâmetro para **Exibir/Ocultar contas com saldo zerado (R$ 0,00)** no card Contas.
   - Parâmetro para **Exibir/Ocultar investimentos com saldo zerado (R$ 0,00)** no card Investimentos.
   - Parâmetro para **Exibir ou ocultar faturas com valor zerado (R$ 0,00)** no card de Cartões de Crédito.
   - Parâmetro para **Exibir ou ocultar as demais contas ativas** no card Contas (mantendo apenas favoritas).
   - Definição da antecedência em dias de contas a pagar e receber.
3. **Lançamentos & Extratos:**
   - **Direção Padrão de Ordenação por Data:** Escolha entre **Crescente** (mais antigos primeiro, padrão contábil) ou **Decrescente** (mais recentes primeiro).
   - **Inserção Rápida no Extrato das Contas:** Habilita ou desabilita o bloco inline de campos no topo do extrato de cada conta. Ao desativar, todos os campos inline são ocultados para maximizar o espaço útil vertical de rolagem dos lançamentos, e um botão circular de destaque `+` é adicionado ao lado do nome da conta no cabeçalho para abrir a janela modal de lançamento pré-selecionando a conta atual.
4. **Aparência e Cores de Destaque:**
   - Seleção de paleta de destaque dinâmica (**Azul Oceano**, **Esmeralda**, **Índigo**, **Sunset Laranja**, **Ciano Futurista** ou **Titanium Slate**).
   - **Padronização Visual Completa:** Todos os botões contornados (`Outlined`), botões preenchidos (`Filled`), seletores de abas (`SegmentedButton`), chips de filtro e botões de exportação (CSV, PDF) adotam a cor de destaque com fundo translúcido suave, eliminando qualquer tom lilás padrão do sistema.
5. **Layout e Densidade:**
   - Modo de exibição da barra lateral: **Expandida** (285px com lista detalhada de contas e seções completas de Planejamento e Módulos) vs. **Mini Rail** (64px com navegação condensada por ícones).
   - **Navegação Integral no Mini Rail:** O Mini Rail disponibiliza a lista completa de ícones e tooltips em duas seções organizadas por divisores:
     - **Planejamento:** Lançamentos, Contas a Pagar & Receber, Compras Parceladas, Fluxo de Caixa, Relatório, Previsões, Limite de Gastos e Pesquisa Global.
     - **Módulos & Ferramentas:** Categorias e Subcategorias, Tags, Ajustes & Personalização, Incluir Nova Conta, Logs de Alterações, Importação / Exportação, Cloud & Sincronização, Excluir Lançamentos, Ajuda e Manual e Sobre o OpenMoney.
   - Modo de exibição do extrato (Lista Diária vs. Datagrid Contínua).
   - Escala tipográfica e zoom visual de acessibilidade.
6. **Inteligência Artificial (BYOK):**
   - Ativação e configuração da chave de API do Google Gemini Flash para leitura e interpretação multimodal de recibos fiscais.

---

## 4. ✍️ Tela de Novo Lançamento & Lançamentos em Série

A tela/modal de **Novo Lançamento** conta com ergonomia aprimorada para agilizar entradas manuais:
- **Seletor Triplo de Tipo de Lançamento:** Além de `− Despesa` e `+ Receita`, inclui opção de primeira classe para `⇄ Transferência`. Ao selecionar transferência, a interface substitui automaticamente o seletor de categorias pelo seletor explícito de **"Conta de Destino"**, facilitando a movimentação entre contas e cálculos cambiais de moedas distintas sem necessidade de navegar pela árvore de categorias.
- **Ordem Prioritária de Contas de Destino (Contas Normais › Cartões de Crédito no Fim):** No seletor de conta de destino da transferência, as opções são apresentadas priorizando primeiro as contas bancárias/operacionais (Favoritas seguidas de Ativas) e posicionando obrigatoriamente todas as contas do tipo **Cartão de Crédito no fim da lista** (mesmo as favoritas, organizadas entre si por favoritas e ativas), excluindo a conta de origem.
- **Botão "Salvar e Criar Outro":** Permite registrar a transação atual e manter o modal aberto com os campos de valor, favorecido e nota resetados, preservando a conta, a data e a tipologia selecionadas, com foco automático imediato no campo de descrição para a próxima entrada.
- **Botão "Salvar":** Salva a transação e fecha o modal retornando à visão de origem.

---

## 5. 📊 Extratos: Alternância de Ordenação por Data e Modo Datagrid

### 5.1. Ordenação Crescente / Decrescente com 1 Clique
No extrato de qualquer conta corrente, cartão de crédito ou no Extrato Geral Consolidado, o usuário pode alternar a ordem dos lançamentos com um clique:
- **No Extrato da Conta:** Clique na coluna de cabeçalho **"DIA"** para alternar a direção indicada pela seta (`arrow.up` para crescente, `arrow.down` para decrescente).
- **No Extrato Geral:** Botão de ordenação dedicado presente na barra de ferramentas superior.
- **Integridade Contábil:** A inversão afeta apenas a ordenação visual de apresentação; os saldos acumulados e cálculos diários continuam matematicamente perfeitos e imutáveis.

### 5.2. Modo Datagrid (Tabela Contínua)
Para usuários que realizam conciliações em lote ou trabalham com grande volume de movimentações diárias:
- Exibe todos os lançamentos em uma tabela contínua com linhas compactas.
- Sequência padronizada de colunas: **Status de Conciliação | Data | Conta (com logotipo oficial do banco) | Favorecido | Categoria | Nota | Valor**.
- **Tags Sutis de Metadados:** Exibe de forma compacta e discreta na coluna descritiva as etiquetas de recorrência, faturas vinculadas e previsões do mês.
- Ações rápidas exibidas ao passar o mouse sobre a linha (*hover*): editar, duplicar e excluir.

---

## 6. 📱 Experiência Mobile e Telas Compactas

Em dispositivos móveis ou janelas redimensionadas para largura inferior a 760 pixels:
- **Abertura Imediata:** O aplicativo abre diretamente no Dashboard Geral, eliminando etapas intermediárias.
- **Barra Superior Dedicada:** O antigo botão de início foi unificado com o ícone do **Dashboard** (`Icons.dashboard_rounded` no Flutter e `square.grid.2x2.fill` no iOS).
- **Botão Circular de Novo Lançamento:** No topo do dashboard, o botão "+ Novo Lançamento" adota um formato circular compacto com `+`, garantindo que caiba perfeitamente ao lado da saudação sem quebras de linha.
- **Grid Adaptativa de 1 Coluna:** Todos os cards se ajustam para a largura total do display, mantendo tipografia legível e sem qualquer transbordamento (*overflow*).
