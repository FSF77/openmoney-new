# OpenMoney (Multiplataforma: Windows, macOS, iPhone e iPad)

<p align="center">
  <strong>Aplicativo financeiro moderno, multiplataforma (Flutter / Dart) e open source para Windows, macOS, iOS (iPhone) e iPadOS (iPad), inspirado no clássico Microsoft Money 99.</strong>
</p>

---

## 🚀 Arquitetura Multiplataforma (Flutter 3.x)

Esta versão evolui o OpenMoney para uma base de código única em **Flutter (Dart)** com compilação nativa (**Windows x64/ARM64**, **macOS Universal**, **iOS** e **iPadOS**) e **100% de compatibilidade binária e estrutural** com o arquivo `openmoney.json` (`v: 6`) e arquivos `.csv` / `.qif`.

### Como Executar e Compilar

```bash
# 1. Instalar dependências
flutter pub get

# 2. Executar testes de paridade de regras de negócio e schema JSON v6
flutter test

# 3. Executar em modo desenvolvimento (macOS ou Windows)
flutter run -d macos
flutter run -d windows

# 4. Gerar builds nativos de produção
flutter build windows --release
flutter build macos --release
flutter build ipa --release
```

### Estrutura do Projeto (`lib/`)
- `lib/models/openmoney_models.dart`: Schema JSON v6 idêntico (`Database`, `Account`, `CardConfig`, `InvoiceInfo`, `CategoryItem`, `Transaction`, `RecurrenceRule`), centavos inteiros (`amt: int`) e helpers contábeis.
- `lib/store/money_store.dart`: Motor reativo (`MoneyStore`) com indexação em memória $O(1)$ para 30.000+ lançamentos, busca binária por mês, `syncRecs`, `syncCards`, `adjustPredictions`, gravação atômica (`.tmp` -> rename), backups diários e watcher de arquivo para **iCloud Drive** e **OneDrive**.
- `lib/services/cash_flow_engine.dart`: Motor matricial de Fluxo de Caixa (Mensal, Trimestral, Semestral, Anual) e exportação CSV.
- `lib/services/importers_exporters.dart`: Importadores e exportadores CSV e QIF (Microsoft Money 99 com fallback UTF-8 / Windows-1252).
- `lib/ui/`: Design System *Liquid Glass* multiplataforma, Shell adaptativo Desktop/Tablet/Mobile, Extrato de Contas, Fluxo de Caixa, Relatórios Analíticos com drill-down, Orçamento, Categorias, Vencimentos e Busca Global.

---

## 🌟 Visão Geral

O **OpenMoney** combina o poder de controle financeiro e o rigor contábil do clássico Microsoft Money 99 com as tecnologias mais modernas do ecossistema Apple (SwiftUI nativo). Seus dados pertencem exclusivamente a você: a base de dados é armazenada em um arquivo `openmoney.json` limpo e legível, sem dependência de servidores proprietários, cadastros externos ou telemetria.

### ✨ Principais Características

- **💎 Design System Liquid Glass**: Interface moderna com efeito de vidro fosco translúcido (*glassmorphism* nativo com `.ultraThinMaterial`), iluminação ambiente, gradientes especulares nas bordas e cartões flutuantes para saldos e métricas.
- **⚡ 100% Nativo & Ultrarrápido**: Desenvolvido em Swift + SwiftUI puro. O aplicativo compilado para macOS consome apenas ~2 MB em disco e inicia instantaneamente com mínimo uso de memória.
- **📱 Multiplataforma (macOS, iOS e iPadOS)**: Código compartilhado e interfaces adaptadas com ergonomia para Desktop e Mobile.
- **☁️ Sincronização Livre via Nuvem**: Escolha armazenar sua base no **iCloud Drive**, **Dropbox**, **Google Drive**, **OneDrive** ou localmente no Mac/iPhone.
- **🔔 Central de Contas a Pagar & Receber**: Monitoramento ativo de lançamentos pendentes de conciliação com lembretes automáticos por janela temporal de vencimento (padrão 3 dias), badges no Dock/ícone e notificações nativas do sistema.
- **📄 Impressão e Exportação em PDF A4 de Alta Fidelidade**: Emissão de Faturas de Cartão de Crédito e Extratos Mensais de Contas com layout otimizado, sem truncamento de textos, ícone de conciliação antes da data, notas em segunda linha, saldo acumulado por quebra de dia e valores em linha única.
- **📲 OpenMoney Coletor Mobile (PWA & Scanner OCR)**: Web App progressivo offline para iPhone/Android com reconhecimento ótico de recibos por câmera (OCR local em WebAssembly), autocompletar inteligente de favorecidos e exportação de lote temporário para importação no macOS sem risco de sobrescrita de base.
- **📊 Controle Financeiro Rigoroso**: Saldo Real vs. Previsto, conciliação de lançamentos, gestão de faturas de cartão de crédito com pagamento parcial/adiantamento, lançamentos recorrentes, parcelamentos inteligentes, orçamentos e relatórios analíticos detalhados.

---

## 📐 Regras de Negócio e Governança Financeira

Esta seção consolida as regras fundamentais que regem o cálculo, a integridade e a operação do OpenMoney:

### 1. Contas e Integridade Histórica
- **Impossibilidade de Exclusão de Contas com Lançamentos**: Para proteger a rastreabilidade patrimonial e os relatórios fiscais/contábeis, o OpenMoney **não permite a exclusão física** de contas que possuam lançamentos vinculados. Caso o usuário tente excluir uma conta com movimentações, o sistema bloqueia a operação, informa o total de lançamentos e sugere a desativação da conta com 1 clique.
- **Desativação (Arquivamento) de Contas**: Contas inativas mantêm todo o seu histórico intacto em relatórios, fluxos de caixa e evolução patrimonial, mas deixam de aceitar novos lançamentos ou transferências. Podem ser reativadas a qualquer momento.
- **Exclusão de Contas Sem Uso**: Somente contas com **0 lançamentos** podem ser excluídas definitivamente, mediante confirmação expressa do usuário.

### 2. Cartão de Crédito e Faturas
- **Ciclo de Fechamento e Vencimento**: Cada cartão de crédito possui configuração do dia de fechamento (`closeDay`), dia de vencimento (`dueDay`) e conta de débito padrão (`pay`).
- **Alocação Padrão por Data**: Despesas lançadas até o dia de fechamento integram a fatura do mês corrente (vencendo no mês seguinte). Despesas posteriores à data de fechamento entram na fatura seguinte.
- **Seleção Manual de Fatura (Override)**: Embora o sistema calcule a fatura padrão com base na data de fechamento, o usuário pode **escolher manualmente outra fatura** para qualquer lançamento (ex.: postergar ou antecipar uma compra de fechamento tardio). Essa opção está disponível tanto no macOS quanto no iOS/iPadOS, na barra de inserção e na edição do lançamento.
- **Pagamento Parcial e Adiantamento de Fatura**:
  - O usuário pode registrar pagamentos totais ou parciais em qualquer data antes ou depois do vencimento (ex.: fatura de R$ 1.000 em Outubro com vencimento em 05/11; pagamento de R$ 500 no dia 15/10).
  - **Abatimento Automático no Vencimento**: A rotina automática de conciliação de faturas (`syncCards`) monitora todos os pagamentos parciais e despesas vinculadas à chave da fatura (`ik`). No vencimento, o sistema gera o agendamento de cobrança cobrando **apenas o saldo remanescente**.
  - **Fatura Liquidada**: Se os pagamentos cobrirem 100% da fatura (saldo restante $\le 0$), a cobrança automática no vencimento é cancelada e a fatura recebe o status **LIQUIDADA**.

### 3. Edição, Cópia e Migração de Lançamentos entre Contas
- **Copiar Lançamento como Novo (`TransactionCopySheet`)**:
  - **Ícone e Acesso**: Botão dedicado de cópia com ícone Apple SF Symbol `doc.on.doc` posicionado ao lado dos botões de Editar (`pencil`) e Excluir (`trash`) em cada linha de lançamento no macOS, nas ações de deslizar a linha (`swipeActions`) e no menu de contexto (botão direito) no macOS e iOS.
  - **Dados Pré-preenchidos**: Traz preenchidos automaticamente a descrição (com remoção inteligente de sufixos de parcelas anteriores `(x/y)`), a categoria ou transferência correspondente, a nota/observação e o valor original.
  - **Data Atual Automática**: O campo de data é inicializado por padrão com a **data atual (hoje)**, permitindo alteração rápida via seletor de data caso desejado.
  - **Flexibilidade Total de Conta e Fatura**: Permite selecionar qualquer conta ativa do sistema. Ao selecionar uma conta de cartão de crédito, o sistema calcula e associa automaticamente a fatura correspondente ao período da data selecionada.
  - **Definição de Repetição (Novo Lançamento Completo)**: Permite escolher livremente se a nova movimentação será um lançamento **Único**, **Recorrente** (com periodicidade diária, semanal, mensal ou anual, com ou sem data de término) ou **Parcelado** (de 2x a 120x).
  - **Integridade do Registro Original**: Executa `store.addTransaction(...)`, gerando identificadores e séries 100% novas, sem alterar em nada o lançamento de origem.
  - **Regra de Exceção para Faturas Automáticas**: Lançamentos automáticos gerados pelo sistema para fechamento/pagamento de faturas de cartão (`tx.auto == true`) não exibem a opção de copiar.
- **Mover Lançamento de Conta**: Na tela de edição de lançamentos (`TransactionEditSheet`), é possível alterar a conta do lançamento (`selectedAccId`).
- **Adequação Automática de Cartão de Crédito**:
  - Ao mover uma compra para um cartão de crédito, o sistema calcula e associa a chave da fatura correspondente (`ik`), permitindo ajuste manual.
  - Ao mover de um cartão para uma conta corrente ou dinheiro, a associação de fatura é removida (`ik = nil`).
- **Séries Recorrentes e Parceladas**: Caso o lançamento faça parte de um parcelamento ou recorrência e a edição seja aplicada para lançamentos futuros (`scope == .forward`), todas as parcelas futuras não conciliadas são transferidas para a nova conta de destino.
- **Transferências**: Ao mover uma perna de uma transferência para outra conta, a contraparte par da transferência tem sua referência (`peer`) e sua descrição atualizadas de forma atômica e consistente.

### 4. Confirmações de Exclusão (Prevenção de Perda Acidental)
- **Lançamentos Avulsos**: Ao clicar na lixeira (macOS) ou deslizar para excluir (iOS), o sistema exige confirmação com os dados do lançamento (beneficiário, valor e data).
- **Lançamentos em Série (Parcelados / Recorrentes)**: Abre o diálogo de escopo para escolha entre excluir apenas o lançamento selecionado ou todos os futuros da série (lançamentos já conciliados nunca são excluídos).
- **Exclusão de Lançamentos em Lote (Por Período e/ou Conta)**:
  - Rotina acessível diretamente na barra de menus do macOS em **Lançamentos › Excluir Lançamentos em Lote...** e **Arquivo › Excluir Lançamentos por Período / Conta...** (e na aba Base no iOS).
  - **Escopo Flexível de Contas**: Permite executar a limpeza em uma conta individual ou em todas as contas da base de dados simultaneamente.
  - **Escopo Flexível de Período**: Suporta remoção de "Todo o Histórico" ou de um "Período Específico" delimitado por Data Inicial e Data Final (com botões de atalho: Ano Atual, Ano Anterior, Mês Atual, Últimos 12M e Até Hoje).
  - **Preservação Estrita de Contas e Categorias**: Contas cadastradas, seus tipos, saldos iniciais de abertura (`opening`), categorias, subcategorias, regras de recorrência e orçamentos planejados são **100% preservados**. Apenas as movimentações de lançamentos selecionadas são excluídas.
  - **Tratamento de Transferências Vinculadas**: Opção configurável para excluir automaticamente a contrapartida de transferências em outras contas (evitando lançamentos órfãos) ou desvincular a contrapartida mantendo-a avulsa.
  - **Aviso Obrigatório de Risco e Confirmação**: Apresenta painel visual de alerta de ação definitiva, com resumo estatístico ao vivo (*live preview* de quantidade de lançamentos, receitas, despesas, saldo líquido e contas impactadas). Exige confirmação explícita via checkbox antes de liberar o botão de exclusão.
  - **Geração Compulsória de Arquivo de Backup**: Antes de efetivar qualquer remoção, o sistema obriga a exportação de uma cópia de segurança em `.zip` através do `NSSavePanel` (e grava cópia de contingência compactada com carimbo de data/hora em `~/Library/Application Support/OpenMoney/Backups/`). Caso o usuário cancele o diálogo de backup, **a exclusão é abortada imediatamente**.
  - **Recálculo Atômico dos Módulos**: Após a exclusão, as faturas de cartão de crédito (`syncCards`), índices em memória ($O(1)$) e relatórios são recalculados instantaneamente.
- **Categorias Sem Uso**: Categorias sem lançamentos vinculados exigem confirmação explícita antes de serem removidas.
- **Categorias Em Uso**: Categorias que possuam lançamentos vinculados não podem ser excluídas diretamente; o sistema exige a indicação de uma categoria de substituição para reclassificar os registros.

### 5. Hierarquia de Planejamento e Responsividade
- **Ordem Unificada do Módulo Planejamento**: Em ambas as plataformas (macOS e iOS), a ordem oficial é:
  1. **Fluxo de Caixa**
  2. **Relatórios**
  3. **Orçamento**
  4. **Categorias**
- **Menu da Barra Superior (macOS)**: O módulo Planejamento conta com menu dedicado na barra de menus do macOS (`CommandMenu("Planejamento")`), com atalhos diretos (`Cmd + Option + 1` para Fluxo de Caixa, `Cmd + Option + 2` para Relatórios, `Cmd + Option + 3` para Orçamento, `Cmd + Option + 4` para Categorias e `Cmd + Shift + F` para Pesquisar em Toda a Base).
- **Escala Visual Responsiva**: Telas com grandes matrizes de dados (como Fluxo de Caixa e Orçamento Anual) são calibradas para exibição nítida a 100% em resoluções Full HD (1920x1080) e, em telas ou janelas menores, adaptam sua escala visual proporcionalmente (escala adaptativa até 60%) para exibir todos os 12 meses simultaneamente sem cortes horizontais.

### 6. Relatórios vs. Fluxo de Caixa (Tratamento de Transferências e Categorias)
- **Filtro Estrito nos Relatórios Mensais de Receitas/Despesas**:
  - Transferências entre contas (`xfer != nil` ou `peer != nil`) e lançamentos de categorias com a opção "Considerar nos Relatórios" desmarcada (incluindo categorias padrão de transferência como `"Transferencias (C)"` e `"Transferencias (D)"`) **não aparecem nem são somados** nos totais de receitas e despesas da tela de Relatórios (`ReportsView` no macOS e `iOSReportsTab` no iOS).
  - Cada categoria possui no seu cadastro/edição a opção configurável **"Considerar nos relatórios"** (`includeInReports`). Categorias fora dos relatórios recebem o badge visual `"Fora dos Relatórios"`.
- **Preservação Integral do Fluxo de Caixa**:
  - Essa exclusão de relatórios **NÃO se aplica ao Fluxo de Caixa**. O motor do Fluxo de Caixa (`CashFlowEngine`) processa rigorosamente todas as contas, transferências e categorias para assegurar a exatidão matemática do saldo anterior, do resultado financeiro e do saldo final em caixa/bancos.

### 7. Performance com Grandes Volumes de Dados
- **Indexação em Memória $O(1)$**: Caches estruturados por conta e por mês (`cachedTxsByAccount`, `cachedMonthData`).
- **Gravação Assíncrona Não-Bloqueante**: O salvamento da base JSON é executado em thread secundária com *debounce*, garantindo resposta instantânea mesmo em bases com mais de 30.000 lançamentos e arquivos de 5 MB+.

### 8. Importação Segura: Pré-Verificação e Criação Automática de Contas
- **Verificação Prévia de Contas (Prevenção de Importação Incorreta)**: Antes de processar e inserir qualquer transação na base a partir de arquivos CSV ou QIF, a rotina de importação escaneia e valida previamente todas as contas mencionadas no arquivo.
- **Resolução Automática da Coluna "Conta" no CSV**:
  - Na Central de Importação CSV, ao selecionar *"Automático (usar coluna 'Conta' do CSV)"*, o sistema analisa a coluna correspondente de cada linha e vincula o lançamento diretamente à respectiva conta (ex: *Nubank*, *Banco Inter*, *Itaú*).
  - **Filtro Estrito contra Cabeçalhos**: O sistema ignora automaticamente textos que correspondam ao cabeçalho da coluna (como `"Conta"`, `"Account"`, `"Nome da Conta"`, etc.), garantindo que o nome da coluna do arquivo nunca seja criado ou associado como uma conta real.
  - **Registro Efetivo no Banco de Dados**: Novas contas encontradas no CSV são adicionadas formalmente à base de dados (`db.accounts`), aparecendo de imediato na barra lateral e eliminando contas órfãs.
- **Criação Antecipada de Contas Inexistentes**: Caso uma ou mais contas citadas no arquivo não estejam previamente cadastradas no banco de dados, o sistema cria automaticamente as contas antes de vincular os lançamentos, evitando categoricamente que transações sejam alocadas na conta errada ou fiquem órfãs com identificadores inválidos.
- **Inferência Inteligente do Tipo de Conta**: O tipo da nova conta criada é inferido dinamicamente pelo nome contido no arquivo:
  - Nomes contendo termos como *"Cartão"*, *"Card"* ou *"Crédito"* recebem o tipo `Cartão de crédito`.
  - Termos como *"Poupança"* ou *"Savings"* recebem o tipo `Poupança`.
  - Termos como *"Investimento"* ou *"Invest"* recebem o tipo `Investimento`.
  - Termos como *"Dinheiro"* ou *"Cash"* recebem o tipo `Dinheiro`.
  - Demais contas recebem o tipo padrão `Corrente`.
- **Garantia de Integridade em Bases Limpas**: Ao importar um arquivo sem coluna de contas em uma base de dados que ainda não possua nenhuma conta cadastrada, o sistema cria antecipadamente uma conta padrão (*"Conta Corrente"*), garantindo que todos os lançamentos tenham uma conta válida associada.
- **Vínculo Correto de Transferências no QIF**: Em arquivos QIF com marcação de transferência entre contas (`[NomeDaConta]`), o sistema pré-cadastra a conta de contraparte se ela ainda não existir, preservando o relacionamento bidirecional da transferência em vez de convertê-la incorretamente em categoria avulsa.

### 9. Ajuste Automático de Previsões Orçamentárias Temporárias
- **Conceito de Previsão Temporária**: Lançamentos iniciados com o prefixo `Previsão` (ex.: *Previsão Posto*, *Previsão Mercado*, *Previsão Farmácia*) funcionam como reservas prévias de teto de gastos no mês.
- **Abrangência Global Multiconta**: Ao acionar o botão **"Ajustar Previsões"**, o sistema avalia as previsões do mês selecionado em todas as contas cadastradas.
- **Apuração por Categoria em Todas as Contas**: Para cada categoria com previsão, o sistema consolida todos os gastos já realizados no mês em **todas as contas** ativas (excluindo outras previsões e transferências).
- **Abatimento Determinístico sem Dedução Duplicada**: O valor gasto é subtraído do teto da previsão. A base original é memorizada de forma transparente na nota (`[Previsão base: R$ X,XX]`), permitindo acionar o botão quantas vezes for necessário ao longo do mês à medida que novas compras entrarem, recalculando sempre a partir do teto inicial sem duplicar reduções.
- **Exclusão Automática de Previsão Esgotada**: Se as despesas da categoria atingirem ou superarem o teto previsto (saldo remanescente $\le 0$), a previsão temporária é excluída automaticamente e um aviso destacado alerta que o saldo daquela previsão foi integralmente consumido.
- **Painel Resumo Visual com Design Liquid Glass (`PredictionsAdjustSummarySheet`)**: Em substituição aos antigos alertas estreitos do sistema operacional, o OpenMoney apresenta um modal translúcido com cards de resumo (total economizado/abatido, quantidade de previsões ajustadas, mantidas e esgotadas), decomposição visual da conta (`Base − Gastos = Saldo`) e badges de status semânticos (verde para ajustadas, vermelho para esgotadas e cinza para mantidas).

### 10. Governança, Integridade e Política de Retenção de Backups
- **Eliminação Definitiva do `.bak` Não-Versionado**: O antigo arquivo `openmoney.json.bak` mantido solto na pasta da base foi descontinuado. Por ser sobrescrito cegamente a cada *debounce* de 350ms, ele oferecia falsa sensação de segurança, não guardava histórico temporal e poluía pastas sincronizadas (iCloud Drive, Dropbox, Google Drive, OneDrive).
- **Snapshot Diário Automático em `.zip`**: Ao abrir o aplicativo ou no primeiro salvamento do dia, o motor `BackupManager` gera uma cópia completa dos dados compactada em formato `.zip` universal (`openmoney-backup-YYYY-MM-DD.zip`), gerando uma redução de ~85% a 90% no tamanho em disco.
- **Janela de Retenção Mínima de 7 Dias**: O sistema mantém o histórico diário de pelo menos 7 dias corridos. Cópias mais antigas que 7 dias são expurgadas automaticamente (`pruneBackups`).
- **Salvaguarda de Quantidade Mínima de Snapshots**: Para proteger usuários que utilizam o app em intervalos esporádicos (ex.: uma vez por semana ou a cada quinzena), a rotina de limpeza **nunca apaga backups se houver 7 ou menos arquivos na pasta**, assegurando a existência permanente de no mínimo 7 pontos de restauração no tempo.
- **Isolamento de Diretório**: Todos os backups automáticos e programados residem na pasta dedicada do aplicativo (`~/Library/Application Support/OpenMoney/Backups/`), mantendo a pasta da base de trabalho limpa e livre de ruídos.
- **Restauração Universal Transparente**: O sistema aceita indistintamente tanto arquivos `.zip` quanto `.json` antigos. Ao restaurar um `.zip`, o arquivo é descompactado e validado em memória antes de substituir a base ativa.

### 11. Ordenação Cronológica Intra-Dia Estável
- **Preservação da Ordem de Inserção no Mesmo Dia**: Lançamentos ocorridos no mesmo dia possuem carimbo temporal de criação (`createdAt`).
- **Novo Lançamento na Linha Abaixo**: Ao inserir uma nova movimentação para uma data onde já existem lançamentos, ela é posicionada na linha imediatamente inferior, eliminando saltos aleatórios de posição provocados por hashes de identificador.
- **Retrocompatibilidade com Bases Legadas**: Lançamentos legados sem `createdAt` recebem automaticamente carimbo sequencial estável na rotina de migração.

### 12. Inicialização Segura contra Perda de Base (Arquivo Não Localizado)
- **Eliminação de Abertura Silenciosa ou Equivalente Arbitrária**: Caso o arquivo configurado não seja localizado no caminho registrado ao abrir o app (ex.: pendrive desconectado, volume de rede indisponível ou arquivo renomeado), o aplicativo **não cria um banco vazio silenciosamente nem procura por arquivos equivalentes arbitrários**.
- **Painel de Resgate e Escolha Explícita (`MissingDatabaseSheet`)**: Apresenta tela informativa com o caminho anterior e oferece botões rápidos para "Localizar Arquivo...", "Escolher dos Recentes..." ou "Criar Nova Base...".

### 13. Menu Arquivo: Lista dos Últimos Arquivos Abertos ("Abrir Recente")
- **Histórico de Bases Recentes**: O menu **Arquivo › Abrir Recente** mantém registro dos últimos 10 arquivos abertos com indicação visual (`✓`) da base atualmente ativa.
- **Segurança de Acesso no macOS**: Utiliza Security-Scoped Bookmarks para assegurar permissão persistente de leitura/escrita em diretórios externos e nuvens.
- **Comando de Limpeza**: Opção para limpar o histórico do menu e do sistema operacional com 1 clique.

### 14. Lembretes de Vencimento, Notificações Nativas e Conciliação (Contas a Pagar & Receber)
- **Central Executiva de Vencimentos (`DueBillsView` / `iOSDueBillsTab`)**:
  - Nova tela dedicada com design Liquid Glass acessível diretamente pelo menu lateral do macOS (com badge de pendências dinâmico), na aba *Vencimentos* do iOS, pelo menu **Planejamento › Contas a Pagar e Receber...** (`Cmd + Option + 5`) ou através do banner inteligente de lembrete dentro dos extratos.
  - **Parâmetro Configurável de Antecedência (Padrão: 3 dias)**:
    - O usuário pode configurar a janela temporal de alerta: **1 dia**, **2 dias**, **3 dias (padrão oficial)**, **5 dias**, **7 dias**, **10 dias**, **15 dias** ou **30 dias**.
    - O valor é persistido nas preferências do sistema (`UserDefaults`), aplicando-se imediatamente aos filtros, contadores da barra lateral, badges de ícone e agendamento de notificações.
  - **Classificação Temporal por Urgência**:
    - **Atrasadas / Vencidas** ($\Delta d < 0$ e `rec == false`): badge vermelho de alta prioridade `ATRASADO` informando a quantidade de dias decorridos.
    - **Vencendo Hoje** ($\Delta d == 0$ e `rec == false`): badge laranja de ação prioritária `HOJE`.
    - **A Vencer em até N dias** ($1 \le \Delta d \le N$ e `rec == false`): badge azul `EM X DIAS` para provisionamento de saldo.
  - **Segregação Executiva entre Débitos e Créditos**:
    - **Contas a Pagar** ($amt < 0$): Total consolidado em centavos e contagem exata de compromissos a liquidar.
    - **Contas a Receber** ($amt > 0$): Total consolidado em centavos e contagem de créditos pendentes de compensação.
    - **Saldo Projetado Líquido**: Resultado líquido previsto ($\sum Receitas - \sum Despesas$) na janela temporal ativa.
  - **Barra de Controles & Filtros Otimizada**:
    - Rótulos desacoplados (`Exibir:`, `Tipo:` e `Conta:`) com layout horizontal protegido contra quebra de texto, permitindo alternar rapidamente entre *Todas as Pendências*, *Atrasadas*, *Vencendo Hoje* e a *Janela Ativa*, além de filtrar por conta bancária específica.
  - **Coluna de Data sem Quebra de Linha**:
    - Largura dimensionada para `135pt` mantendo a data (`DD/MM/AAAA`) e o dia da semana (`· qui`) em linha única e legibilidade máxima.
  - **Conciliação em 1 Clique e Auditoria em Lote**:
    - Botão circular de conciliação integrado em cada linha. Clicar alterna o status de conciliação bancária (`rec = true`), sincronizando a perna espelhada se for transferência e removendo o item da lista de pendências com animação suave.
    - Botão *"Conciliar Todas da Janela"* com confirmação de segurança para conciliação em lote.
  - **Navegação com Foco no Registro**:
    - Botão *"Ver"* em cada linha que direciona diretamente para o extrato da conta, ajusta o mês correspondente, rola até o lançamento e aplica o realce luminoso temporário.
- **Notificações Nativas do Sistema Operacional (macOS e iOS)**:
  - **100% Local, Offline e Soberano**: Implementado via `UserNotifications.framework` da Apple (`NotificationManager.swift`), sem telemetria, conexões externas nem dependência de servidores na nuvem.
  - **Resumo Inteligente Diário Matinal (Anti-Spam)**:
    - Agendamento diário automático às 08:30 da manhã consolidando compromissos que vencem na janela (ex.: *"Você tem 2 contas a pagar (R$ 450,00) e 1 a receber (R$ 1.200,00) nos próximos 3 dias"*).
  - **Badge Dinâmico no Ícone do App / Dock**:
    - No macOS: Exibe a quantidade de lançamentos pendentes no Dock (`NSApplication.shared.dockTile.badgeLabel`).
    - No iOS: Atualiza o badge numérico na tela de início (`UNUserNotificationCenter.setBadgeCount`).
    - Ao conciliar todos os compromissos da janela, o badge é removido automaticamente.
  - **Botão de Teste Imediato**:
    - Botão *"Testar Notificação"* na barra de controles que solicita autorização do sistema se ainda não concedida e emite um alerta sonoro e visual de teste em 1.5s.
- **Banner Inteligente de Lembrete no Extrato da Conta**:
  - Ao entrar em qualquer conta corrente ou cartão com compromissos pendentes de conciliação vencendo na janela ativa, um banner translúcido em vidro líquido surge logo acima da tabela com resumo financeiro e atalho direto *"Ver e Conciliar"*.

### 15. Exportação e Importação CSV com Rastreabilidade de Fatura de Cartão
- **Coluna "Fatura" no CSV**: A exportação padrão passa a incluir a 8ª coluna `"Fatura"` (`"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura"`).
- **Formatação de Fatura**: Para cartões de crédito, exporta a competência no formato amigável `MM/AAAA` (ex.: `10/2026`).
- **Mapeamento Flexível na Importação**: Reconhece automaticamente cabeçalhos de fatura (`fatura`, `invoice`, `competencia`, `ciclo`) e vincula os lançamentos à chave correta (`tx.ik`), preservando o histórico de compras de cartão com total compatibilidade retroativa para arquivos antigos.

### 16. Impressão e Exportação em PDF A4 de Fatura de Cartão de Crédito e Extrato Mensal da Conta
- **Fatura de Cartão de Crédito em PDF (`CardInvoicePrintPageView` / `CardInvoicePDFGenerator`)**:
  - **Finalidade e Ergonomia**: Criado para facilitar a conferência minuciosa e a conciliação linha a linha entre os lançamentos registrados no OpenMoney e a fatura bancária emitida pela administradora do cartão.
  - **Acesso no Cabeçalho e Telas**: Disponível no cabeçalho dos lançamentos da conta de cartão através do botão dedicado `[Fatura PDF ▾]` (ao lado de *"Pagar Restante / Parcial..."*), na tela de pagamento de fatura (`InvoicePaymentSheet`) e no menu de ações no iOS.
  - **Abrangência por Fatura**: Filtra e consolida todos os lançamentos que pertencem ao ciclo da fatura em aberto/selecionada (`ik == chave` ou data pertencente ao ciclo de fechamento `closeDay`), independentemente da data de calendário do lançamento (ex.: compras efetuadas em outubro que vencem na fatura de novembro).
  - **Cabeçalho Executivo Completo**: Nome da conta de cartão de crédito, competência da fatura (ex.: *Outubro de 2026*), dia/data exata de fechamento (`closeDate`), data de vencimento (`dueDate`), conta vinculada para débito automático/pagamento (`payAccountName`), carimbo temporal de emissão (*Emitido em DD/MM/AAAA às HH:mm*) e numeração de páginas (*Página X de Y*).
  - **Cards KPI de Resumo Financeiro**:
    - **Total Compras / Encargos**: Somatório das compras e despesas do ciclo em centavos.
    - **Pagamentos / Créditos**: Somatório de todos os pagamentos e adiantamentos realizados para a fatura.
    - **Saldo a Pagar**: Saldo remanescente exato em aberto (em vermelho se pendente ou verde se zerado).
    - **Situação da Fatura**: Indicador semântico de status (*LIQUIDADA*, *PAGO PARCIAL* ou *EM ABERTO*).
  - **Tabela Analítica Otimizada (Layout Amplo e Sem Cortes)**:
    - **Ícone de Conciliação Antes da Data**: Posicionado na primeira coluna (`✓` ou `—`) com largura de 20pt, sem poluição de rótulos de texto no cabeçalho. O cabeçalho exibe apenas o ícone `✓`, maximizando a largura disponível para os dados.
    - **Data em Linha Única**: Coluna com largura fixa de 58pt no padrão `DD/MM/AAAA`.
    - **Descrição com Segunda Linha para Notas/Observações**: Coluna ampla de 270pt para Favorecido e Parcelas `(x/y)`. Quando o lançamento possui observação (`memo`), ela é exibida em uma segunda linha subordinada (tamanho 7.2pt em cinza secundário) logo abaixo da descrição, eliminando colunas extras e garantindo espaço integral para o nome da despesa sem qualquer corte de texto.
    - **Categoria Ampla**: Coluna generosa de 115pt sem truncamento de categorias ou subcategorias.
    - **Valor Sem "R$" e em Linha Única**: Coluna de 87pt alinhada à direita exibindo apenas o valor numérico formatado (`1.250,00` ou `+ 1.250,00`), eliminando quebras de linha indesejadas e garantindo legibilidade imediata com precisão contábil.
  - **Barra de Fechamento**: Resumo no rodapé com contagem total de lançamentos, total de despesas, créditos e saldo a pagar.
- **Extrato Mensal da Conta em PDF (`AccountStatementPrintPageView` / `AccountStatementPDFGenerator`)**:
  - **Finalidade e Abrangência**: Atende a todas as demais contas do sistema (Conta Corrente, Poupança, Investimentos, Dinheiro em Carteira, etc.).
  - **Acesso no Cabeçalho e Menus**: Botão dedicado `[Extrato PDF ▾]` ao lado de `[CSV / QIF ▾]` no cabeçalho da conta no macOS, itens correspondentes dentro do menu de exportação e menu de impressão/compartilhamento na barra superior do iOS.
  - **Governança de Saldos Obrigatória**:
    - **Saldo Inicial Real (`openingReal`)**: Posição consolidada de abertura do mês com lançamentos já compensados.
    - **Saldo Inicial Previsto (`openingPred`)**: Posição projetada de abertura considerando compromissos agendados.
    - **Total de Entradas (`+`)**: Somatório de todas as receitas, créditos e transferências recebidas no mês.
    - **Total de Saídas (`−`)**: Somatório de todas as despesas, débitos e transferências enviadas no mês.
    - **Saldo Final Real**: Posição líquida real de encerramento do mês.
    - **Saldo Final Previsto**: Posição projetada de encerramento considerando todos os compromissos do mês.
  - **Saldo Acumulado por Quebra Diária em Uma Linha**:
    - Elimina a coluna lateral de saldo acumulado que comprimia as demais colunas horizontalmente.
    - As transações fluem organizadas por dia com as colunas otimizadas (`[✓] | DATA | DESCRIÇÃO (com nota na 2ª linha) | CATEGORIA | VALOR`).
    - Ao final de cada dia com movimentações, uma barra horizontal de quebra diária exibe o **Saldo Real do dia** (e o **Previsto**, caso divirja do real), mantendo o extrato limpo, arejado e fácil de auditar contra o extrato do banco.
  - **Barra de Fechamento**: Consolidação com total de movimentações, total de créditos, total de débitos, resultado líquido do mês e saldo final real.
- **Mecanismo de Geração Vetorial e Paginação Inteligente**:
  - **Suporte Multi-Páginas Sem Cortes**: Utiliza particionamento automático de lançamentos em blocos (`chunkList`), dimensionando a primeira página com cabeçalho expandido e KPIs (até 18-20 itens) e páginas subsequentes com mini-cabeçalho compacto (até 26 itens), garantindo aproveitamento estético de 100% da folha A4 padrão sem estouros de margem ou quebras de valor.
  - **Impressão Nativa**: Integração com `NSPrintOperation` e `PDFDocument` no macOS com suporte a diálogo padrão de impressão, impressoras físicas, AirPrint e spool do sistema, e `UIPrintInteractionController` no iOS.
  - **Exportação Direta em Arquivo PDF**: Gravação de arquivo `.pdf` vetorial limpo com `NSSavePanel` no macOS e `ShareLink` com `PDFExportItem` (`Transferable`) no iOS.

### 17. OpenMoney Coletor Mobile (PWA), Reconhecimento Ótico (OCR) e Importação Segura
- **Arquitetura Desacoplada de Entrada Rápida ("Append-Only Inbox")**:
  - Para eliminar riscos de sobrescrita acidental ou arquivos duplicados com sufixo ` 2.json` no iCloud Drive pelo Safari mobile, o OpenMoney adota uma arquitetura em duas pontas:
    1. **No Celular (Coletor PWA)**: Opera offline e focado exclusivamente na coleta ágil de novos gastos e compras do dia a dia.
    2. **No Desktop (macOS)**: Centraliza a base de dados definitiva (`openmoney.json`), importando os novos registros de forma cumulativa e atômica.
- **Extração Leve de Estrutura Inicial (One-Time Setup)**:
  - Ao vincular o arquivo `openmoney.json` no celular, o Coletor extrai apenas a estrutura essencial (~20 KB): nomes e tipos de contas ativas, saldos de referência conciliados, categorias/subcategorias e até 1.000 favorecidos mais frequentes com suas respectivas categorias históricas.
- **Cálculo Rigoroso de Saldo Real Conciliado**:
  - Os saldos exibidos no carrossel de contas do Coletor consideram estritamente transações marcadas como conciliadas (`rec == true`), eliminando distorções de lançamentos futuros ou agendamentos não compensados.
- **Autocompletar Inteligente de Favorecidos com Classificação Automática**:
  - Ao digitar as primeiras 2 letras no campo Favorecido, o sistema consulta a base em memória com normalização semântica (insensível a acentos e maiúsculas/minúsculas).
  - Cada sugestão exibe uma pílula com a última categoria associada.
  - Ao selecionar a sugestão, o formulário é preenchido de imediato, selecionando automaticamente o tipo (**Despesa** ou **Receita**) e a respectiva **Categoria**, exatamente como no macOS e iOS.
- **Hierarquia Completa de Categorias (Seleção de Categorias Principais)**:
  - O seletor de categorias permite a escolha de categorias principais (`📁 Alimentação (Principal)`) mesmo quando elas possuem subcategorias filhas cadastradas (`↳ Supermercado`, `↳ Restaurante`), assegurando flexibilidade máxima de classificação.
- **Reconhecimento Ótico de Caracteres por Câmera (OCR Local Privativo)**:
  - Permite fotografar ou carregar uma imagem de comprovante/cupom fiscal da galeria.
  - O processamento de imagem e o reconhecimento ótico (OCR) rodam 100% no navegador via WebAssembly (Tesseract.js), sem envio de dados ou fotos para nenhum servidor de terceiros.
  - Extrai automaticamente: **Estabelecimento/Favorecido**, **Data** da compra e **Valor Total**.
  - Abre o formulário pré-preenchido para conferência rápida pelo usuário.
- **Exportação Limpa em Arquivo Único (`openmoney_inbox.json`)**:
  - Exporta apenas os novos lançamentos pendentes em formato JSON compacto (~1 a 2 KB).
  - Imagens capturadas via câmera são descartadas do arquivo exportado para garantir tráfego leve e rapidez instantânea.
  - Compatível com a API de compartilhamento do iOS (Web Share API com arquivo único, prevenindo arquivos residuais como `texto.txt`).
- **Importação Nativa no macOS com Janela de Revisão Visual (`Cmd + Option + M`)**:
  - Disponível no menu **Importar > Lançamentos do Celular (openmoney_inbox.json)...** com o atalho oficial **`Cmd + Option + M`** (mantendo `Cmd + Shift + M` reservado para Mover Base).
  - **Prevenção Rigorosa de Duplicidades**: Transações já existentes na base são detectadas por assinatura única (conta, data, favorecido, valor e categoria) e identificador, sendo ignoradas automaticamente para evitar lançamentos repetidos.
  - **Associação Automática de Cartão de Crédito**: Para contas do tipo cartão de crédito, o sistema calcula dinamicamente a competência da fatura (`ik`) com base na data do lançamento e no fechamento do cartão.
  - **Auto-Cadastro de Categorias Inéditas**: Novas categorias utilizadas no celular são registradas automaticamente na árvore de categorias da base.
  - **Janela Modal de Revisão (`MobileInboxImportSummarySheet`)**: Exibe painel detalhado em Liquid Glass com contagem de importações, total de despesas, total de receitas, duplicados ignorados e a lista linha a linha de cada item adicionado com data, conta, favorecido, categoria e valor formatado.

---

## 🚀 Como Rodar e Compilar

### 1. Compilação Nativa macOS (Script Automático)

Para compilar o aplicativo diretamente do terminal sem necessidade de abrir o Xcode:

```bash
# 1. Torne o script executável (caso necessário)
chmod +x ./build-app.sh

# 2. Compile e gere o bundle nativo OpenMoney.app
./build-app.sh

# 3. Abra o aplicativo gerado
open OpenMoney.app
```

O script `./build-app.sh`:
- Gera automaticamente os ícones de alta resolução em formatos `.icns` e `.png` (1024x1024).
- Compila de forma otimizada (`-O`) visando arquitetura Apple Silicon (`arm64`) nativa.
- Gera o bundle `OpenMoney.app` assinado *ad-hoc* pronto para execução (compilação e assinatura são feitas em `/tmp` para evitar atributos do Finder/iCloud que invalidam a assinatura).
- Gera o pacote de distribuição `dist/OpenMoney-<versão>.zip` e o feed `dist/version.json`.
- Aceita parâmetros: `./build-app.sh [VERSÃO] ["Notas"] [--publish]`. Com `--publish`, envia a nova versão ao repositório público de releases (veja a seção *Atualização Automática pela Internet*).

### 2. Compilação para iOS / iPadOS (Script Automático)

Para gerar os pacotes do app para iOS (Simulador ou Dispositivo / `.ipa`):

```bash
./build-ios.sh
```

O script oferece 3 opções:
1. **Simulador iOS**: Gera `build/ios/OpenMoney-Simulator.app` (basta arrastar para a janela do simulador para instalar).
2. **Dispositivo iOS (.ipa)**: Compila o binário `arm64` nativo e empacota em `build/ios/OpenMoney.ipa` e `OpenMoney-Device.app`.
3. **Instalação Direta**: Compila e instala diretamente no simulador que estiver aberto no momento.

### 3. Abrir e Rodar no iPhone Físico via Xcode (macOS / iOS / iPadOS)

Para instalar diretamente no seu iPhone conectado ao Mac:

```bash
open OpenMoney.xcodeproj
```

1. No topo do Xcode, escolha o target **OpenMoney** e selecione o seu **iPhone** (ou um Simulador).
2. Na aba **Signing & Capabilities**, selecione a sua conta Apple (*Team*).
3. Pressione **Cmd + R** (ou o botão Play ▶) para compilar e instalar no iPhone.

---

## 📋 Funcionalidades Implementadas

### 1. Gestão Completa de Contas e Patrimônio Global
- **Múltiplos Tipos de Conta Suportados**:
  - **Corrente**: Movimentação bancária diária, transferências e pagamentos.
  - **Poupança**: Contas de reserva e rendimento básico.
  - **Investimento**: Aplicações de renda fixa/variável e patrimônio investido.
  - **Dinheiro**: Controle de carteira, pequenos gastos em espécie e caixinha.
  - **Cartão de Crédito**: Gestão de limite, fechamento, vencimento e faturas.
- **Saldos em Tempo Real (Real vs. Previsto)**:
  - **Saldo Real**: Apuração estrita das transações já conciliadas no extrato.
  - **Saldo Previsto**: Projeção com lançamentos pendentes e parcelas futuras do mês selecionado.
  - **Patrimônio Consolidado no Rodapé**: Indicador permanente na barra lateral do patrimônio real e projetado de todas as contas ativas.
- **Arquivamento e Desativação Segura de Contas**:
  - Desativação de contas inativas com 1 clique (mantendo o histórico completo em relatórios e auditorias).
  - Bloqueio rígido de novos lançamentos em contas inativas, com banner informativo e botão de reativação imediata.
  - Separação visual com seções dedicadas: **Contas Ativas** e **Contas Inativas** (com contadores e badge `INATIVA`).
  - **Contas Favoritas**: toggle "Favoritar conta" no cadastro; as favoritas aparecem em um grupo próprio **Favoritas** no topo da barra lateral, seguido de **Contas Ativas** e **Contas Inativas**.
  - **Grupos recolhíveis**: clique no título de cada grupo para recolher/expandir (útil com muitas contas inativas). O estado é gravado e restaurado ao reabrir o app.
  - O botão **+ Nova conta** fica no final da lista, abaixo das contas inativas.
- **Proteção Contra Exclusão Acidental**:
  - Bloqueio total de exclusão para contas que contenham lançamentos, sugerindo a desativação da conta.
  - Exclusão permitida apenas para contas sem lançamentos (0 registros), com alerta de confirmação definitiva.
- **Reordenação Personalizada**:
  - **macOS**: Arraste e solte (*drag & drop*) ou menu de contexto com atalhos "Mover para cima" / "Mover para baixo".
  - **iOS**: Ações contextuais táteis de reordenação. A sequência é salva de forma persistente no arquivo JSON.

### 2. Gestão Avançada de Cartões de Crédito e Faturas
- **Ciclo Completo de Fechamento e Vencimento**: Configuração individual de dia de fechamento (`closeDay`), dia de vencimento (`dueDay`) e conta para débito automático (`pay`).
- **Painel de Status da Fatura do Mês**:
  - Exibição destacada em Liquid Glass no cabeçalho da conta com:
    - **Total da Fatura** (soma de despesas alocadas).
    - **Já Pago** (adiantamentos e pagamentos parciais realizados).
    - **Saldo a Pagar** / Status **LIQUIDADA** (verde esmeralda).
    - Datas exatas de fechamento, vencimento e conta de débito vinculada.
- **Botão "Pagar / Adiantar..." (`InvoicePaymentSheet`)**:
  - Interface dedicada no macOS e iOS para efetuar pagamentos integrais ou adiantamentos parciais em qualquer data.
  - Atalho instantâneo **"Preencher Saldo Restante"**.
  - Seleção da conta de débito e data do pagamento.
- **Abatimento Automático no Vencimento**:
  - Caso o usuário efetue um pagamento parcial antecipado, a transação automática gerada no vencimento cobra **estritamente o saldo remanescente**.
  - Caso a fatura seja quitada integralmente com antecedência, o lançamento automático no vencimento é cancelado e removido.
- **Seleção Manual de Fatura (Override)**:
  - Seletor de fatura presente tanto na barra rápida de inserção quanto na edição do lançamento.
  - Permite alocar compras para faturas anteriores ou futuras (com indicação da fatura padrão calculada pelo fechamento).
- **Identificação Visual**: Tag roxa com o mês da fatura (`Fatura Mês/Ano`) em cada linha de lançamento de cartão no macOS e iOS.

### 3. Livro-Caixa e Tabela de Lançamentos Inteligente
- **Autocompletar Preditivo de Beneficiário com Classificação Automática**:
  - Ao digitar os primeiros caracteres do beneficiário, o OpenMoney busca no histórico e exibe sugestões contextuais.
  - **Classificação Imediata**: Ao selecionar a sugestão (via clique, toque ou tecla `Enter`), o sistema preenche automaticamente a **última categoria** e o **tipo** (Despesa/Receita) utilizados para aquele beneficiário.
  - **macOS**: Sugestões flutuantes integradas à barra de inserção com navegação por teclado.
  - **iOS**: Carrossel horizontal de chips de sugestão tátil logo abaixo do campo.
- **Mover Lançamento de Conta**:
  - Na tela de edição de lançamentos (`TransactionEditSheet`), é possível selecionar uma nova conta de destino.
  - Conversão inteligente de faturas de cartão e propagação atômica para séries recorrentes, parcelamentos futuros e transferências.
- **Agrupamento Cronológico Dia a Dia**:
  - Extrato agrupado por data com indicação do dia da semana (ex: `15/10/2026 · Qui`).
  - Fechamento diário com indicação do saldo real e previsto acumulado ao final de cada dia.
- **Colunas Redimensionáveis no macOS**: Divisores arrastáveis entre as colunas (**Data**, **Descrição/Beneficiário**, **Categoria**, **Nota** e **Valor**) com salvamento do layout.
- **Conciliação Bancária Interativa**: Botão circular de conciliação com estilo Liquid Glass para alternar entre pendente e conciliado com 1 clique/toque.
- **Ações Rápidas em Cada Linha (Editar, Copiar e Excluir)**:
  - Botão de **Editar** (`pencil`): abre o modal de alteração do registro e escopo de séries.
  - Botão de **Copiar** (`doc.on.doc`): duplica o lançamento abrindo a tela de cópia com data atual, campos pré-preenchidos e liberdade para trocar conta, valor e modo (recorrente/parcelado).
  - Botão de **Excluir** (`trash`): remove o lançamento mediante confirmação de segurança.
- **Confirmação Nativa de Exclusão**: Diálogo de segurança exibindo descrição, valor e data antes de excluir lançamentos avulsos.
- **Busca e Filtro em Tempo Real**: Barra de busca instantânea filtrando por beneficiário, categoria ou anotações na velocidade da digitação no mês corrente.
- **Navegação Rápida entre Meses e Seletor Direto de Ano/Mês (`MonthYearQuickPicker`)**:
  - Além da navegação sequencial com setas (`‹` e `›`), o cabeçalho do mês é interativo (`calendar` + `chevron.down`).
  - Permite abrir popover com controle de anos (stepper `‹ Ano ›`, menu com anos existentes na base de dados) e grade com os 12 meses (Jan a Dez).
  - Salto imediato de múltiplos anos ou meses com 1 clique (ex: voltar de 2026 para 2020), além de botão de retorno rápido para o mês atual (*Hoje*).
- **Rodapé Mensal Flutuante**: Indicadores de total de receitas, despesas e saldo líquido do mês selecionado.
- **Rotina de Exclusão de Lançamentos em Lote (Barra de Menus macOS e Base iOS)**:
  - Menu **Lançamentos › Excluir Lançamentos em Lote...** e Menu **Arquivo › Excluir Lançamentos por Período / Conta...**.
  - Permite expurgar movimentações de uma conta específica ou de todas as contas simultaneamente.
  - Suporta seleção entre "Todo o Histórico" ou intervalo personalizado com data inicial e final (com atalhos: Ano Atual, Ano Anterior, Mês Atual, Últimos 12M e Até Hoje).
  - Preserva estritamente as contas, seus saldos de abertura e todas as categorias e subcategorias cadastradas.
  - Alerta de risco em tempo real com estatísticas de impacto financeiro (*live preview*) e confirmação obrigatória.
  - **Backup Prévio Obrigatório**: Exportação compulsória de arquivo JSON da base completa via `NSSavePanel` antes de efetuar a exclusão (se cancelado o backup, a exclusão é abortada).
  - Recálculo dinâmico automático de conciliações e faturas de cartão de crédito (`syncCards`).
- **Ajuste Inteligente de Previsões Orçamentárias ("Ajustar Previsões")**:
  - **Botão na Barra do Mês (macOS e iOS)**: Localizado estrategicamente ao lado do filtro e da busca rápida no cabeçalho do mês.
  - **Identificação Automática**: Localiza instantaneamente todos os lançamentos do mês cuja descrição comece com `Previsão` (ex: `Previsão Posto`, `Previsão Mercado`), sem distinção de maiúsculas/minúsculas e acentos.
  - **Apuração Global de Gastos da Categoria**: Varre todas as contas ativas no mês e calcula o total dos gastos efetivamente realizados na mesma categoria (desconsiderando transferências e outras previsões).
  - **Abatimento Proporcional Inteligente**: Reduz o valor da previsão com base nos gastos reais da categoria. A base original é gravada de forma transparente na nota (`[Previsão base: R$ X,XX]`), garantindo que execuções sucessivas não causem deduções repetidas.
  - **Exclusão de Previsão Esgotada**: Caso as despesas da categoria alcancem ou superem o valor previsto (saldo restante $\le 0$), o lançamento temporário de previsão é **excluído automaticamente**, emitindo aviso em destaque: *"Não há mais previsão disponível"*.
  - **Relatório de Ajuste Instantâneo**: Exibe modal/alerta com o resumo categorizado das previsões ajustadas, previsões esgotadas/excluídas e previsões que permaneceram em dia.

### 4. Pesquisa em Toda a Base de Dados (Busca Global)
- **Consulta Global Unificada em Todas as Contas e Períodos**:
  - Acessível pela barra lateral (*Pesquisa Global*), pelo atalho de teclado `Cmd + Shift + F`, pelo menu *Lançamentos*, pelo botão na barra de navegação de lançamentos no macOS ou pela aba dedicada **Buscar** no iOS.
  - **Busca Multicritério com Suporte a 4 Campos Principais**:
    - **Descrição / Favorecido**: Busca flexível por nome ou partes do beneficiário.
    - **Categoria**: Busca por termos da categoria principal ou subcategoria hierárquica.
    - **Nota / Observação**: Busca por anotações e memorandos (ex.: `IPVA 2024`, `Reembolso`, `Nota Fiscal`).
    - **Valor**: Reconhecimento inteligente de valores com ou sem centavos, decimais com vírgula ou ponto (ex.: `150`, `150,00`, `150.00`, `1.500,00`, `R$ 89,90`).
  - **Exibição Estruturada em Linhas**: Tabela completa exibindo **Data**, **Conta**, **Descrição / Favorecido** (com badges de recorrência `⟳` e parcelamento `x/y`), **Categoria**, **Nota / Observação** e **Valor** formatado com cor correspondente.
  - **Filtros Rápidos Complementares**: Filtro por conta (Todas ou conta específica) e por tipo de lançamento (Todos, Receitas `+`, Despesas `−`).
  - **Navegação Direta ao Registro com Destaque Visual**:
    - Ao clicar em qualquer linha da busca, o sistema abre a conta de destino, define o mês correspondente da data do lançamento, rola a tela até a posição exata da movimentação e a destaca com iluminação e borda de ênfase visual.

### 5. Lançamentos Recorrentes e Parcelados Inteligentes
- **Recorrência Flexível (Tempo Indeterminado ou Data de Término)**:
  - Frequências: **Diário**, **Semanal**, **Quinzenal**, **Mensal**, **Bimestral**, **Trimestral**, **Semestral** e **Anual**.
  - **Tempo Indeterminado (sem fim)**: O lançamento se renova continuamente sem interrupção.
  - **Data de Término Programada**: Opção de definir uma data final limite (`end`), cessando automaticamente a geração de novos lançamentos a partir daquela data.
  - **Horizonte Adaptativo de Projeção**:
    - **Anual**: Projeção antecipada de **5 anos (60 meses)**, viabilizando planejamento plurianual de seguros, IPVA, IPTU e anuidades.
    - **Semestral**: Projeção antecipada de **4 anos (48 meses)**.
    - **Trimestral**: Projeção antecipada de **3 anos (36 meses)**.
    - **Bimestral e Mensal**: Projeção antecipada de **2 anos (24 meses)**.
    - **Diário, Semanal e Quinzenal**: Projeção de **1 ano (12 meses)** com consumo otimizado de armazenamento.
  - **Sincronização Reativa ao Navegar no Calendário**: Ao avançar no tempo para qualquer ano ou mês futuro no extrato, as transações futuras de regras contínuas são materializadas sob demanda.
- **Parcelamento Inteligente**:
  - Divisão automática em até **120 parcelas** com cálculo exato de centavos (`splitAmt`).
  - Sufixo automático com numeração da parcela no beneficiário (ex.: `Notebook (1/10)`).
  - Ajuste de dias para meses com 28, 30 e 31 dias mantendo a consistência do vencimento.
- **Diálogo de Escopo de Alteração e Exclusão (`ScopeChoice`)**:
  - *Apenas este lançamento*.
  - *O selecionado e todos os futuros não conciliados*.
  - *Todos os lançamentos da série*.
  - **Proteção Absoluta**: Lançamentos que já foram conciliados no banco nunca são alterados ou excluídos em edições de série.

### 6. Transferências Entre Contas
- **Lançamento Duplo Espelhado Atômico**: Geração simultânea do débito na conta de origem e do crédito na conta de destino vinculados por UID compartilhado (`xfer`).
- **Transferências Recorrentes Automáticas**:
  - Suporte completo ao modo **Recorrente** em transferências entre contas (Diário, Semanal, Quinzenal, Mensal, Bimestral, Trimestral, Semestral ou Anual).
  - Permite automatizar movimentações periódicas (ex.: aportes mensais para poupança/investimentos, mesadas, transferências de custódia).
  - Suporte a **Tempo Indeterminado (sem fim)** ou com **Data de Término Programada**.
  - O motor de projeção sincroniza automaticamente o débito na conta de origem e o crédito correspondente na conta de destino para todas as ocorrências da série.
  - Gestão de escopo atômica: editar ou excluir ocorrências (apenas esta, esta e futuras ou todas) mantém o espelhamento de ambas as pontas sempre íntegro.
- **Atualização Sincronizada**: Alterar data, valor ou descrição em uma das pontas sincroniza a contraparte automaticamente. Excluir uma ponta remove o espelho correspondente.
- **Neutralidade Patrimonial**: No Fluxo de Caixa Global, transferências internas não distorcem as receitas ou despesas globais. Na visualização de conta individual, a transferência é computada com o detalhamento da conta de contrapartida.

### 7. Categorias e Subcategorias com Proteção de Dados
- **Hierarquia Estruturada em Dois Níveis**: Categorias Principais e Subcategorias organizadas rigorosamente em **Despesas** e **Receitas**.
- **Controle de Inclusão em Relatórios (`includeInReports`)**:
  - Opção no cadastro e edição para habilitar/desabilitar se a categoria é computada nos relatórios mensais de receitas e despesas.
  - Indicador visual com badge `"Fora dos Relatórios"` para categorias configuradas para não pontuar nos relatórios analíticos.
- **Prevenção de Lançamentos Órfãos**:
  - Categorias sem lançamentos exigem confirmação explícita antes de serem excluídas.
  - Categorias em uso não podem ser excluídas diretamente; o sistema abre a modal de substituição (`CategoryDeleteSheet`) para reclassificar todos os lançamentos para outra categoria.
- **Importação e Exportação Estruturada em CSV**:
  - **Exportação com Padrão Hierárquico**: Gera arquivo CSV contendo `"Tipo"`, `"Categoria Principal"`, `"Subcategoria"` e a coluna combinada `"Categoria Completa"` formatada com o símbolo `"›"` (ex.: `"Alimentação › Bares e Restaurantes"`, `"Transportes › Combustível"`).
  - **Importação Resiliente**: Detecção automática de delimitadores (`;`, `,`, tab), suporte a formatos combinados com separadores (`›`, `>`, `/`), criação automática da categoria-pai e prevenção contra duplicatas.
  - Acesso direto por botões dedicados no cabeçalho da tela no macOS e no menu de ações no iOS.
- **Grid de Detalhamento dos Lançamentos por Categoria (`CategoryTransactionsDetailSheet`)**:
  - Botão dedicado **"Lançamentos"** e pílula interativa de contagem em cada linha de categoria e subcategoria.
  - Modal com grid completo e estruturado contendo: **Conta** (com ícone específico de banco ou cartão de crédito), **Data** (formatada `DD/MM/AAAA` monoespaçada), **Descrição/Favorecido** (com tags de recorrência e fatura), **Categoria Completa**, **Nota/Observação** e **Valor** (colorido em verde para receitas e vermelho para despesas).
  - **Filtro de busca em tempo real**, ordenação por data, valor e descrição, atalho de duplo clique para editar o lançamento diretamente e **exportação em CSV** da relação exibida.

### 8. Planejamento Financeiro: Orçamento Mensal (Budget)
- **Metas e Tetos de Gastos por Categoria**: Definição de limites mensais por categoria de despesa.
- **Soma Acumulada de Subcategorias**: Categorias principais que possuem subcategorias calculam e exibem automaticamente a soma acumulada das metas e dos gastos realizados.
- **Barras de Progresso Liquid Glass**: Gradientes luminosos indicando o percentual consumido, alertas visuais para limites estourados (vermelho) e indicação do saldo disponível restante.
- **Totalizador Geral**: Resumo no rodapé com o total planejado vs. total realizado no mês.

### 9. Relatório Analítico de Fluxo de Caixa (Mensal, Trimestral, Semestral e Anual)
- **Matriz Financeira Multidimensional Completa**:
  - Visão analítica matricial consolidada de todas as receitas e despesas organizadas por categoria e subcategoria.
- **Períodos Flexíveis de Análise**:
  - **Mensal**: 12 meses do ano (`01/AAAA` a `12/AAAA`) + Total acumulado do ano.
  - **Trimestral**: 4 trimestres consolidados + Total.
  - **Semestral**: 2 semestres consolidados + Total.
  - **Anual**: Comparativo plurianual de todos os anos da base + Total histórico.
- **Linhas Analíticas de Fechamento Contábil**:
  - Subtotais automáticos por categoria principal (`Total [Categoria]`) e lançamentos diretos sem subcategoria (`[Categoria] - Não-atribuído`).
  - Linhas destacadas de `Total Rendimento` e `Total Despesas`.
  - **Rendimento menos Despesas**: Resultado operacional líquido do período (superávit em verde, déficit em vermelho).
  - **Saldo Anterior Acumulado**: Apuração matemática exata do saldo real transitado de períodos anteriores (saldos iniciais + movimentações passadas).
  - **Saldo Final Acumulado**: Consolidação do saldo em caixa/bancos ao final de cada período (`Saldo Anterior + Rendimento - Despesas`).
- **Filtros e Controles Avançados**:
  - **Todas as Contas (Visão Consolidada)**: Sem transferências internas, refletindo a variação real do patrimônio global.
  - **Conta Específica**: Detalha movimentações individuais e computa transferências sob a categoria `Transferência`.
  - **Filtro de Status**: *Todos os Status*, *Apenas Conciliados* (auditoria fiscal/realizado) ou *Apenas Previstos/Futuros* (projeção orçamentária).
  - **Filtro de Regime de Data**: *Data do Lançamento* (regime de competência) vs. *Data de Pagamento da Fatura* (regime de caixa de cartões).
  - Navegador de anos (`‹ AAAA ›`), busca em tempo real e botões de **Recolher/Expandir Tudo**.
- **Layout Responsivo Calibrado**:
  - Exibição nítida a 100% nativo em resoluções Full HD (1920x1080).
  - Redimensionamento proporcional automático (escala adaptativa até 60%) em janelas ou monitores menores para manter todos os 12 meses visíveis sem cortes.
- **Exportação CSV Compatível com Excel e Planilhas**:
  - Delimitador `;`, decimais com vírgula BRL, metadados dos filtros ativos e codificação **UTF-8 com BOM** (abre perfeitamente no Excel, Numbers e Google Planilhas sem distorcer acentuação).

### 10. Relatórios e Análise Mensal
- **Exclusão de Transferências e Categorias Neutras**: Não exibe e não soma nos totais de receitas e despesas transferências entre contas e categorias marcadas como fora dos relatórios (ex.: "Transferencias (C)", "Transferencias (D)").
- **Navegação de Mês com Seletor Rápido (`MonthYearQuickPicker`)**:
  - Cabeçalho interativo com ícone de calendário e indicador de expansão (`calendar` e `chevron.down`) ao lado dos botões sequenciais de anterior (‹) e próximo (›), além do atalho "Hoje".
  - Popover de salto temporal em 2 cliques: seletor de anos (‹, ›, atalhos "Ano Anterior" / "Próximo" e menu suspenso com anos presentes no banco de dados), grade 4x3 dos 12 meses (com iluminação do mês selecionado e mês corrente) e botão "Mês Atual (Hoje)".
  - Disponível e sincronizado tanto no macOS (`ReportsView`) quanto no iOS (`iOSReportsTab`).
- **Cards de Métricas Liquid Glass**: Receitas, Despesas, Saldo Líquido do Mês e **Taxa de Poupança** (*Savings Rate* percentual).
- **Distribuição Gráfica por Categoria**: Gráfico de barras proporcional com ranking e percentual de participação de cada categoria e subcategoria no total do mês.
- **Drill-down Interativo por Categoria e Subcategoria**:
  - **Clique Direto para Detalhar**: Ao clicar na linha de qualquer categoria principal ou subcategoria nas listas de Receitas ou Despesas (com realce ao passar o mouse e cursor de mão no macOS, e toque com `chevron.right` no iOS), o sistema abre instantaneamente a janela modal com todos os lançamentos que compõem aquele valor.
  - **Filtro Contextual do Mês**: Abre automaticamente pré-filtrado para o mês ativo analisado no relatório (assegurando que o total bata no centavo com a barra de progresso), incluindo seletor rápido no cabeçalho para alternar entre o mês em questão e o histórico completo (*Todos os períodos*).
  - **Granularidade Precisa**: Clicar na categoria principal detalha todos os lançamentos dela e de suas subcategorias; clicar na subcategoria foca estritamente nos lançamentos específicos daquela subcategoria.
  - **Auditoria e Ações Rápidas**: Visualização de Conta, Data, Descrição, Categoria, Nota e Valor, com busca instantânea, ordenação, atalho de duplo clique para editar o lançamento e botão de exportação em CSV do extrato da categoria.
- **Impressão e Exportação em PDF Adaptada em 1 Página (`MonthlyReportPrintView` / `MonthlyReportPDFGenerator`)**:
  - **Menu e Atalhos de Impressão**: Menu "Imprimir / PDF" na barra superior do relatório no macOS com atalho global `Cmd + P`, item no menu Arquivo/Exportar, e botão na barra de navegação/rodapé no iOS.
  - **Impressão Nativa**: Diálogo padrão de impressão do macOS (`NSPrintOperation`) com suporte completo a impressoras físicas, AirPrint e "Salvar como PDF...", e `UIPrintInteractionController` no iOS.
  - **Exportação Direta em PDF**: Geração vetorial direta de arquivo `.pdf` via `NSSavePanel` no macOS e `ShareLink` (Salvar em Arquivos, AirDrop, etc.) no iOS.
  - **Design Calibrado para 1 Página A4**: Layout executivo profissional (595 x 842 pt) com cabeçalho oficial OpenMoney com data/hora de emissão, cards KPI de resumo financeiro, distribuição lado a lado em 2 colunas (Receitas à esquerda, Despesas à direita) com barras de participação percentual e condensação adaptativa de subcategorias e categorias excedentes, barra de saldo líquido final e rodapé de autenticação, garantindo adaptação perfeita em 1 página única.

### 11. Central de Importação e Exportação (CSV e QIF — Microsoft Money 99)
- **Central de Importação/Exportação CSV (`CSVImportExportSheet`)**:
  - Modal dedicada no macOS (`Cmd + Option + I`) e na aba Base de Dados no iOS.
  - Permite escolher a conta de destino (automática pela coluna do CSV ou conta fixa selecionada).
  - **Pré-Verificação e Auto-Criação de Contas**: Examina a coluna de contas antes de importar e cria automaticamente as contas ausentes no cadastro antes de associar os lançamentos, evitando que transações de contas distintas sejam misturadas na mesma conta.
  - **Flag de Controle de Duplicidade** (*Permitir importação de lançamentos duplicados*):
    - **Desativado (Padrão de Segurança)**: Verificação instantânea $O(1)$ por chave única (`conta|data|valor|favorecido`). Ignora transações idênticas já cadastradas e informa no resumo final a quantidade de lançamentos duplicados ignorados.
    - **Ativado**: Permite importar transações idênticas caso o usuário opte por carregar deliberadamente lançamentos com mesma conta, data, valor e favorecido.
  - Disponível também diretamente no seletor de arquivos do macOS (`NSOpenPanel`) através de checkbox integrada como *accessory view*.
- **Exportação CSV Universal**: Por conta individual ou de todas as contas consolidadas com cabeçalho padrão, valores BRL e UTF-8 com BOM (compatível com Excel, Numbers e Google Planilhas).
- **Importação QIF do Microsoft Money 99 e Quicken**:
  - Suporte completo ao formato `.qif` clássico.
  - Decodificação resiliente com fallback para **Windows CP1252 / Latin-1**, preservando acentos e caracteres especiais originais do Money 99.
  - Reconhecimento automático de contas bancárias, cartões de crédito, dinheiro e investimentos.
  - Identificação e pré-criação automática de contrapartes em transferências entre contas no padrão `[NomeDaConta]`.
  - Relatório pós-importação detalhado com total de transações importadas, duplicatas ignoradas, novas categorias cadastradas e novas contas criadas.

### 12. Gestão da Base de Dados na Barra de Menus (macOS) e Nuvem
- **Exibição do Nome da Base na Barra de Título e no Cabeçalho**:
  - A barra superior do aplicativo e a barra de título da janela do macOS exibem dinamicamente o nome do arquivo da base atualmente carregada (ex: `OpenMoney — openmoney.json`), assegurando total transparência sobre qual banco de dados está ativo em tempo real.
- **Criação de Nova Base de Dados**: Opção **Nova Base de Dados...** (`Cmd + N`) permitindo escolher nome de arquivo e pasta pelo `NSSavePanel` (iCloud, pasta de rede, etc.).
- **Acesso Completo via Menu Arquivo**:
  - *Nova Base de Dados...* (`Cmd + N`)
  - *Abrir Base de Dados...* (`Cmd + O`)
  - *Abrir Recente* (submenu dinâmico com histórico de até 10 bases)
  - *Mover Base de Dados (Sincronizar)...* (`Cmd + Shift + M`)
  - *Central de Importação/Exportação CSV...* (`Cmd + Option + I`)
  - Menu suspenso *Exportar* (CSV por conta ou consolidado, Categorias em CSV, Relatório Mensal em PDF e Backup Completo ZIP/JSON via `Cmd + Shift + E`).
  - Menu suspenso *Importar* (Lançamentos em CSV via `Cmd + I`, Categorias em CSV, Arquivos QIF via `Cmd + Shift + Q` e Restaurar Backup ZIP/JSON).
  - Menu suspenso *Backups de Segurança* (Histórico de Backups via `Cmd + Shift + B`, Criar Backup em ZIP Agora e Revelar Pasta de Backups no Finder).
  - *Excluir Lançamentos por Período / Conta...* (limpeza em lote segura com backup prévio).
  - *Revelar Base no Finder*.
- **Barra Lateral Limpa**: Os botões de gerenciamento de banco de dados foram transferidos para a barra de menus do sistema macOS, garantindo ergonomia e deixando os cartões de Patrimônio Líquido com total destaque visual.
- **Sincronização Livre na Nuvem**: Suporte nativo para armazenar a base `openmoney.json` no iCloud Drive, Dropbox, Google Drive, OneDrive ou localmente.
- **Gravação Atômica e Limpeza de Resíduos**:
  - Gravação estritamente atômica utilizando arquivos temporários (`.tmp`) e substituição segura (`replaceItemAt`), imune a falhas de energia ou encerramento inesperado.
  - Descontinuação do antigo arquivo `openmoney.json.bak` solto, com limpeza automática de arquivos legados da pasta da base.
- **Arquitetura de Alta Performance ($O(1)$)**:
  - Cache estruturado em memória de lançamentos por conta e por mês.
  - Transição instantânea entre contas e meses, mesmo em bases com mais de **30.000 lançamentos** e arquivos JSON de mais de 5 MB.
  - Gravação assíncrona em thread secundária com *debounce* de 350ms, eliminando qualquer travamento ou engasgo na interface do usuário.

### 13. Rotina Inteligente de Backups em ZIP com Retenção de 7+ Dias (`BackupManager`)
- **Fim da Sobrescrita do `.bak`**: Anteriormente, cada alteração no app sobrescrevia cegamente o `.bak` da pasta local em apenas 350 milissegundos, impedindo a recuperação de erros cometidos minutos ou dias antes. A nova arquitetura isola o histórico em snapshots versionados e imutáveis.
- **Compressão Máxima em `.zip` (Economia de ~85% a 90%)**:
  - O JSON da base de dados é altamente redundante em termos de chaves textuais. A compactação nativa em ZIP reduz uma base de vários megabytes para poucas centenas de kilobytes.
  - Gera arquivos compatíveis nativamente com qualquer sistema operacional (macOS, Windows, Linux, iOS).
- **Pasta Isolada e Protegida**:
  - Localização padrão: `~/Library/Application Support/OpenMoney/Backups/`.
  - A pasta de trabalho da base ativa (seja no iCloud Drive, Documentos ou Dropbox) permanece 100% limpa, sem poluição de arquivos temporários ou backups intermediários.
- **Geração Automática de Snapshot Diário**:
  - No primeiro salvamento do dia ou ao inicializar o aplicativo, o sistema gera automaticamente uma cópia de segurança nomeada no formato:
    ```
    openmoney-backup-YYYY-MM-DD.zip
    ```
  - Executado em thread secundária assíncrona (`Task.detached(priority: .utility)`), sem impactar o desempenho ou a taxa de quadros (60 fps) da interface gráfica.
- **Política de Retenção de 7 Dias com Salvaguarda de Quantidade**:
  - Rotina automática de expurgo (`pruneBackups`): analisa os arquivos compactados e remove os backups mais antigos que 7 dias corridos.
  - **Trava de Segurança Inviolável**: O expurgo só é executado se existirem **mais de 7 backups** na pasta. Se o usuário ficar dias ou semanas sem abrir o OpenMoney, os últimos snapshots são integralmente preservados, garantindo sempre no mínimo uma semana completa de pontos de restauração.
- **Backups Pontuais com Timestamp**:
  - Snapshots com carimbo de segundo (`YYYY-MM-DD_HHmmss`) gerados automaticamente antes de operações sensíveis (como exclusão de lançamentos em lote) e sob demanda manual pelo usuário.
- **Janela Modal de Histórico de Backups (`Cmd + Shift + B`)**:
  - Acessível pelo atalho global `Cmd + Shift + B` ou pelo menu *Arquivo › Backups de Segurança › Histórico de Backups (Últimos 7 Dias)...*.
  - Exibe a lista cronológica decrescente dos arquivos `.zip` com ícones Apple SF Symbol `doc.zipper`.
  - Informações detalhadas de cada ponto: nome do arquivo, data e hora de criação e tamanho compactado em KB/MB.
  - Botão **Restaurar**: diálogo de confirmação com 1 clique para restaurar a base e recarregar os dados instantaneamente.
  - Botão **Criar Backup Agora**: gera um snapshot manual imediato.
  - Botão **Revelar Pasta no Finder**: abre diretamente o diretório de backups no macOS.
- **Restauração Universal (ZIP e JSON)**:
  - O painel de restauração suporta arquivos `.zip` e `.json`.
  - Ao selecionar um arquivo `.zip`, o motor extrai o banco em sandbox temporária, valida a integridade da estrutura `Database` e aplica a migração e conciliação atômica.

### 14. Experiência Multiplataforma e Usabilidade
- **Menu Planejamento na Barra Superior do macOS**:
  - `Contas a Pagar e Receber` (`Cmd + Option + 5`)
  - `Fluxo de Caixa` (`Cmd + Option + 1`)
  - `Relatórios` (`Cmd + Option + 2`)
  - `Orçamento` (`Cmd + Option + 3`)
  - `Categorias e Subcategorias` (`Cmd + Option + 4`)
- **Atalhos Globais no macOS**:
  - `Cmd + ?`: Abrir Ajuda e Manual do OpenMoney.
  - `Cmd + N`: Criar nova base de dados.
  - `Cmd + O`: Abrir base de dados existente.
  - `Cmd + Shift + M`: Mover/trocar localização da base.
  - `Cmd + Shift + F`: Pesquisa em toda a base de dados (Busca Global).
  - `Cmd + Shift + B`: Histórico de backups automáticos (restauração e gerenciamento de snapshots).
  - `Cmd + Option + 5`: Abrir Central de Contas a Pagar e Receber (Lembretes & Conciliação).
  - `Cmd + I`: Importar lançamentos CSV.
  - `Cmd + Option + I`: Central de importação/exportação CSV.
  - `Cmd + Shift + Q`: Importar arquivo QIF do Microsoft Money 99.
  - `Cmd + Shift + E`: Exportar backup completo (ZIP / JSON).
- **Navegação Nativa no iOS / iPadOS**: Abas dedicadas (**Contas**, **Vencimentos** com badge de pendências dinâmico, **Buscar**, **Fluxo de Caixa**, **Relatórios**, **Orçamento**, **Categorias**, **Base**), suporte completo a gestos de deslizar (*swipe*), menus de contexto e integração com o seletor de arquivos nativo da Apple.

### 15. Sistema de Ajuda e Manual Integrado (Sincronizado Sempre com o README.md)
- **Menu "Ajuda" Nativo no macOS**:
  - Acesso direto pelo menu do sistema **Ajuda** ou pelo atalho `Cmd + ?` (`⌘?`).
  - Opções para abrir a janela de ajuda interativa, abrir o `README.md` no editor de texto externo e recarregar os dados do disco.
- **Sincronização Dinâmica em Tempo Real**:
  - O motor de ajuda (`HelpManager`) lê o arquivo `README.md` dinamicamente do disco em tempo de execução (checando diretório do projeto, recursos empacotados no bundle e fallback compilado `EMBEDDED_README`).
  - Qualquer alteração realizada no `README.md` reflete imediatamente na tela de ajuda através do botão "Recarregar", sem necessidade de reiniciar o aplicativo.
  - A rotina de compilação (`build-app.sh` e `build-ios.sh`) sincroniza automaticamente o `README.md` com o código-fonte (`HelpContent.swift`) e a pasta de recursos do aplicativo antes de cada build.
- **Visualizador Estruturado com Busca e Blocos Ricos**:
  - Navegação lateral por tópicos indexados (Visão Geral, Regras de Negócio, Funcionalidades, Como Compilar e Manual Completo).
  - Campo de busca instantânea filtrando tópicos e regras.
  - Renderização rica em Liquid Glass com suporte a cabeçalhos, marcadores, listas numeradas, citações e blocos de código com botão de cópia com 1 clique.
  - Acessível também pelo botão `?` no cabeçalho da barra lateral no macOS e pela aba **Base** no iOS/iPadOS.

### 16. Atualização Automática pela Internet (macOS)
- **Verificação ao Abrir e Sob Demanda**:
  - Ao iniciar, o app consulta silenciosamente se há uma versão mais nova; se não houver, nada é exibido.
  - Manualmente, use o menu **OpenMoney > Buscar Atualizações...** ou **Ajuda > Buscar Atualizações...**.
- **Janela de Atualização Disponível**:
  - Mostra versão atual, nova versão, data e as notas da versão, com os botões **Instalar e Reiniciar**, **Lembrar Mais Tarde** e **Ver no GitHub**.
  - O download exibe barra de progresso; ao concluir, o app descompacta o pacote, substitui o `OpenMoney.app`, fecha e reabre sozinho já atualizado.
- **Distribuição**:
  - O código-fonte fica no repositório privado; os pacotes ficam no repositório público [`FSF77/openmoney-releases`](https://github.com/FSF77/openmoney-releases), no formato `downloads/OpenMoney-<versão>.zip`, junto com o feed `version.json`.
  - A consulta ignora o cache do CDN do GitHub (usa o commit mais recente do repositório), detectando novas versões imediatamente após a publicação.
- **Instalação Inicial ou Manual**:
  - Instalação/atualização com um comando no Terminal:
    ```bash
    curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-releases/main/install.sh | bash
    ```
  - Se o macOS exibir *"OpenMoney está danificado e não pode ser aberto"* após baixar o `.zip` pelo navegador (o app não é notarizado pela Apple), execute uma única vez: `xattr -cr /Applications/OpenMoney.app`. As atualizações feitas pelo próprio app não exibem esse aviso.
- **Publicar uma Nova Versão (desenvolvedor)**:
  ```bash
  ./build-app.sh 1.0.29 "Notas da versão" --publish
  ```
  O script atualiza `VERSION` e `BUILD_NUMBER`, compila e assina o app, gera o `.zip` e o `version.json` e publica tudo no repositório de releases.

### 17. OpenMoney Coletor Mobile (PWA) e Rotina de Entrada Rápida na Rua
- **Acesso pelo Navegador do Smartphone**:
  - **OpenMoney Coletor (Entrada Rápida + Scanner OCR)**: [https://fsf77.github.io/openmoney-releases/coletor/](https://fsf77.github.io/openmoney-releases/coletor/)
  - **OpenMoney Web Completo (Extratos e Painel)**: [https://fsf77.github.io/openmoney-releases/web/](https://fsf77.github.io/openmoney-releases/web/)
- **Instalação como PWA no iOS**:
  - No Safari do iPhone, abra o endereço do Coletor, toque no botão de **Compartilhar** e selecione **"Adicionar à Tela de Início"**. O app funciona em tela cheia como aplicativo nativo, com suporte offline via Service Worker.
- **Fluxo do Dia a Dia**:
  1. No primeiro acesso, toque em **Trocar** e selecione o seu `openmoney.json` uma única vez.
  2. Ao fazer uma compra na rua, toque em **📷 Escanear Recibo** ou **✍️ Novo Lançamento**.
  3. No final do dia ou da semana, toque em **Exportar para o Mac** e salve o `openmoney_inbox.json` no iCloud Drive, AirDrop ou pasta compartilhada.
  4. No Mac, acione **`Cmd + Option + M`** para revisar e incorporar todos os novos lançamentos à sua base com 1 clique.

---

## 📁 Estrutura do Projeto

```text
ProjOpenMoney/
├── Package.swift                    # Configuração SPM (macOS 14+, iOS 17+)
├── build-app.sh                     # Script de compilação autônoma do OpenMoney.app (macOS)
├── build-ios.sh                     # Script de compilação do OpenMoney para iOS / iPadOS
├── README.md                        # Documentação completa e regras de negócio
├── VERSION / BUILD_NUMBER           # Versão e build atuais (atualizados pelo build-app.sh)
├── coletor/                         # OpenMoney Coletor Mobile (PWA leve + OCR em WebAssembly)
│   ├── index.html                   # Interface mobile com Liquid Glass e tema dinâmico
│   ├── manifest.json / sw.js        # Configuração PWA e suporte offline
│   ├── css/style.css                # Estilos responsivos com modo claro e escuro
│   └── js/ (app.js, db.js, ocr.js)  # Motor de OCR local, fila pendente e autocompletar
├── web/                             # OpenMoney Mobile Web Completo (PWA com extratos completos)
├── Sources/
│   └── OpenMoney/
│       ├── OpenMoneyApp.swift       # Entry point do app (@main), menu bar e ciclo de vida
│       ├── Models.swift             # Modelos de dados (Account, Transaction, Database) e helpers
│       ├── BackupManager.swift      # Gestão de backups em ZIP, retenção diária de 7 dias e expurgo
│       ├── NotificationManager.swift # Gerenciador de notificações locais do sistema (macOS/iOS) e badges
│       ├── ImportersExporters.swift # Parsers de CSV, QIF (Money 99) e Coletor Mobile (inbox)
│       ├── Store.swift              # MoneyStore (gerenciamento de estado, I/O, regras de negócio)
│       ├── Views.swift              # Componentes de UI Desktop macOS e Design System Liquid Glass
│       ├── iOSViews.swift           # Componentes adaptados para iPhone e iPad
│       ├── UpdateManager.swift      # Atualização automática pela internet (feed, download, instalação)
│       ├── Resources/               # Ícones (.icns, .png)
│       └── Assets.xcassets/         # Asset Catalog com ícones para todas as resoluções
└── scripts/
    ├── embed-readme.py              # Sincroniza README.md na ajuda interna do aplicativo
    ├── generate-icon.swift          # Utilitário Swift para renderização procedural do ícone
    ├── publish-web.sh               # Publica o Web App e o Coletor no GitHub Pages
    └── publish-release.sh           # Publica o .zip e o version.json no repositório de releases
```

---

## 🛠️ Tecnologias Utilizadas

- **Linguagem**: Swift 5.9+
- **Interface**: SwiftUI 5+ (materiais translúcidos nativos, escala responsiva, animações contínuas)
- **Frameworks Apple**: `SwiftUI`, `AppKit` (macOS), `UIKit` (iOS), `UniformTypeIdentifiers`
- **Armazenamento e Performance**: JSON Schema estruturado e atômico com indexação em memória $O(1)$, salvamento assíncrono em background (debounced, sem travamento de UI em bases com mais de 30.000 lançamentos) e importadores em lote otimizados via Sets hash.

---

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo `LICENSE` para mais detalhes.

*OpenMoney é um projeto independente de código aberto, concebido por entusiastas de finanças pessoais. Não possui afiliação, vínculo ou endosso da Microsoft Corporation.*
