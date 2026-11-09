# OpenMoney

<p align="center">
  <strong>Aplicativo financeiro moderno, multiplataforma e open source.</strong>
</p>

<p align="center">
  <img src="icon-1024.png" alt="OpenMoney Logo" width="128" height="128" />
</p>

---
## 🌐 Acesso Web

Acesso o site https://openmoney.app.br


## ⚡ Instalação Rápida (1-Click / Terminal)

Instale ou atualize para a versão mais recente do OpenMoney diretamente pelo terminal do seu sistema operacional com um único comando:

### 🍏 No macOS (Terminal)
Abra o aplicativo **Terminal** e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.sh | bash
```

> **O que o instalador faz no macOS:**
> 1. Fecha instâncias ativas do OpenMoney para evitar bloqueios de arquivo em atualização.
> 2. Consulta o feed oficial (`version.json`) com mecanismo *anti-cache* garantindo o download da versão mais recente.
> 3. Baixa o pacote oficial `OpenMoney-macOS-<versao>.zip`.
> 4. Instala ou substitui com segurança o aplicativo em `/Applications/OpenMoney.app`.
> 5. Remove as restrições de quarentena do Apple Gatekeeper (`xattr -cr`).
> 6. Inicializa o OpenMoney automaticamente.

---

### 🪟 No Windows (PowerShell / Prompt de Comando)
Abra o **PowerShell** (usuário padrão, **não** requer privilégios de Administrador) e execute:

```powershell
irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex
```

> **Alternativa pelo Prompt de Comando (CMD) ou atalho Executar (Win + R):**
> ```cmd
> powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex"
> ```
>
> **O que o instalador faz no Windows:**
> 1. Encerra processos do `openmoney.exe` em execução para liberar arquivos travados.
> 2. Consulta o feed oficial (`version.json`) com *anti-cache* para obter a versão atual.
> 3. Baixa e descompacta o pacote `OpenMoney-Windows-<versao>.zip` no diretório padrão do usuário (`%LOCALAPPDATA%\Programs\OpenMoney`).
> 4. Cria atalhos oficiais com ícone de alta resolução na **Área de Trabalho (Desktop)** e no **Menu Iniciar**.
> 5. Inicializa o aplicativo automaticamente.

---

## 🌟 Visão Geral e Filosofia

O **OpenMoney** une o rigor contábil, a previsibilidade e a robustez do lendário **Microsoft Money 99** a uma experiência visual contemporânea construída em Flutter com o design system **Liquid Glass** (vidro translúcido, iluminação de bordas, cartões flutuantes e suporte impecável aos modos Claro e Escuro).

### Princípios Fundamentais:
1. **Soberania Absoluta dos Dados (100% Local)**:
   - Sem cadastros obrigatórios, sem contas na nuvem proprietária, sem telemetria e sem dependência de internet para funcionar.
   - Sua base reside em um único arquivo legível e aberto: `openmoney.json`.
2. **Sincronização Livre e Transparente**:
   - Salve o arquivo `openmoney.json` no **iCloud Drive**, **OneDrive**, **Google Drive**, **Dropbox**, pen drive ou no disco local.
   - Integração com seletores nativos do sistema (`NSSavePanel` / `NSOpenPanel` no macOS; diálogos Win32 no Windows).
3. **OpenMoney Cloud & Sincronização em Tempo Real (Sync v2)**:
   - Suporte híbrido opcional: use bases locais em arquivo ou conecte sua conta online para sincronização instantânea em tempo real via Cloudflare D1/WebSockets.
   - **Backups Locais de Segurança:** No Desktop, o app gera backups diários e manuais compactados (`.zip`) no disco do seu computador, mesmo ao utilizar o modo online.
   - **Logs de Auditoria Centralizados:** Histórico completo de alterações com persistência remota e retenção de 30 dias.
   - **Segurança de Conta:** Criação e alteração de e-mail validadas por código numérico de 6 dígitos (Resend), com envio preventivo do backup `.zip` em caso de exclusão de dados.
4. **Precisão Financeira em Centavos Inteiros (`Int`)**:
   - Todos os valores monetários são calculados e armazenados internamente como centavos inteiros (`amt: Int`), eliminando dízimas periódicas e erros de arredondamento de ponto flutuante (`Double` / `Float`).
5. **Resiliência e Gravação Atômica**:
   - Proteção estrita contra corrupção em quedas de energia: a gravação ocorre em arquivo temporário com substituição atômica imediata.
   - Rotina automatizada de **Backups em ZIP** com histórico e retenção segura.

---

## 📐 Regras de Negócio e Governança Financeira

Esta seção consolida as regras fundamentais que regem o cálculo, a integridade e a operação do OpenMoney:

### 1. Contas e Integridade Histórica
- **Impossibilidade de Exclusão de Contas com Lançamentos**: Para proteger a rastreabilidade patrimonial e os relatórios fiscais/contábeis, o OpenMoney **não permite a exclusão física** de contas que possuam lançamentos vinculados. Caso o usuário tente excluir uma conta com movimentações, o sistema bloqueia a operação, informa o total de lançamentos e sugere a desativação da conta com 1 clique.
- **Desativação (Arquivamento) de Contas**: Contas inativas mantêm todo o seu histórico intacto em relatórios, fluxos de caixa e evolução patrimonial, mas deixam de aceitar novos lançamentos ou transferências. Podem ser reativadas a qualquer momento.
- **Exclusão de Contas Sem Uso**: Somente contas com **0 lançamentos** podem ser excluídas definitivamente, mediante confirmação expressa do usuário.

### 2. Cartão de Crédito e Faturas
- **Ciclo de Fechamento e Vencimento**: Cada cartão de crédito possui configuração do dia de fechamento (`closeDay`), dia de vencimento (`dueDay`) e conta de débito padrão (`pay`).
- **Identificação da Fatura pelo Vencimento (Padrão de Mercado)**:
  - Faturas de cartão de crédito são nomeadas e identificadas pela competência da sua **data de vencimento** (`dueDay`).
  - *Exemplo*: Um cartão com fechamento no dia 23 e vencimento no dia 03 do mês seguinte tem as compras realizadas de 24/09 a 23/10 vinculadas à **Fatura de Novembro** (vencimento em 03/11). Compras a partir de 24/10 integram a **Fatura de Dezembro** (vencimento em 03/12).
- **Navegação no Seletor de Mês e Tela de Lançamentos**:
  - No seletor de mês superior da tela de lançamentos de uma conta de cartão de crédito, ao selecionar **Novembro**, o sistema exibe os lançamentos da **Fatura de Novembro** (vencimento em Novembro), independentemente de terem ocorrido no final de setembro ou em outubro.
  - O cabeçalho exibe o detalhamento completo do ciclo: `Fatura Novembro de 2026 · Fecha dia 23 (23/10/2026) · Vence dia 3 (03/11/2026) · Débito em ...`.
- **Saldo Previsto por Competência de Vencimento**:
  - O **saldo previsto** de contas do tipo cartão de crédito (exibido na barra lateral e nos resumos da conta) considera rigorosamente a data de vencimento da fatura.
  - Ao selecionar Novembro, o valor previsto totaliza as compras da fatura que vence em Novembro, garantindo que compras já pertencentes à fatura seguinte (Dezembro) não antecipem ou onerem indevidamente a previsão financeira de Novembro.
- **Seleção Manual de Fatura (Override)**: Embora o sistema calcule a fatura padrão com base no ciclo de fechamento/vencimento, o usuário pode **escolher manualmente outra fatura** para qualquer lançamento (ex.: postergar ou antecipar uma compra de fechamento tardio). Essa opção está disponível tanto no macOS quanto no Windows/Web/Mobile.
- **Pagamento Parcial e Adiantamento de Fatura**:
  - O usuário pode registrar pagamentos totais ou parciais em qualquer data antes ou depois do vencimento (ex.: fatura de R$ 1.000 em Novembro com vencimento em 03/11; pagamento de R$ 500 no dia 15/10).
  - **Abatimento Automático no Vencimento**: A rotina automática de conciliação de faturas (`syncCards`) monitora todos os pagamentos parciais e despesas vinculadas à chave da fatura (`ik`). No vencimento, o sistema gera o agendamento de cobrança cobrando **apenas o saldo remanescente**.
  - **Fatura Liquidada**: Se os pagamentos cobrirem 100% da fatura (saldo restante $\le 0$), a cobrança automática no vencimento é cancelada e a fatura recebe o status **LIQUIDADA**.
- **Migração Automática e Transparente da Base (v7)**:
  - Bases legadas criadas em versões anteriores com chave de fatura baseada no mês de fechamento são automaticamente migradas para a competência de vencimento na abertura do app (`db.v = 7`), mantendo histórico, tags, memos e vínculos de pagamentos intactos.
- **Exportação e Importação CSV**:
  - A coluna **Fatura** exporta a competência oficial de vencimento no formato amigável `MM/AAAA` (ex.: `11/2026`) e reconhece esse formato durante a importação.

### 3. Edição, Cópia e Migração de Lançamentos entre Contas
- **Copiar Lançamento como Novo**:
  - **Acesso**: Botão dedicado de cópia com ícone de dois documentos posicionado nas ações de cada linha de lançamento, no menu de contexto (botão direito) e nas ações de deslizar.
  - **Dados Pré-preenchidos**: Traz preenchidos automaticamente a descrição (com remoção inteligente de sufixos de parcelas anteriores `(x/y)`), a categoria ou transferência correspondente, a nota/observação e o valor original.
  - **Data Atual Automática**: O campo de data é inicializado por padrão com a **data atual (hoje)**, permitindo alteração rápida via seletor de data.
  - **Flexibilidade Total de Conta e Fatura**: Permite selecionar qualquer conta ativa do sistema. Ao selecionar uma conta de cartão de crédito, o sistema calcula e associa automaticamente a fatura correspondente.
  - **Definição de Repetição**: Permite escolher livremente se a nova movimentação será um lançamento **Único**, **Recorrente** (com periodicidade diária, semanal, mensal ou anual, com ou sem data de término) ou **Parcelado** (de 2x a 120x).
  - **Integridade do Registro Original**: Executa `store.addTransaction(...)`, gerando identificadores e séries 100% novas, sem alterar em nada o lançamento de origem.
- **Mover Lançamento de Conta**: Na tela de edição de lançamentos, é possível alterar a conta do lançamento.
- **Adequação Automática de Cartão de Crédito**:
  - Ao mover uma compra para um cartão de crédito, o sistema calcula e associa a chave da fatura correspondente (`ik`), permitindo ajuste manual.
  - Ao mover de um cartão para uma conta corrente ou dinheiro, a associação de fatura é removida (`ik = nil`).
- **Séries Recorrentes e Parceladas**: Caso o lançamento faça parte de um parcelamento ou recorrência e a edição seja aplicada para lançamentos futuros, todas as parcelas futuras não conciliadas são transferidas para a nova conta de destino.
- **Transferências**: Ao mover uma perna de uma transferência para outra conta, a contraparte par da transferência tem sua referência (`peer`) e sua descrição atualizadas de forma atômica e consistente.

### 4. Confirmações de Exclusão (Prevenção de Perda Acidental)
- **Lançamentos Avulsos**: Ao excluir, o sistema exige confirmação com os dados do lançamento (beneficiário, valor e data).
- **Lançamentos em Série (Parcelados / Recorrentes)**: Abre o diálogo de escopo para escolha entre excluir apenas o lançamento selecionado ou todos os futuros da série (lançamentos já conciliados nunca são excluídos).
- **Exclusão de Lançamentos em Lote (Por Período e/ou Conta)**:
  - Rotina acessível na barra lateral em **Ferramentas › Limpeza de Lançamentos em Lote**.
  - **Escopo Flexível de Contas**: Permite executar a limpeza em uma conta individual ou em todas as contas da base de dados simultaneamente.
  - **Escopo Flexível de Período**: Suporta remoção de "Todo o Histórico" ou de um "Período Específico" delimitado por Data Inicial e Data Final (com atalhos: Ano Atual, Ano Anterior, Mês Atual, Últimos 12M e Até Hoje).
  - **Preservação Estrita de Contas e Categorias**: Contas cadastradas, seus tipos, saldos iniciais de abertura (`opening`), categorias, subcategorias, regras de recorrência e limites de gastos planejados são **100% preservados**. Apenas as movimentações de lançamentos selecionadas são excluídas.
  - **Tratamento de Transferências Vinculadas**: Opção configurável para excluir automaticamente a contrapartida de transferências em outras contas (evitando lançamentos órfãos) ou desvincular a contrapartida mantendo-a avulsa.
  - **Aviso Obrigatório de Risco e Confirmação**: Apresenta painel visual de alerta de ação definitiva com contadores estatísticos em tempo real. Exige confirmação explícita via checkbox antes de liberar o botão de exclusão.
  - **Geração Compulsória de Arquivo de Backup**: Antes de efetivar qualquer remoção, o sistema obriga a exportação de uma cópia de segurança em `.zip`. Caso o usuário cancele o diálogo de backup, **a exclusão é abortada imediatamente**.
- **Categorias Sem Uso**: Categorias sem lançamentos vinculados exigem confirmação explícita antes de serem removidas.
- **Categorias Em Uso**: Categorias que possuam lançamentos vinculados não podem ser excluídas diretamente; o sistema exige a indicação de uma categoria de substituição para reclassificar os registros.

### 5. Hierarquia de Planejamento e Responsividade
- **Ordem Unificada do Módulo Planejamento**:
  1. **Fluxo de Caixa**
  2. **Relatórios**
  3. **Limite de Gastos**
  4. **Categorias**
- **Escala Visual Responsiva**: Telas com grandes matrizes de dados (como Fluxo de Caixa e Relatórios) adaptam proporcionalmente seus elementos para exibir todos os 12 meses simultaneamente sem cortes horizontais.
- **Ocultação do Menu Lateral**: Pressione `Cmd + B` (macOS) ou `Ctrl + B` (Windows) para recolher o menu lateral e maximizar a área de visualização.

### 6. Relatórios vs. Fluxo de Caixa (Tratamento de Transferências e Categorias)
- **Filtro Estrito nos Relatórios Mensais/Anuais de Receitas/Despesas**:
  - Transferências entre contas (`xfer != null` ou `peer != null`) e lançamentos de categorias com a opção "Considerar nos Relatórios" desmarcada **não aparecem nem são somados** nos totais de receitas e despesas da tela de Relatórios.
  - Cada categoria possui no seu cadastro/edição a opção configurável **"Considerar nos relatórios"** (`includeInReports`). Categorias fora dos relatórios recebem o badge visual `"OCULTA DE RELATÓRIOS"`.
  - **Filtro de Contas e Negócios nos Relatórios**: A tela de Relatórios conta com seletor de contas, permitindo escolher "Todas as Contas", selecionar múltiplas contas por checkbox ou filtrar por Negócio (ex.: **PF** ou **PJ**).
  - **Filtro de Status de Conciliação**: Permite isolar "Todos os Lançamentos", "Apenas Conciliados" (para auditoria estrita) ou "Apenas Pendentes" (para projeções). O filtro propaga para a impressão/exportação em PDF de 1 página e para o drill-down de categorias.
  - **Visão Anual Consolidada**: Suporte a relatórios consolidados do ano inteiro, com soma anual de cada categoria e cálculo anual da taxa de poupança (*Savings Rate*).
- **Preservação Integral do Fluxo de Caixa**:
  - Essa exclusão de relatórios **NÃO se aplica ao Fluxo de Caixa**. O motor do Fluxo de Caixa (`CashFlowEngine`) processa rigorosamente todas as contas, transferências e categorias para assegurar a exatidão matemática do saldo anterior, do resultado financeiro e do saldo final em caixa/bancos.

### 7. Performance com Grandes Volumes de Dados
- **Indexação em Memória $O(1)$**: Caches estruturados por conta e por mês.
- **Gravação Assíncrona Não-Bloqueante**: O salvamento da base JSON é executado com *debounce*, garantindo resposta instantânea mesmo em bases com mais de 30.000 lançamentos e arquivos de 5 MB+.

---

---

## 💎 Funcionalidades e Recursos Detalhados

### 1. Gestão de Contas e Livro-Caixa (Extrato Inteligente)
- **Múltiplos Tipos de Conta**:
  - `Corrente`: Movimentações do dia a dia, transferências e pagamentos.
  - `Poupança`: Reservas de liquidez e aplicações de curto prazo.
  - `Cartão de crédito`: Gestão de limites, datas de corte/vencimento e faturas.
  - `Investimento`: Ativos, renda fixa/variável e aportes de longo prazo.
  - `Dinheiro`: Carteira física e pequenos gastos em espécie.
- **Saldo Real vs. Saldo Previsto**:
  - **Saldo Real**: Apuração estrita das transações já efetivadas e conciliadas no extrato bancário.
  - **Saldo Previsto**: Projeção financeira incluindo despesas pendentes, agendamentos e parcelamentos futuros.
- **Agrupamento Cronológico Dia a Dia**:
  - Extrato separado por data e dia da semana (ex.: `27/10/2026 · Ter`).
  - **Saldo por Quebra de Dia**: Barra horizontal ao término de cada dia informando o saldo acumulado (real e previsto).
  - **Cabeçalho e Rodapé Consolidado**: Saldo Inicial (Real/Previsto), Total de Entradas (+), Total de Saídas (−) e Saldo Final.
- **Favorecido e Anotações em Duas Linhas**:
  - Linha 1: Favorecido/Descrição ampla e indicadores de parcelamento `(x/y)`.
  - Linha 2: Anotações (`memo`) e metadados com hierarquia visual subordinada, evitando corte de texto.
- **Conciliação Bancária em 1 Clique**:
  - Ícone circular interativo antes da data para alternar status entre pendente e conciliado (`rec`), atualizando instantaneamente a conta e o lançamento espelho caso seja transferência.
- **Organização e Governança de Contas**:
  - Agrupamento na barra lateral em **Favoritas**, **Contas Ativas** e **Contas Inativas**.
  - **Persistência de Expansão**: Estado recolhido/expandido mantido na sessão.
  - **Classificação por Negócio/Finalidade**: Campo opcional de negócio/empresa (`business`) com exibição discreta e elegante.
  - **Trava de Segurança Contábil**: Contas que possuem transações registradas **não podem ser excluídas**, prevenindo quebra de históricos. Podem ser desativadas/arquivadas com um clique. Apenas contas com exatamente zero lançamentos podem ser apagadas.

---

### 2. Gestão Avançada de Cartões de Crédito e Faturas
- **Ciclo Dinâmico de Fechamento e Vencimento**:
  - Configuração individual do dia de fechamento (`closeDay`), dia de vencimento (`dueDay`) e conta bancária padrão para débito da fatura (`pay`).
- **Alocação Inteligente de Fatura e Override Manual**:
  - Toda transação em cartão recebe uma chave de competência da fatura (`ik` no padrão `AAAA-MM`).
  - Compras efetuadas até o dia de corte entram na fatura corrente; compras após o fechamento entram na fatura seguinte.
  - O usuário possui total flexibilidade para sobrescrever manualmente a fatura vinculada caso o emissor processe em ciclo divergente.
- **Adiantamento e Pagamento Parcial de Fatura**:
  - Permite abater qualquer valor na fatura a qualquer momento através do modal de pagamento.
  - O motor de sincronização (`syncCards`) gera o agendamento de liquidação cobrando **estritamente o saldo remanescente**:
    $$\text{Saldo a Liquidar} = \max(0, \sum |\text{Despesas do Ciclo}| - \sum \text{Pagamentos})$$
  - Se quitada integralmente, o agendamento é removido e o cartão exibe o selo **LIQUIDADA** (verde).
- **Exportação de Fatura em PDF A4**:
  - Relatório impresso idêntico a um demonstrativo bancário: reúne todos os lançamentos que pertencem ao ciclo da fatura, independentemente do mês de calendário civil.

---

### 3. Central de Contas a Pagar e Receber (Vencimentos)
- **Visão Executiva de Prazos**:
  - Central consolidada acessível pela barra lateral (com badge numérico em tempo real), atalho de teclado ou menu.
- **Janela de Antecedência Configurável**:
  - Ajuste flexível do horizonte de monitoramento: 1, 2, **3 dias (padrão)**, 5, 7, 10, 15 ou 30 dias.
- **Classificação Visual de Urgência**:
  - 🔴 **ATRASADO**: Transações vencidas e ainda não conciliadas ($\Delta d < 0$).
  - 🟠 **HOJE**: Lançamentos que vencem na data corrente ($\Delta d = 0$).
  - 🔵 **EM X DIAS**: Lançamentos a vencer dentro da janela selecionada.
- **Ações Rápidas de Auditoria**:
  - Conciliação direta na listagem com 1 clique.
  - Conciliação em lote assistida.
  - Botão "Ver" com navegação imediata até a conta e realce pulsante no extrato.

---

### 4. Matriz de Fluxo de Caixa Multidimensional (Cash Flow)
- **Visualização Matricial Dinâmica**:
  - **Mensal**: 12 meses do ano (`Jan` a `Dez`) + Coluna de Total Consolidado do Ano.
  - **Trimestral**: 4 trimestres consolidados (`T1` a `T4`) + Total.
  - **Semestral**: 2 semestres consolidados (`S1` e `S2`) + Total.
  - **Anual**: Comparativo histórico de todos os anos da base.
- **Rigor Contábil e Regimes**:
  - Rendimentos Operacionais, Despesas Operacionais e Resultado Líquido.
  - **Saldo Anterior Acumulado**: Saldo real transitado de períodos anteriores.
  - **Saldo Final Acumulado**: Saldo consolidado em caixa e bancos no encerramento de cada coluna.
  - Suporte a alternância entre **Regime de Competência** (data da compra no cartão) e **Regime de Caixa** (data de liquidação da fatura).
  - Filtro por status: *Todos*, *Apenas Conciliados* ou *Não Conciliados*.
- **Exportação CSV Formatada**:
  - Codificação UTF-8 com BOM, delimitador `;`, valores decimais formatados em moeda brasileira (vírgula) para abertura direta no Microsoft Excel, Apple Numbers e Google Planilhas.

---

### 5. Relatórios Analíticos Mensais
- **Layout Executivo de Duas Colunas**:
  - Receitas alinhadas à esquerda e Despesas à direita, proporcionando comparação visual instantânea.
- **Isolamento Estrito de Transferências**:
  - Transferências entre contas e categorias marcadas como neutras (`includeInReports: false`) não contaminam nem inflam as receitas e despesas.
- **KPIs Estratégicos**:
  - Receitas Totais, Despesas Totais, Resultado Líquido do Mês e **Taxa de Poupança** (*Savings Rate* %).
- **Distribuição Percentual com Barras Visuais**:
  - Ranking de gastos por categoria com barras translúcidas Liquid Glass proporcionais.
- **Exportação em PDF Calibrada para 1 Página A4**:
  - Layout otimizado (595.28 x 841.89 pt) para consolidar todo o demonstrativo mensal em uma folha A4 perfeita para arquivo ou impressão.

---

### 6. Auditoria e Drill-Down Interativo de Categorias
- **Inspeção Instantânea**:
  - Clique em qualquer categoria na tela de Categorias ou nos Relatórios para abrir a modal de auditoria.
- **Busca e Filtros Dinâmicos**:
  - Filtragem por texto em tempo real (descrição, nota ou valor) e alternância rápida entre lançamentos do mês e histórico completo.
- **Ordenação Flexível**:
  - Classificação por Data, Nome/Favorecido ou Valor.
- **Edição e Exportação**:
  - Duplo clique no registro para edição instantânea.
  - Botão de exportação em CSV com diálogo nativo de salvamento.

---

### 7. Gestão de Categorias e Subcategorias
- **Hierarquia em Dois Níveis**:
  - Categorias Principais e Subcategorias unificadas pelo delimitador oficial ` › ` (ex.: `Alimentação › Supermercado`).
- **Importação e Exportação CSV Estruturada**:
  - Importador inteligente com detecção de delimitador (`;`, `,`, tab), suporte a separadores `›`, `>`, `/`, e criação automática de categorias-mãe.
- **Destaque Visual ao Passar o Mouse (*Hover Highlight*)**:
  - Feedback visual ergonômico idêntico ao extrato do livro-caixa: ao passar o mouse sobre qualquer linha de categoria ou subcategoria, a linha inteira recebe um fundo translúcido sutil (4% de opacidade) com cantos arredondados de 6px.
- **Proteção contra Lançamentos Órfãos**:
  - Categorias com transações vinculadas não podem ser excluídas sem que o usuário defina uma categoria de destino para transferir os registros.

---

### 8. Planejamento Financeiro: Limite de Gastos Mensal
- Definição de limites de gastos mensais por categoria.
- Totalizadores automáticos com acúmulo de subcategorias na categoria principal.
- Barras de progresso com gradiente de alerta visual conforme o consumo se aproxima ou ultrapassa o limite planejado.

---

### 9. Motor de Recorrências e Parcelamentos
- **Parcelamento Inteligente**:
  - Divisão exata em até 120 parcelas com tratamento de restos de centavos (`splitAmt`) e sufixo identificador `(x/y)`.
- **Projeção Adaptativa de Recorrências (`syncRecs`)**:
  - Suporta periodicidades: Diária, Semanal, Quinzenal, Mensal, Bimestral, Trimestral, Semestral e Anual.
  - Projeta automaticamente até **5 anos** para recorrências anuais (IPVA, IPTU, seguros) e **2 anos** para mensais.
  - Lançamentos recorrentes contínuos ou com data de término estipulada.
  - Transferências recorrentes espelhadas de forma atômica.
- **Ajuste Inteligente de Previsões**:
  - Lançamentos marcados como `Previsão ...` atuam como tetos orçamentários. O sistema deduz os gastos reais ocorridos ao longo do mês e exclui a previsão quando esgotada, evitando duplicidades contábeis.

---

### 10. Busca Global Multicritério
- Acesso rápido por atalho (`Cmd + Shift + F` no macOS ou `Ctrl + Shift + F` no Windows).
- Pesquisa simultânea em Favorecido, Categoria, Notas e Valor numérico.
- Clique em qualquer resultado para navegar diretamente ao extrato da conta, selecionando o mês correspondente com realce luminoso sobre a linha.

---

### 11. Central de Importação e Exportação (CSV e QIF Microsoft Money 99)
- **Compatibilidade QIF (Microsoft Money 99 / Quicken)**:
  - Decodificação universal com fallback para **Windows CP1252 / Latin-1**, preservando caracteres acentuados legados.
  - Reconhecimento automático de transferências `[NomeDaConta]` e criação automática das contas inexistentes.
- **Importador CSV Resiliente**:
  - Mapeamento flexível de colunas, múltiplos formatos de data e valores numéricos brasileiros ou internacionais.
  - Mapeamento de colunas de fatura/competência de cartão de crédito.
  - Filtro opcional contra duplicação de lançamentos por chave composta $O(1)$.
- **Exportação Completa da Base**:
  - Backup integral da base em JSON puro a qualquer momento.

---

### 12. Coletor Mobile Web / PWA (`coletor/` - ADR 008)
- Módulo PWA independente para registrar despesas e receitas rapidamente no smartphone (offline-first).
- **Acesso Oficial**: [https://fsf77.github.io/openmoney-new/coletor/](https://fsf77.github.io/openmoney-new/coletor/)
- **Automação via Atalhos do iOS (Apple Shortcuts)**:
  - Disparado automaticamente ao pagar por aproximação com Apple Pay ou receber notificações bancárias.
  - Suporte a parâmetros estruturados na URL: `?recibo=Data:DD/MM/AAAA;Conta:...;Favorecido:...;Valor:...;`
  - Atalho oficial disponível para download no iCloud diretamente na tela de Configurações (⚙️) do Coletor: [Baixar Atalho iOS](https://www.icloud.com/shortcuts/47a65df3d9c94513bba1af90b1a3ed4e).
- **Motor de Resolução de Contas em 4 Níveis (4-Tier Smart Account Resolution)**:
  1. *Nível 1 (Tabela De-Para / Apelidos)*: Mapeamento direto de nomes de cartões da carteira para contas do OpenMoney gerenciável em ⚙️ Configurações.
  2. *Nível 2 (Sinônimos Bancários & Token Scorer)*: Algoritmo heurístico financeiro que descarta ruídos (`Mastercard`, `Visa`, `Cartão`, `Crédito`) e reconhece sinônimos de marcas (`UV` $\leftrightarrow$ `Ultravioleta`, `Amex` $\leftrightarrow$ `American Express`, `Carbon` $\leftrightarrow$ `C6 Crédito`), com desempate de categorias (evita associar cartões Platinum a UV).
  3. *Nível 3 (Memória Habitual do Estabelecimento — `lastAcc`)*: Grava e reutiliza a última conta utilizada para aquele mesmo favorecido.
  4. *Nível 4 (Fallback)*: Conta favorita (★) ou primeira conta ativa.
- **Recursos Adicionais**:
  - Leitura de comprovantes com **IA Multimodal Google Gemini (BYOK - ADR 007)** diretamente pela câmera do celular.
  - Visualização de Contas e Saldos com contraste aprimorado (modo claro/escuro) e ordenação executiva (Favoritas e Ativas com saldo).
  - Inserção por comando de voz e autocompletar inteligente com última conta e categoria.
  - Exportação do lote em `openmoney_inbox.json` para importação e auditoria no desktop via Mobile Inbox.

---

### 13. Importação Inteligente de Comprovantes via OCR & IA Multimodal (`receipt_ocr_import_modal.dart`)
- **Varredura em Lote de Pastas**: Suporte a seleção de pastas contendo comprovantes em PDF, PNG, JPG, JPEG e HEIC.
- **OCR Nativo Local**:
  - **macOS**: Apple Vision Framework (`VNRecognizeTextRequest`) + `PDFKit`.
  - **Windows**: API nativa WinRT `Windows.Media.Ocr.OcrEngine` com suporte ao português (`pt-BR`).
- **Inteligência Artificial Multimodal (Google Gemini - Modelo BYOK)**:
  - Suporte ao Gemini Flash com chave própria gratuita do Google AI Studio.
  - Extração precisa de Favorecido/Loja (descartando marcas de maquininhas como Cielo/Rede/Stone/Laranjinha e rótulos fiscais).
  - Identificação do Valor Líquido Total Pago (descartando tributos da Lei 12.741 e parcelas individuais).
  - Sugestão automática de Conta e Categoria com base no histórico do usuário.
- **Conferência em Split View & Arquivamento**:
  - Painel lateral com lista de comprovantes e formulário de conferência em tempo real.
  - Movimentação automática e atômica dos arquivos conferidos para a subpasta `processados/`.

---

## ⌨️ Atalhos de Teclado Globais

| Atalho (macOS) | Atalho (Windows) | Ação Executada |
|---|---|---|
| `Cmd + Shift + F` | `Ctrl + Shift + F` | Abrir Pesquisa Global na base de dados |
| `Cmd + Option + I` | `Ctrl + Alt + I` | Abrir Central de Importação / Exportação CSV e QIF |
| `Cmd + O` | `Ctrl + O` | Gerenciador de Bases de Dados (.json) |
| `Cmd + Shift + B` | `Ctrl + Shift + B` | Histórico de Backups e Restauração |

---

## 🔄 Sistema de Atualização Automática (Auto-Update)

O OpenMoney inclui motor de auto-atualização integrado in-app ([`lib/services/update_service.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/services/update_service.dart)):
- **Feed Oficial**: Conecta-se a [https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json](https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json) com cabeçalhos anti-cache.
- **Verificação Automática e Manual**: Checagem silenciosa na inicialização e botão com ícone de nuvem na barra superior do aplicativo.
- **Instalação em 1 Clique**: Download com monitoramento de progresso percentual, verificação de integridade e substituição atômica dos binários.

---

## 🛠️ Scripts de Compilação e Publicação

Para desenvolvedores e mantenedores, o repositório inclui scripts prontos para geração de releases:

### 🍏 No macOS (`scripts/publish_release_macos.sh`)
Gera a compilação Release otimizada para macOS, compacta o arquivo `.zip`, calcula o hash SHA-256, atualiza o `version.json` e envia o commit e tag para o GitHub:

```bash
./scripts/publish_release_macos.sh "Notas de lançamento opcionais"
```

### 🪟 No Windows (`scripts/publish_release_windows.ps1` e `.bat`)
No ambiente Windows com Visual Studio e Flutter instalados:

```powershell
# Execução via PowerShell:
.\scripts\publish_release_windows.ps1 -CustomNotes "Notas de lançamento da versão"

# Ou via duplo-clique no arquivo batch:
scripts\publish_release_windows.bat
```

---

## 💻 Ambiente de Desenvolvimento

### Pré-requisitos
- **Flutter SDK 3.x+** ([flutter.dev](https://flutter.dev))
- **macOS**: Xcode com command line tools para compilação desktop macOS e iOS.
- **Windows**: Visual Studio 2022 com a carga de trabalho *Desenvolvimento para desktop com C++*.

### Comandos Rápidos

```bash
# Instalar dependências
flutter pub get

# Análise estática do código
flutter analyze

# Executar testes unitários
flutter test

# Executar nativamente no macOS
flutter run -d macos

# Executar nativamente no Windows
flutter run -d windows
```

---

## 📁 Estrutura do Código-Fonte (`lib/`)

```text
lib/
├── main.dart                             # Ponto de entrada, inicialização de janelas, tema e hotkeys
├── models/
│   └── openmoney_models.dart             # Modelos de dados (Schema v6), Contas, Faturas, Regras e Txs
├── store/
│   └── money_store.dart                  # Estado reativo principal, I/O atômico, backups e sincronização
├── services/
│   ├── cash_flow_engine.dart             # Motor de cálculo contábil do Fluxo de Caixa Matricial
│   ├── importers_exporters.dart          # Processadores de CSV, QIF (CP1252) e Categorias
│   ├── native_file_picker.dart           # Ponte para seletores de arquivo nativos (macOS / Windows)
│   ├── pdf_report_generator.dart         # Motor de diagramação e geração de relatórios PDF em A4
│   └── update_service.dart               # Motor de verificação e instalação de atualizações
└── ui/
    ├── app_shell.dart                    # Interface adaptativa desktop/tablet/mobile com sidebar
    ├── theme/
    │   └── liquid_glass.dart             # Design System Liquid Glass (cores, sombras e materiais)
    ├── modals/
    │   ├── account_modal.dart            # Criação, edição e configuração de contas e cartões
    │   ├── backups_history_modal.dart    # Histórico de backups automáticos em ZIP e restauração
    │   ├── batch_delete_modal.dart       # Exclusão em lote com backup preventivo compulsório
    │   ├── category_drill_down_modal.dart# Auditoria detalhada com busca e exportação CSV
    │   ├── csv_qif_modal.dart            # Central unificada de importação/exportação CSV e QIF
    │   ├── invoice_payment_modal.dart    # Adiantamento e quitação parcial de faturas de cartão
    │   ├── mobile_inbox_modal.dart       # Conferência e importação de registros do Coletor Mobile
    │   ├── transaction_edit_modal.dart   # Cadastro e edição detalhada de lançamentos
    │   └── welcome_database_modal.dart   # Painel de resgate e seleção segura de banco de dados
    └── views/
        ├── account_ledger_view.dart      # Livro-caixa com fechamento diário, inserção e faturas
        ├── budget_view.dart              # Orçamento mensal com metas visuais Liquid Glass
        ├── cash_flow_view.dart           # Matriz financeira multidimensional de fluxo de caixa
        ├── categories_view.dart          # Gerenciador de árvore de categorias e subcategorias
        ├── due_bills_view.dart           # Central executiva de contas a pagar e receber (vencimentos)
        ├── global_search_view.dart       # Busca global multicritério em toda a base
        └── reports_view.dart             # Relatório analítico mensal (Receitas à esq., Despesas à dir.)
```

---

## 🎨 Identidade Visual e Ícones

O projeto conta com ativos gráficos oficiais de alta definição:
- **macOS**: `macos/Runner/Assets.xcassets/AppIcon.appiconset/` e `AppIcon.icns` com resoluções de 16x16 até 1024x1024 Retina.
- **Windows**: `windows/runner/resources/app_icon.ico` com formato multi-resolução nativo Win32 (16, 32, 48, 64, 128 e 256 px).
- **iOS / iPadOS**: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` para iPhone, iPad e App Store.

---

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo [`LICENSE`](file:///Users/fabiano/Developer/OpenMoneyFlutter/LICENSE) para mais detalhes.

*OpenMoney é um projeto independente de código aberto, concebido por entusiastas de finanças pessoais. - FSF Consultoria*
