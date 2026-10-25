# Manual Completo de Engenharia, Regras de Negócio e Funcionalidades do OpenMoney

**Versão da Base:** v1.0.30  
**Plataformas Alvo:** Apple macOS 14+ (Sonoma, Sequoia) e Apple iOS / iPadOS 17+  
**Linguagem & Framework:** Swift 5.9+ / SwiftUI puro / AppKit & UIKit  
**Arquitetura:** Reativa Unidirecional baseada em `@MainActor public final class MoneyStore: ObservableObject`  
**Licença:** MIT (Código Aberto)

---

## 1. Visão Geral e Filosofia do Sistema

O **OpenMoney** é um sistema financeiro pessoal e patrimonial de alta precisão contábil, inspirado nos conceitos do clássico *Microsoft Money 99*, porém construído com a elegância do ecossistema Apple moderno.

### Princípios Fundamentais:
1. **Soberania Absoluta dos Dados**: Não existem servidores proprietários, cadastros obrigatórios, telemetria nem nuvens fechadas. A base de dados reside em um único arquivo estruturado e legível (`openmoney.json`), gravado de forma atômica no disco local ou em qualquer provedor em nuvem da preferência do usuário (iCloud Drive, Dropbox, Google Drive, OneDrive).
2. **Precisão Financeira em Centavos Inteiros (`Int`)**: Todas as quantias monetárias são modeladas internamente como inteiros representando centavos (`amt: Int`), eliminando categoricamente quaisquer erros de arredondamento de ponto flutuante binário (`Double`/`Float`).
3. **Desempenho Extremo ($O(1)$) com Mais de 30.000 Lançamentos**: O app utiliza cache e dicionários indexados em memória combinados com busca binária cronológica, persistência desacoplada da thread principal com *debounce* de 350ms, gravação atômica via arquivo temporário limpo e rotina de backups compactados em `.zip` com retenção mínima de 7 dias via `BackupManager`.
4. **Design System Liquid Glass**: Interface com efeitos de vidro fosco (`.ultraThinMaterial`), iluminação ambiente com gradientes nas bordas, cartões flutuantes para KPIs e suporte nativo a temas Claro e Escuro.

---

## 2. Modelagem de Dados e Estrutura dos Arquivos (`Models.swift`)

### 2.1 Tipos de Conta Suportados (`ACCOUNT_TYPES`)
- `"Corrente"`: Movimentação rotineira, transferências e pagamentos.
- `"Poupança"`: Reservas de liquidez e aplicações de curto prazo.
- `"Cartão de crédito"` (`CARD_TYPE`): Gestão de limites, ciclo de fechamento/vencimento e faturas.
- `"Investimento"`: Ativos financeiros, renda fixa/variável e aportes de longo prazo.
- `"Dinheiro"`: Carteira física e pequenos gastos em espécie.

### 2.2 Estruturas Centrais

#### `Account`
```swift
public struct Account: Codable, Identifiable, Equatable {
    public var id: String             // UID alfanumérico curto (7 chars)
    public var name: String           // Nome legível da conta
    public var type: String           // Um dos ACCOUNT_TYPES
    public var opening: Int           // Saldo inicial de abertura (em centavos)
    public var card: CardConfig?      // Parâmetros de fatura (se for cartão)
    public var invoices: [String: InvoiceInfo]? // Metadados e overrides de faturas
    public var inactive: Bool?        // Flag de desativação/arquivamento
    public var favorite: Bool?        // Flag para agrupar no topo da barra lateral
}
```

#### `CardConfig` & `InvoiceInfo`
- `closeDay: Int`: Dia do mês em que a fatura do cartão fecha (1 a 31).
- `dueDay: Int`: Dia do mês em que a fatura vence (1 a 31).
- `pay: String`: ID da conta padrão de onde o pagamento da fatura será debitado.
- `InvoiceInfo`: Registra as datas reais de fechamento (`close`), vencimento (`due`), conta de débito (`pay`) e se a data foi sobrescrita manualmente (`manual: Bool`).

#### `Transaction`
```swift
public struct Transaction: Codable, Identifiable, Equatable, Hashable {
    public var id: String             // Identificador único do lançamento
    public var acc: String            // ID da conta de vínculo
    public var peer: String?          // ID da conta contraparte (em transferências)
    public var date: String           // Formato ISO "YYYY-MM-DD"
    public var payee: String          // Favorecido / Descrição / Estabelecimento
    public var cat: String            // "Principal › Subcategoria" ou "Transferência: Conta"
    public var memo: String           // Observação / Nota / Tag de Previsão
    public var amt: Int               // Valor em centavos (Negativo: Débito/Despesa, Positivo: Crédito/Receita)
    public var rec: Bool              // Conciliado / Confirmado no extrato bancário
    public var xfer: String?          // UID compartilhado vinculando débitos e créditos espelhados
    public var auto: Bool?            // Identifica transações automáticas de liquidação de fatura
    public var card: String?          // ID do cartão gerador da fatura automática
    public var ik: String?            // Chave da fatura ("YYYY-MM") à qual o lançamento pertence
    public var inv: String?           // Referência do mês da fatura liquidada
    public var plan: String?          // UID da série de parcelamento
    public var pn: Int?               // Número da parcela atual (1..pt)
    public var pt: Int?               // Total de parcelas do plano
    public var recId: String?         // UID da regra de recorrência geradora
    public var recFreq: String?       // Frequência da regra ("daily", "weekly", "monthly", "yearly")
    public var recSeq: Int?           // Número sequencial da ocorrência
    public var createdAt: Double?     // Carimbo de data/hora (timestamp) para ordenação estável no mesmo dia
}
```

#### `RecurrenceRule`
Permite automatizar lançamentos e transferências contínuas ou com prazo determinado:
- `id`: UID da regra.
- `acc` e `peer`: Contas envolvidas (suporta transferências recorrentes).
- `start`: Data ISO inicial.
- `freq`: `"daily"`, `"weekly"`, `"monthly"` ou `"yearly"`.
- `amt`, `payee`, `cat`, `memo`.
- `nextSeq`: Próxima sequência a ser materializada (começa em 1).
- `end: String?`: Data limite de término opcional (se nula, a recorrência vigora por **tempo indeterminado**).

#### `CategoryItem`
- Estruturada em dois níveis: Categoria Pai (`parent == nil`) e Subcategoria (`parent == "NomeDoPai"`).
- Separador oficial: `SEP = " › "` (U+203A delimitado por espaços).
- `type`: `"Despesa"` ou `"Receita"`.
- `includeInReports: Bool?`: Controle se pontua ou não nos relatórios analíticos de receitas e despesas.

---

## 3. Regras de Negócio e Governança Financeira

### 3.1 Gestão e Integridade de Contas
1. **Bloqueio Físico contra Exclusão de Contas com Lançamentos**:
   - Para impedir a corrupção retroativa de históricos e balanços patrimoniais, qualquer conta que possua 1 ou mais lançamentos (`txCount > 0`) **não pode ser excluída**.
   - Ao tentar excluir, o sistema exibe um alerta modal explicando a impossibilidade e oferecendo a opção de **Desativar a Conta** com 1 clique.
2. **Desativação (Arquivamento)**:
   - Contas inativas são movidas para uma seção colapsável própria ("Contas Inativas") e identificadas com o badge `INATIVA` ou ícone de arquivo.
   - O histórico de movimentações, cálculos do fluxo de caixa e relatórios fiscais permanecem 100% preservados.
   - Contas desativadas não permitem a criação de novos lançamentos manuais nem de transferências.
3. **Exclusão Definitiva de Contas sem Uso**:
   - Apenas contas com **exatamente 0 lançamentos** podem ser excluídas definitivamente, mediante confirmação expressa do usuário.
4. **Favoritar Contas**:
   - No cadastro/edição, o usuário pode marcar "Favoritar conta". Contas favoritas são fixadas em um grupo dedicado no topo da barra lateral.

### 3.2 Cartão de Crédito e Ciclo de Faturas
1. **Determinação Padrão da Fatura (`invKeyFor`)**:
   - Composta pelo ano e mês da competência da fatura: `"YYYY-MM"`.
   - Se o dia do lançamento for menor ou igual ao dia de fechamento (`date.day <= card.closeDay`), a compra integra a fatura do próprio mês (`k`).
   - Se for posterior ao dia de fechamento (`date.day > card.closeDay`), a compra é alocada para a fatura do mês seguinte (`addMonthsYM(k, 1)`).
2. **Seleção Manual de Fatura (*Override*)**:
   - Tanto na barra de inserção rápida quanto no modal de edição (`TransactionEditSheet`), o usuário pode alterar a fatura vinculada (`tx.ik`), permitindo antecipar ou postergar compras que o emissor do cartão lançou em ciclo divergente.
3. **Pagamento Parcial e Adiantamento de Fatura (`InvoicePaymentSheet`)**:
   - O usuário pode pagar qualquer quantia (total ou parcial) em qualquer data.
   - É gerada uma transferência entre a conta corrente de débito e a conta do cartão com o valor pago associado à fatura (`ik`).
4. **Conciliação e Abatimento Automático no Vencimento (`syncCards`)**:
   - A rotina calcula dinamicamente: $\text{Charges} = \sum |\text{Despesas do ciclo}|$ e $\text{Payments} = \sum \text{Pagamentos parciais do ciclo}$.
   - Saldo devedor restante: $\text{Remaining} = \max(0, \text{Charges} - \text{Payments})$.
   - Se houver saldo a pagar ($\text{Remaining} > 0$), a transação automática de liquidação no vencimento cobra **apenas o valor remanescente**.
   - Se a fatura estiver quitada ($\text{Remaining} = 0$), a cobrança automática no vencimento é cancelada e o cabeçalho do cartão exibe o selo **LIQUIDADA** em verde esmeralda.

### 3.3 Mover Lançamentos entre Contas
- Ao alterar a conta de um lançamento em `TransactionEditSheet`:
  - Se a nova conta for um Cartão de Crédito, o sistema calcula e associa o `ik` correspondente da fatura.
  - Se mover de um cartão para uma conta bancária ou dinheiro, o vínculo da fatura é cancelado (`ik = nil`).
  - Se for uma transferência, o lançamento par da contraparte tem seu `peer` e sua descrição ("Transferência: [Conta]") atualizados de forma atômica.
  - Se o lançamento fizer parte de uma série (parcelado ou recorrente) e for editado com escopo `.forward`, todas as ocorrências futuras não conciliadas são transferidas para a nova conta.

### 3.4 Proteção e Escopo de Exclusão
- **Lançamentos Avulsos**: Exige diálogo nativo de confirmação contendo favorecido, valor e data.
- **Lançamentos em Série (Parcelamento / Recorrência)**:
  - Dispara o diálogo de escopo (`ScopeChoice`):
    - *Apenas este lançamento*.
    - *O selecionado e todos os futuros não conciliados*.
    - *Todos os lançamentos da série*.
  - **Garantia de Conciliação**: Transações que já foram conciliadas no banco (`rec == true`) **nunca são alteradas nem excluídas** em operações em série.
- **Exclusão de Lançamentos em Lote (`BatchDeleteTransactionsSheet`)**:
  - Permite limpar lançamentos por Conta (específica ou todas) e Período (Todo o Histórico ou Intervalo de Datas com atalhos: Ano Atual, Ano Anterior, Mês Atual, Últimos 12M e Até Hoje).
  - Preserva integralmente o cadastro das contas, saldos iniciais de abertura (`opening`), regras de recorrência e catálogo de categorias.
  - Permite escolher se as pernas espelhadas de transferências em outras contas devem ser excluídas em conjunto ou mantidas desvinculadas.
  - Exibe pré-visualização ao vivo (*live preview*) com contagem de lançamentos, total de receitas, total de despesas e saldo líquido impactado.
  - **Exigência Inviolável de Backup**: Antes de liberar a exclusão, o sistema obriga a exportação de um arquivo de backup em JSON via `NSSavePanel` (e grava cópia automática em disco). Se o usuário cancelar o backup, a operação é sumariamente abortada.

### 3.5 Ajuste Inteligente de Previsões Orçamentárias
- **Conceito**: Lançamentos com favorecido iniciado pela palavra `"Previsão"` (ex.: *Previsão Mercado*, *Previsão Combustível*) agem como reservas mensais de teto de gastos.
- Ao clicar em **"Ajustar Previsões"** (`store.adjustPredictions(for: month)`):
  - O motor analisa todas as contas ativas do mês.
  - Para cada categoria com previsão, totaliza os gastos reais realizados (excluindo outras previsões e transferências).
  - Deduz os gastos reais do teto da previsão. A base original de cálculo é gravada de forma transparente na nota da transação: `[Previsão base: R$ X,XX]`.
  - Essa memorização transparente impede dedução cumulativa ou duplicada em execuções repetidas no decorrer do mês.
  - Se os gastos atingirem ou superarem o teto previsto ($\text{Saldo Restante} \le 0$), a previsão temporária é **automaticamente excluída**, disparando um alerta modal de atenção: *"⚠️ PREVISÃO NÃO MAIS DISPONÍVEL (EXCLUÍDA)"*.

### 3.6 Projeção Temporal Adaptativa de Recorrências (`syncRecs`)
- **Frequência Anual (`yearly`)**: Projeta antecipadamente **5 anos (60 meses)**, viabilizando o planejamento plurianual de seguros, IPVA, IPTU e anuidades.
- **Frequência Mensal (`monthly`)**: Projeta antecipadamente **2 anos (24 meses)**.
- **Frequência Diária e Semanal (`daily` / `weekly`)**: Projeta antecipadamente **1 ano (12 meses)**.
- **Materialização sob Demanda**: Conforme o usuário navega para meses futuros no calendário, novas instâncias de regras contínuas são materializadas reativamente.
- **Transferências Recorrentes**: Gera simultaneamente o débito na conta de origem e o crédito na conta de destino vinculados pelo mesmo ID de série (`xrec:[regra]:[seq]`), com sincronização atômica em edições e exclusões.

### 3.7 Relatórios Analíticos vs. Fluxo de Caixa
- **Relatório Mensal de Despesas e Receitas (`ReportsView` / `iOSReportsTab`)**:
  - Filtra e **ignora estritamente transferências entre contas** e qualquer categoria configurada com `includeInReports == false` (como *"Transferencias (C)"* e *"Transferencias (D)"*).
  - Focado exclusivamente no consumo de renda e resultado operacional daquele mês.
- **Fluxo de Caixa Analítico (`CashFlowEngine`)**:
  - Consolida todas as contas e transações para garantir o rigor contábil.
  - Na visão de *Todas as Contas*, suprime transferências internas para não inflar receitas e despesas.
  - Na visão de *Conta Específica*, computa transferências sob a rubrica `Transferência`, discriminando a conta parceira.
  - Apura com exatidão matemática:
    - $\text{Saldo Anterior Acumulado} = \sum \text{Saldos Iniciais} + \sum \text{Movimentações Passadas}$.
    - $\text{Resultado Operacional} = \text{Rendimento} - \text{Despesas}$.
    - $\text{Saldo Final Acumulado} = \text{Saldo Anterior} + \text{Resultado}$.

---

## 4. Funcionalidades Detalhadas por Módulo

### 4.1 Livro-Caixa e Tabela de Movimentações (Extrato)
- **Barra de Inserção Rápida**: Campos com tipagem dinâmica, botão de alternância Débito/Crédito e menu de modalidade:
  - *Lançamento Único*.
  - *Parcelado*: até 120 parcelas com cálculo exato de centavos (`splitAmt`) e sufixo indicador `(x/y)`.
  - *Recorrente*: Diário, Semanal, Quinzenal, Mensal, Bimestral, Trimestral, Semestral ou Anual; Tempo Indeterminado ou Data de Término programada.
- **Autocompletar Preditivo de Favorecido**:
  - macOS: Menu popover flutuante com navegação por setas e seleção com `Enter`.
  - iOS: Carrossel horizontal de chips táteis.
  - Ao selecionar, define automaticamente a última categoria utilizada e o tipo (Despesa/Receita).
- **Agrupamento Cronológico Dia a Dia**:
  - Separadores de dia com dia da semana (ex: `23/10/2026 · Sex`).
  - Totalizadores de fechamento diário com Saldo Real e Saldo Previsto acumulados até aquele dia.
- **Ordenação Cronológica Intra-Dia Estável (`createdAt`)**:
  - Lançamentos ocorridos no mesmo dia possuem carimbo temporal de criação (`createdAt`).
  - Ao adicionar novos lançamentos para uma data existente, cada novo lançamento fica sempre posicionado na linha imediatamente abaixo dos anteriores, preservando a ordem cronológica de lançamento.
- **Colunas Redimensionáveis no macOS**: Divisores arrastáveis entre Data, Descrição, Categoria, Nota e Valor, com larguras persistidas na sessão.
- **Conciliação em 1 Clique**: Botão circular que alterna o estado de conciliação bancária (`rec`), sincronizando a contraparte de transferências.
- **Seletor Rápido de Ano/Mês (`MonthYearQuickPicker`)**:
  - Cabeçalho interativo que abre popover com stepper de anos, menu com anos existentes na base, matriz 4x3 dos 12 meses e botão "Mês Atual (Hoje)".

### 4.2 Pesquisa em Toda a Base de Dados (Busca Global)
- Acessível por `Cmd + Shift + F`, pela barra lateral (*Pesquisa Global*) ou pela aba dedicada *Buscar* no iOS.
- **Busca Multicritério em 4 Campos Simultâneos**:
  1. *Favorecido / Descrição*: Busca fonética e insensível a maiúsculas/acentos.
  2. *Categoria*: Busca por categoria principal ou subcategoria.
  3. *Nota / Memorando*: Procura em tags, anotações e códigos.
  4. *Valor*: Reconhecimento numérico inteligente (`150`, `150,00`, `150.00`, `1.500,00`, `R$ 89,90`).
- **Filtros Adicionais**: Filtro por conta (Todas ou específica) e por tipo (Todos, Receitas `+`, Despesas `−`).
- **Navegação Direta com Realce Luminoso**: Clicar em qualquer resultado abre a respectiva conta, posiciona o extrato no mês correto, rola até o lançamento e aplica uma borda pulsante de destaque visual temporário (4 segundos).

### 4.3 Gestão de Categorias e Subcategorias
- Organização em árvore de dois níveis: Categoria Principal e Subcategorias.
- **Prevenção contra Exclusão de Categorias em Uso**: Se a categoria tiver lançamentos vinculados, o app impede a exclusão direta e abre o modal `CategoryDeleteSheet` para reclassificar todos os lançamentos para uma categoria substituta.
- **Detalhamento de Lançamentos por Categoria (`CategoryTransactionsDetailSheet`)**:
  - Pílula com contagem e botão dedicado "Lançamentos" em cada categoria e subcategoria.
  - Abre grid estruturado com Conta, Data, Descrição, Categoria Completa, Nota e Valor colorido.
  - Permite busca textual interna, ordenação por qualquer coluna, duplo clique para editar o lançamento e botão de exportação em CSV do extrato daquela categoria.
- **Importação e Exportação Estruturada em CSV**:
  - Exporta: `"Tipo";"Categoria Principal";"Subcategoria";"Categoria Completa"`.
  - Importa: Detecção automática de delimitadores (`;`, `,`, tab), suporte a formatos combinados com separadores (`›`, `>`, `/`, `:`), criação automática da categoria-pai e prevenção contra duplicidades.

### 4.4 Planejamento Financeiro: Orçamento Mensal (Budget)
- Definição de limites mensais por categoria de despesa.
- Categorias principais agregam visualmente e computam a soma das metas e gastos de suas subcategorias.
- Barras de progresso em vidro líquido translúcido com gradientes azulados para limites normais e alertas visuais vermelhos para gastos excedentes.
- Totalizador consolidado no rodapé: Total Planejado vs. Total Realizado no mês.

### 4.5 Relatório de Fluxo de Caixa Matricial
- **Períodos Analíticos**:
  - *Mensal*: 12 meses do ano (`01/AAAA` a `12/AAAA`) + Total acumulado do ano.
  - *Trimestral*: 4 trimestres consolidados + Total.
  - *Semestral*: 2 semestres consolidados + Total.
  - *Anual*: Comparativo plurianual de todos os anos da base + Total histórico.
- **Filtros e Controles**:
  - Consolidação global (sem transferências internas) ou filtro por conta específica.
  - Filtro por status de conciliação: *Todos*, *Apenas Conciliados* (auditoria fiscal) ou *Apenas Não Conciliados* (projeções futuras).
  - Filtro por regime contábil: *Data do Lançamento* (competência) vs. *Data de Pagamento da Fatura* (caixa dos cartões de crédito).
  - Botões para Recolher/Expandir Tudo e busca rápida por categorias.
- **Responsividade**: Calibrado nativamente a 100% para monitores Full HD (1920x1080) e com escala visual proporcional contínua (até 60%) para janelas menores, garantindo que os 12 meses fiquem visíveis sem cortes horizontais.
- **Exportação CSV**: Codificado em UTF-8 com BOM, delimitador `;`, valores decimais em vírgula e metadados dos filtros ativos gravados no cabeçalho.

### 4.6 Relatório Mensal e Impressão/PDF em 1 Página A4
- **Cards de Métricas Executivas**: Receitas, Despesas, Saldo Líquido do Mês e **Taxa de Poupança** (*Savings Rate* %).
- **Drill-down Interativo por Categoria e Subcategoria**:
  - Clicar na linha de qualquer categoria ou subcategoria abre instantaneamente a janela de auditoria com os lançamentos correspondentes.
  - Abre pré-filtrado para o mês ativo (garantindo conciliação centavo a centavo com o relatório), com seletor rápido no topo para alternar entre o mês e o histórico completo.
- **Impressão e Exportação em PDF Calibrada para 1 Página A4 (`MonthlyReportPrintView` / `MonthlyReportPDFGenerator`)**:
  - Acessível por `Cmd + P`, menu Arquivo ou menu suspenso de ações.
  - Layout executivo profissional (595.28 x 841.89 pt): cabeçalho oficial com data/hora de emissão, cards de métricas, duas colunas balanceadas (Receitas à esquerda, Despesas à direita) com barras de progresso percentuais, condensação inteligente de subcategorias excedentes e rodapé de autenticação.
  - Suporte a impressão física, AirPrint e exportação direta de `.pdf` via `NSSavePanel` (macOS) ou `ShareLink` (iOS).

### 4.7 Central de Importação e Exportação (CSV e QIF — Microsoft Money 99)
- **Central de Importação/Exportação CSV (`CSVImportExportSheet`)**:
  - Atalho global `Cmd + Option + I`.
  - Opção de destino: Conta Fixa Selecionada ou *Automático (usar coluna 'Conta' do CSV)*.
  - **Auto-Criação e Inferência de Contas**: Varre previamente o arquivo e cria automaticamente no banco as contas inexistentes com base no nome (*"Cartão"*, *"Investimento"*, *"Poupança"*, *"Dinheiro"*, *"Corrente"*), ignorando cabeçalhos de coluna e evitando lançamentos órfãos.
  - **Flag de Controle de Duplicidade**:
    - *Desativada (Padrão de Segurança)*: Verificação instantânea $O(1)$ por chave composta (`conta|data|valor|favorecido`). Ignora registros idênticos já cadastrados.
    - *Ativada*: Permite carregar transações repetidas deliberadamente.
  - **Rastreabilidade de Fatura de Cartão de Crédito**:
    - *Exportação*: Inclui a 8ª coluna `"Fatura"` no CSV com a competência formatada em `MM/AAAA` (ex.: `10/2026`) para contas de cartão.
    - *Importação*: Mapeador inteligente que detecta aliases de fatura/competência (`fatura`, `invoice`, `competencia`, `ciclo`) e vincula a transação diretamente à respectiva fatura (`tx.ik`), com total compatibilidade com arquivos legados.
- **Importador QIF do Microsoft Money 99 e Quicken**:
  - Decodificação universal com suporte resiliente a **Windows CP1252 / Latin-1**, preservando acentuação gráfica brasileira clássica.
  - Identificação de transferências contidas no padrão `[NomeDaConta]`, pré-cadastrando as contas ausentes e estabelecendo vínculos bidirecionais espelhados.
  - Relatório pós-importação detalhado com contagem de lançamentos importados, duplicados ignorados, contas criadas e categorias cadastradas.

### 4.8 Sistema de Ajuda Nativo Sincronizado
- Atalho `Cmd + ?` ou menu de Ajuda do sistema.
- O motor `HelpManager` realiza a leitura em tempo de execução do próprio arquivo `README.md` (no disco de desenvolvimento, nos recursos do bundle ou no fallback compilado `EMBEDDED_README`).
- Permite recarregar o conteúdo dinamicamente sem reiniciar o app.
- Visualizador com índice lateral navegável, campo de busca instantânea e blocos de código com botão de cópia de 1 clique.

### 4.9 Atualização Automática pela Internet (macOS)
- **Canal de Distribuição**: Repositório público GitHub [`FSF77/openmoney-releases`](https://github.com/FSF77/openmoney-releases).
- **Verificação Sem Cache de CDN**: Consulta a API de commits do GitHub para capturar o SHA exato da branch `main`, impedindo que intermediários (Fastly/CDN) entreguem um feed `version.json` obsoleto.
- **Instalação Atômica e Reinicialização Silenciosa**:
  - Faz o download do pacote `.zip` com barra de progresso em tempo real.
  - Descompacta com `/usr/bin/ditto` e remove atributos de quarentena do Gatekeeper via `/usr/bin/xattr -cr`.
  - Dispara um script Bash em segundo plano (`nohup /tmp/openmoney_updater_[PID].sh &`), fecha o aplicativo atual, substitui o bundle em `/Applications/OpenMoney.app` e reabre o app atualizado automaticamente.
- **Comando de Instalação Rápida no Terminal**:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-releases/main/install.sh | bash
  ```

### 4.10 Ajuste Inteligente de Previsões com Liquid Glass (`PredictionsAdjustSummarySheet`)
- Substituição do antigo alerta modal estreito do sistema por um Sheet moderno e espaçoso com design Liquid Glass.
- Cards no topo com métricas executivas: Total Economizado/Abatido (`brl`), quantidade de previsões ajustadas, mantidas e esgotadas.
- Lista detalhada de previsões com decomposição da fórmula `Base Original − Gastos Reais = Novo Saldo` e badges coloridos de status (verde para ajustada, vermelho para esgotada e cinza para mantida).

### 4.11 Inicialização Segura e Histórico de Arquivos Recentes
- **Proteção contra Perda de Base (`MissingDatabaseSheet`)**: Se o arquivo da base de dados configurada não for localizado no disco ao iniciar o aplicativo, o OpenMoney não cria um banco em branco silenciosamente nem procura por arquivos arbitrários. Apresenta o painel de resgate com o caminho anterior e botões diretos para Localizar Arquivo, Escolher dos Recentes ou Criar Nova Base.
- **Menu Arquivo › Abrir Recente**: Lista os últimos 10 arquivos com indicação visual (`✓`) do arquivo ativo e suporte a Security-Scoped Bookmarks para volumes externos e nuvens.

### 4.12 Central de Contas a Pagar e Receber, Notificações Nativas e Conciliação (`DueBillsView` / `NotificationManager`)
- **Gestão Executiva de Vencimentos**:
  - Central consolidada acessível na barra lateral com badge numérico em tempo real, na barra de menus (`Cmd + Option + 5`), na aba *Vencimentos* do iOS e via banner inteligente translúcido no topo do extrato das contas.
  - **Parâmetro Configurável de Antecedência (Padrão: 3 dias)**:
    - Ajuste flexível da janela temporal de monitoramento: 1, 2, **3 dias (padrão oficial)**, 5, 7, 10, 15 ou 30 dias.
    - Persistência nativa em `UserDefaults` com recálculo imediato de contadores e notificações.
  - **Classificação Temporal por Urgência**:
    - **Atrasadas / Vencidas** ($\Delta d < 0$ e `rec == false`): badge vermelho de atenção prioritária `ATRASADO`.
    - **Vencendo Hoje** ($\Delta d == 0$ e `rec == false`): badge laranja `HOJE`.
    - **A Vencer em até N dias** ($1 \le \Delta d \le N$ e `rec == false`): badge azul `EM X DIAS`.
  - **Segregação Executiva entre Débitos e Créditos**:
    - Total de Contas a Pagar ($amt < 0$) e Contas a Receber ($amt > 0$) com cálculo do Saldo Líquido Projetado da janela temporal.
  - **Conciliação em 1 Clique e Auditoria em Lote**:
    - Alternância instantânea de conciliação bancária (`rec = true`) com atualização atômica das contas e espelhos de transferências.
    - Botão de auditoria e conciliação em lote com diálogo modal de confirmação.
    - Botão *"Ver"* com navegação assistida e realce luminoso temporário no extrato da conta.
- **Notificações Nativas do Sistema Operacional (macOS e iOS)**:
  - Integração 100% nativa e local via `UserNotifications.framework` (sem nuvem ou servidores externos).
  - Resumo diário matinal inteligente às 08:30 (anti-spam) agregando montantes e quantidades a liquidar.
  - Badge dinâmico no ícone do aplicativo no macOS Dock e na tela de início do iOS com atualização e remoção automática ao conciliar.
  - Botão *"Testar Notificação"* para concessão de permissão e teste local de som e banner.

---

## 5. Mapeamento de Atalhos de Teclado (macOS)

| Atalho | Ação do Sistema |
|---|---|
| `Cmd + N` | Criar Nova Base de Dados (`.json`) via `NSSavePanel` |
| `Cmd + O` | Abrir Base de Dados Existente via `NSOpenPanel` |
| `Cmd + Shift + M` | Mover Local da Base Ativa (Sincronizar em Nuvem) |
| `Cmd + Shift + F` | Abrir Pesquisa Global em Toda a Base de Dados |
| `Cmd + I` | Importar Lançamentos via Arquivo CSV |
| `Cmd + Option + I` | Abrir Central de Importação / Exportação CSV |
| `Cmd + Shift + Q` | Importar Arquivo QIF (Microsoft Money 99 / Quicken) |
| `Cmd + Shift + E` | Exportar Cópia de Segurança Completa em JSON |
| `Cmd + Option + 1` | Navegar para o Módulo de Fluxo de Caixa Analítico |
| `Cmd + Option + 2` | Navegar para o Módulo de Relatórios Mensais |
| `Cmd + Option + 3` | Navegar para o Módulo de Orçamento (Budget) |
| `Cmd + Option + 4` | Navegar para o Catálogo de Categorias e Subcategorias |
| `Cmd + Option + 5` | Navegar para Contas a Pagar e Receber (Lembretes & Conciliação) |
| `Cmd + P` | Imprimir / Gerar PDF do Relatório Mensal |
| `Cmd + ?` | Abrir Janela Nativa de Ajuda e Manual do Usuário |

---

## 6. Procedimentos de Build, Compilação e Distribuição

### 6.1 Compilação Nativa para macOS (Script Autônomo)
```bash
./build-app.sh
```
O script executa em sequência:
1. Sincroniza o `README.md` com `HelpContent.swift` e copia para os recursos do bundle.
2. Compila proceduralmente os ícones de alta resolução (`.icns` e `.png` 1024x1024) via `scripts/generate-icon.swift`.
3. Invoca o `swift build -c release --arch arm64` com otimizações de binário (`-O`).
4. Empacota o bundle `OpenMoney.app` na pasta `/tmp` e aplica assinatura de código *ad-hoc* (`codesign -s - --force --deep OpenMoney.app`), evitando contaminações de atributos estendidos do Finder/iCloud que invalidariam a execução.
5. Gera o pacote distributivo `dist/OpenMoney-<versao>.zip` e o manifesto `dist/version.json`.
6. Quando invocado com parâmetros de publicação (`./build-app.sh 1.0.24 "Notas da versão" --publish`), dispara `scripts/publish-release.sh`, enviando a release diretamente para o repositório público GitHub.

### 6.2 Compilação para iOS e iPadOS
```bash
./build-ios.sh
```
Oferece menu interativo:
1. Compilar para Simulador iOS (`build/ios/OpenMoney-Simulator.app`).
2. Compilar e empacotar pacote de dispositivo físico (`build/ios/OpenMoney.ipa`).
3. Instalação e execução direta no simulador aberto via `xcrun simctl install` e `xcrun simctl launch`.

### 6.3 Execução no Dispositivo Físico via Xcode
```bash
open OpenMoney.xcodeproj
```
Basta selecionar a conta Apple no menu *Signing & Capabilities* e executar (`Cmd + R`) no iPhone ou iPad conectado.
