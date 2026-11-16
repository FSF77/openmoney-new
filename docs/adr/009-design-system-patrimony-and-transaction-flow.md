# ADR 009: Padronização de Design System, Visibilidade de Patrimônio e Fluxo de Novo Lançamento

## Status
**Aprovado e Implementado** (Swift macOS, Swift iOS e Flutter Multiplataforma).

---

## Contexto

À medida que o ecossistema evoluiu com as funcionalidades contábeis e de conciliação (ADRs 001 a 008), observaram-se necessidades de refinamento na interface de usuário (UI/UX) para manter perfeita uniformidade estética e ergonômica entre as plataformas desktop e mobile (Swift nativo e Flutter):

1. **Card de Patrimônio Consolidado no Menu Lateral**:
   - O card apresentava disparidade de posicionamento (no rodapé no Swift vs no topo no Flutter) e tipografia com fontes em tamanhos discrepantes e estilos monoespaçados heterogêneos.
   - Havia a necessidade de incluir a previsão de saldo acumulado até o término do ano vigente (`Previsto no ano`), mantendo a hierarquia visual nivelada com os demais itens do menu lateral e sem poluição.
   - Demanda de privacidade para ocultação rápida de valores em locais públicos ou gravações de tela.

2. **Hierarquia e Pré-seleção no Fluxo de "Novo Lançamento"**:
   - Ao acionar a criação de transação a partir do menu lateral, o seletor de contas não priorizava o contexto da conta ativa na tela, exigindo re-seleção manual.
   - A lista de seleção de contas nos modais não refletia visualmente a prioridade das contas favoritas.

3. **Padronização Visual e Alinhamentos dos Controles de Formulário**:
   - Ajuste fino na altura e nivelamento dos botões de ação e alternadores na barra de inserção rápida e relatórios, equalizando a altura visível das caixas com rótulo flutuante (`OutlineInputBorder`).

4. **Navegação para Contas de Cartão de Crédito e Fatura em Aberto**:
   - Quando o usuário estava visualizando um mês anterior em uma conta corrente (ou qualquer outro módulo) e navegava para uma conta de cartão de crédito cuja fatura daquele mês já estava fechada, a interface permanecia posicionada no mês passado fechado, em vez de exibir a fatura corrente em aberto onde caem novos lançamentos.

---

## Decisões Tomadas

### 1. Card de Patrimônio Consolidado Unificado
- **Posicionamento**: No menu lateral esquerdo, posicionado logo abaixo do bloco de identificação/título e imediatamente acima do botão de ação primária "Novo Lançamento", em todas as plataformas desktop e mobile.
- **Tipografia Equalizada**:
  - Rótulo superior: `Patrimônio consolidado` (tamanho 11, seminegrito, cor secundária).
  - Linhas de valores com tipografia estritamente unificada (tamanho 12.5 no desktop / 12 no mobile, mesma família de fonte nativa, peso médio `w500` para os rótulos e negrito `w700` para os valores com figuras tabulares):
    - `Real: R$ X.XXX,XX`: valor destacado com a cor de receita (`omGreen`) ou despesa (`omRed`).
    - `Previsto no mês: R$ X.XXX,XX`: saldo projetado considerando as transações e faturas até a competência do mês selecionado.
    - `Previsto no ano: R$ X.XXX,XX`: cálculo acumulado até o final do ano corrente (`AAAA-12-31` e competência `AAAA-12` para cartões de crédito).
- **Modo Privacidade (Ícone de Olho)**:
  - Botão de alternância com ícones `eye` / `eye.slash` (Swift) e `visibility` / `visibility_off` (Flutter).
  - Quando ativado, mascara os três valores com `••••••`.
  - Preferência salva e persistida nas configurações do usuário (`config.json` no Flutter e `@AppStorage("sidebar.hidePatrimonyBalance")` no Swift).

### 2. Algoritmo `totalBalancePredictedYear()`
Implementado em ambas as stacks (`MoneyStore` em Swift e Flutter) seguindo a regra contábil:
- Identifica o ano corrente a partir da competência ativa (`store.month.prefix(4)`).
- Limite temporal definido como `AAAA-12-31` (e fatura `AAAA-12` para contas do tipo `Cartão de Crédito`).
- Soma saldo inicial de todas as contas cadastradas com as transações conciliadas e as pendentes que venham a vencer até o último dia do ano em curso.

### 3. Ordem e Pré-Seleção de Contas em Novos Lançamentos
Ao abrir o modal de "Novo Lançamento":
1. **Prioridade de Pré-seleção**:
   - Se o usuário estiver visualizando o extrato de uma conta específica (`NavModule.account`), essa conta é selecionada automaticamente.
   - Caso contrário, seleciona-se a primeira conta da lista de **Favoritas** ativa.
   - Se não houver favorita, seleciona-se a **primeira conta ativa**.
   - Se não houver ativas, recai sobre a primeira conta da base.
2. **Ordenação do Dropdown**:
   - Contas favoritas no topo, identificadas visualmente com estrela `★`.
   - Seguidas pelas demais contas ativas.

### 4. Nivelamento Visual de Formulários
- No Flutter, ajustou-se a barra de inserção rápida e os seletores com `height: 36px` e compensação de padding superior de `2.0px`, sincronizando o contorno oval dos botões (`StadiumBorder`) exatamente à linha de centro dos contornos de texto com rótulo (`OutlineInputBorder`).

### 5. Priorização da Fatura em Aberto ao Acessar Cartão de Crédito e Retorno ao Mês Atual em Contas Tradicionais
- **Cartões de Crédito**: Ao selecionar/navegar para uma conta do tipo Cartão de Crédito (`type == kCardType / CARD_TYPE`), o sistema calcula a fatura aberta atual na data de referência (`openIk = invKeyFor(card, todayISO())`). Se a competência selecionada atualmente na sessão for anterior à fatura aberta (`store.month < openIk`), o sistema avança automaticamente a visualização (`store.month = openIk`), exibindo imediatamente a fatura em aberto do cartão.
- **Contas Não-Cartão (Corrente, Dinheiro, Poupança, Investimentos, etc.)**: Ao clicar ou alternar para qualquer conta tradicional que não seja cartão de crédito, o sistema reposiciona automaticamente o extrato para a competência do mês corrente (`store.month = currentMonthKey`), garantindo que o usuário visualize de imediato as movimentações do mês atual em vez de permanecer retido no mês futuro da fatura do cartão.
- **Liberdade de Navegação Mantida**: Caso o usuário queira consultar meses passados ou futuros em qualquer conta, pode navegar livremente pelo seletor de mês/ano do extrato. O ajuste automático ocorre estritamente no momento do clique/seleção da conta.
- **Paridade Multiplataforma**: Regra aplicada no Flutter (`money_store.dart` e `account_ledger_view.dart`) e no Swift (`Store.swift`, `Views.swift` no macOS e `iOSViews.swift` no iOS).

### 6. Bloqueio de Categorias e Subcategorias
- **Objetivo**: Permitir desativar categorias obsoletas ou que não devem mais receber novas movimentações, sem perder o histórico contábil.
- **Comportamento**:
  - Uma categoria bloqueada (`blocked == true`) é totalmente preservada no banco de dados, fluxo de caixa, relatórios de receitas/despesas e orçamentos históricos.
  - É **ocultada automaticamente de todas as caixas de seleção de categorias ao criar novos lançamentos** (modal de novo lançamento, barra rápida do extrato e criação por cópia/importação).
  - Caso um lançamento antigo já existente utilize a categoria bloqueada e seja aberto para edição, a categoria é exibida na seleção pontual para não corromper o cadastro preexistente.
  - Ao bloquear uma categoria principal (pai), todas as suas subcategorias herdam o bloqueio.
  - Na tela de catálogo de categorias, exibe-se a tag de status `BLOQUEADA` e um controle para alternar/bloquear facilmente.
- **Schema JSON**: Campo opcional booleano `blocked` no objeto `CategoryItem` (`openmoney.json`), omitido quando falso/nulo para economia de espaço.

### 7. Direcionamento para o Mês da Fatura ao Inserir Lançamento de Cartão de Crédito
- **Regra**: Ao adicionar um lançamento (`addTransaction`) ou navegar para uma transação (`navigateToTransaction`):
  - Em **contas tradicionais** (corrente, dinheiro, etc.), o sistema posiciona `store.month` no mês da data da transação (`date.substring(0, 7)`).
  - Em **contas de cartão de crédito** (`type == kCardType / CARD_TYPE`), o sistema posiciona `store.month` no mês da **competência da fatura** (`baseIk` / `tx.ik`), e não na data em que a compra ocorreu. Por exemplo: uma compra em 26/10 com fatura fechando dia 25/10 direciona imediatamente para o extrato da fatura de Dezembro (`2026-12`), permitindo ao usuário conferir instantaneamente o lançamento na fatura onde ele efetivamente reside.

### 8. Botões Compactos de Exportação e Importação (Ícone + Tooltip)
- **Objetivo**: Otimizar o espaço horizontal dos cabeçalhos em todas as telas operacionais e analíticas.
- **Padrão Visual**:
  - Os botões **"Exportar CSV"**, **"Importar CSV"**, **"Exportar Extrato PDF"**, **"Exportar Fatura PDF"**, **"Exportar PDF A4"** e **"Exportar PDF Anual"** são exibidos de forma compacta contendo apenas o respectivo ícone (`Icons.download`, `Icons.upload_file`, `Icons.picture_as_pdf_outlined`) dentro de um `OutlinedButton` de fundo neutro sem destaque de cor saturada, acompanhado de `Tooltip` descritivo ao posicionar o cursor.
  - Aplicado uniformemente nas telas: **Fluxo de Caixa**, **Extrato de Lançamentos**, **Relatórios**, **Categorias**, **Contas a Pagar & Receber** e **Compras Parceladas**.

### 9. Fluxo de Caixa: Nivelamento de Filtros e Cards de Resumo (KPIs)
- **Nivelamento da Barra de Filtros**:
  - Todas as caixas de seleção e busca (Contas, Status, Tipo, Regime e Filtrar categoria) possuem altura padronizada de `40px` e alinhamento vertical superior (`WrapCrossAlignment.start`), eliminando deslocamentos verticais entre `AccountMultiSelectFilter` e os demais controles.
- **Cards de Resumo (KPIs)**:
  - Adicionada linha de cards executivos exibindo **Total de Receitas** (com ícone positivo em verde), **Total de Despesas** (com ícone negativo em vermelho) e **Resultado Líquido** (com ícone dinâmico conforme saldo superavitário ou deficitário), espelhando o layout nativo do Swift.

### 10. Base de Dados Local vs Cloud & Sincronização, Modal Simplificado e Rodapé do Menu Lateral
- **Nomenclatura Simplificada**: O modal e os botões de acesso ao arquivo local foram padronizados com o título **"Base de Dados Local"** (substituindo `"Base de Dados & Sincronização (iCloud Drive / OneDrive)"`).
- **Modal Direto e Sem Confusão de Caminho**:
  - Removido o campo de texto manual de caminho e atalhos intermediários confusos ("Pasta Nuvem Padrão", "Criar Nova Base Aqui", "Mover Base Atual").
  - A interface conta com dois botões de ação imediata:
    1. **"Abrir Base Existente"**: Abre diretamente o seletor nativo do sistema (Finder no macOS ou Explorer no Windows) para selecionar o arquivo `.json` desejado e, ao confirmar, carrega a base imediatamente.
    2. **"Criar Nova Base"**: Abre diretamente o seletor nativo para escolher a pasta e nome do novo arquivo `.json`, inicializando e abrindo a nova base de forma instantânea.
  - A seção de **"Arquivos Recentes"** permanece ativa e em destaque, permitindo alternar rapidamente entre bases utilizadas com um clique no botão "Abrir" ou remover itens da lista.
- **Inibição Inteligente com Cloud Ativo**: Quando o serviço **Cloud & Sincronização** está autenticado e habilitado (`CloudSyncService.instance.isAuthenticated`), o botão de atalho da Base de Dados Local é automaticamente inibido na barra de topo e no menu, evitando confusão sobre qual fonte de dados está ativa.
- **Rodapé em Linha Única**: No rodapé da barra lateral, as informações de e-mail sincronizado, status da nuvem e versão do aplicativo são renderizadas em linha única (`maxLines: 1`, `softWrap: false`, `TextOverflow.ellipsis`) com `Tooltip` completo, impedindo cortes verticais de texto.

### 11. Comentários por Período na Linha "Saldo Final Acumulado" do Fluxo de Caixa
- **Objetivo**: Permitir que o usuário registre observações e informações relevantes atreladas ao fechamento de cada período (mensal, anual, diário, etc.) diretamente na última linha do Fluxo de Caixa (**Saldo Final Acumulado**).
- **Comportamento e Interação**:
  - Ao clicar em qualquer célula de período da linha **Saldo Final Acumulado**, abre-se um modal contextual (`Comentário do Saldo Final`) exibindo o período, o saldo correspondente e uma caixa de texto multi-linha para inserir, editar ou excluir a anotação.
  - Células que possuem comentário armazenado exibem um pequeno indicador visual (ícone de balão `Icons.comment_outlined` / `bubble.left.fill`) ao lado do valor monetário, além de exibir o conteúdo completo no `Tooltip` ao passar o mouse.
- **Persistência no Schema (`openmoney.json`)**:
  - Armazenado no dicionário `comments` (`Map<String, String>` no Dart / `[String: String]` no Swift) na raiz do objeto `Database`, indexado pelo `id` canônico da coluna do período (ex: `"2026-10"` na visão mensal, `"2026"` na visão anual).

### 12. Otimização de Tipografia, Espaçamentos e Ajuste Responsivo no Fluxo de Caixa (Paridade Swift)
- **Problema**: No Flutter, colunas mensais com largura fixa de `130px` e tipografia `12.0px - 12.5px` causavam transbordamento horizontal da tabela em resoluções Full HD (1920x1080), exigindo rolagem horizontal mesmo com zoom em 90% ou 100%.
- **Solução e Equalização com o Swift**:
  - **Largura Base das Colunas**: Padronizada para `86px` no modo mensal (em consonância com os `85px` do Swift), `112px` diário, `115px` trimestral/anual e `135px` na coluna Total.
  - **Distribuição Responsiva Dinâmica**: Quando a tela dispõe de largura superior (como monitores 1080p, 1440p ou janelas maximizadas), a largura das colunas expande proporcionalmente (clamp entre `86px` e `108px`), ocupando o espaço com elegância sem gerar rolagem horizontal desnecessária.
  - **Tipografia e Alturas Compactas**: Fontes numéricas e de categorias niveladas com a versão Swift (tamanhos `9.5px` a `10.5px` em fontes monoespaçadas com figuras tabulares), alturas de linha ajustadas (`30px` grupos, `24px` subcategorias, `38px` cabeçalho, `32-36px` totais) e padding horizontal reduzido para `3px`, eliminando quebras de linha mesmo em valores de grande magnitude (centenas de milhões).
  - **Respiro Inferior**: Inclusão de espaçador inferior dedicado (`20px`) para evitar qualquer sobreposição da barra de rolagem horizontal sobre os números da última linha do Saldo Final Acumulado.

### 13. Cabeçalho de Períodos no Fluxo de Caixa em Linha Única
- **Problema**: O cabeçalho dos períodos no Fluxo de Caixa renderizava duas linhas de texto por coluna (ex: `Jan/26` sobre `01/2026`, `01` sobre `01/10`, `1° Trim` sobre `1° Trimestre`), gerando poluição visual, redundância e ocupando espaço vertical excessivo.
- **Formatação em Linha Única**:
  - **Diário**: exibe apenas os dias em dois dígitos (`01`, `02`, ..., `31`).
  - **Mensal**: exibe apenas a sigla do mês em caixa alta (`JAN`, `FEV`, `MAR`, `ABR`, `MAI`, `JUN`, `JUL`, `AGO`, `SET`, `OUT`, `NOV`, `DEZ`).
  - **Trimestral**: exibe `1º TRIM`, `2º TRIM`, `3º TRIM`, `4º TRIM`.
  - **Semestral**: exibe `1º SEM`, `2º SEM`.
  - **Anual**: exibe apenas o ano (`2026`, `2027`, ..., `2030`).
- **Acessibilidade e Detalhes Preservados**: A identificação canônica estendida (ex: `01/2026`, `1º Trimestre`, `01/10`) permanece integralmente preservada para drilldown, tooltips (`Tooltip` / `.help()`) e identificação no modal de comentários.
- **Paridade Multiplataforma**: Implementado de forma unificada no Flutter (`cash_flow_engine.dart` e `cash_flow_view.dart`) e no Swift (`ImportersExporters.swift`, `Views.swift` no macOS e `iOSViews.swift` no iOS).

### 14. Otimização do Cabeçalho e Barra de Inserção Rápida no Extrato de Conta (`AccountLedger`)
- **Linha Unificada de Controles no Cabeçalho Desktop**:
  - Posicionada diretamente abaixo da linha de identificação da conta (nome e saldos), agrupando em uma única linha responsiva (`Wrap`):
    1. Seletor de mês/ano (`MonthYearPickerBar`).
    2. Botão de ajuste com rótulo simplificado para **"Previsões"** (`Icons.auto_fix_high`).
    3. Ícone de parâmetros do modo de abatimento (`Icons.tune`).
    4. Botão compacto para baixar CSV (`Icons.download` com largura mínima ajustada para `36px`).
    5. Botão compacto para baixar PDF (`Icons.picture_as_pdf` com largura mínima ajustada para `36px`).
    6. Campo de busca e filtro no mês (`"Filtrar no mês..."` com `width: 200px` e `height: 34px`).
  - Caso a janela seja redimensionada para larguras menores, os controles descem suavemente para uma segunda linha de forma fluida.
  - Para contas do tipo **Cartão de Crédito**, os detalhes e ações da fatura permanecem posicionados imediatamente abaixo da linha de controles.
- **Equalização dos Rótulos de Saldo do Cabeçalho**:
  - O rótulo `"Saldo Conciliado (Real)"` foi simplificado para **"Saldo atual"**.
  - O rótulo `"Previsto Final do Mês"` foi simplificado para **"Saldo previsto"** (mantendo `"Previsto (Fatura)"` em cartões de crédito).
- **Ajuste Espacial da Barra de Inserção Rápida**:
  - **Campo Data**: Largura otimizada para `118px` (anteriormente `142px`), com padding interno ajustado para aproximar o texto da data (`DD/MM/AAAA`) do ícone de calendário, eliminando o espaço vazio.
  - **Campo Modalidade**: Largura reduzida para `118px` (anteriormente `140px`), mantendo perfeita legibilidade de todas as opções.
  - **Campo Frequência**: Largura reduzida para `120px` (anteriormente `145px`).
  - **Campo Parcelas**: Largura reduzida para `88px` (anteriormente `100px`).

### 15. Persistência de Posição e Dimensões da Janela com Fallback Maximizado
- **Comportamento Implementado**:
  - **Gravação Automática**: Ao mover ou redimensionar a janela nas plataformas desktop (macOS e Windows), o sistema salva automaticamente a posição $(X, Y)$ e o tamanho $(L \times A)$, bem como o estado de maximização.
  - **Restauração Inteligente**: Ao reabrir a aplicação, a janela é restaurada com exatidão nas últimas coordenadas e dimensões salvas, validando que a área permaneça dentro dos limites do monitor conectado.
  - **Fallback Maximizado**: Na primeira execução (ou caso não haja coordenadas salvas válidas), o aplicativo continua abrindo automaticamente maximizado ocupando o espaço visível útil da tela (`visibleFrame` no macOS ou `SW_MAXIMIZE` no Windows).
- **Implementação por Plataforma**:
  - **Flutter macOS**: Configurado no `MainFlutterWindow.swift` através do mecanismo nativo de AppKit `setFrameAutosaveName("OpenMoneyMainWindow")` e verificação `setFrameUsingName`.
  - **Flutter Windows**: Implementado no `win32_window.cpp` com persistência de `WINDOWPLACEMENT` via Windows Registry (`Software\OpenMoney\WindowPlacement`) e fallback `ShowWindow(..., SW_MAXIMIZE)`.
  - **Swift macOS**: Integrado de forma 100% nativa com o gerenciador de janelas do AppKit/macOS via `frameAutosaveName`. Na inicialização, detecta se já há frame salvo no sistema; em caso afirmativo, permite a restauração nativa instantânea sem nenhum salto ou expansão forçada. Se não houver frame prévio (primeira inicialização), abre maximizado ocupando o `visibleFrame` e registra o estado inicial.

### 16. Central Unificada de Importação / Exportação e Simplificação da Barra Lateral
- **Remoção de Itens Avulsos da Barra Lateral**:
  - Removidos do menu lateral esquerdo os itens `Importar Carteira (CSV)`, `Importar Comprovantes (OCR)` e `Importar do Celular (.json)`.
  - Mantido um único ponto focal de entrada no menu: **`Importação / Exportação`** (proporcionando melhor legibilidade e evitando quebras de linha na barra lateral).
- **Novo Fluxo Operacional Sem Atrito (Zero Caminho Manual)**:
  - Eliminados os campos de texto manuais de caminho de arquivo e botões intermediários como "Procurar Arquivo (Finder)" ou "Definir Destino".
  - O clique direto em botões como `Importar Lançamentos (CSV)...` ou `Importar QIF...` abre imediatamente a caixa de seleção nativa do sistema (`NativeFilePicker.pickFile`), processando o arquivo e exibindo o resumo instantaneamente.
  - O clique em `Exportar Lançamentos (CSV)...` abre diretamente o diálogo nativo para salvar (`NativeFilePicker.saveFile`) com sugestão automática de nome semântico.
- **Filtros Avançados de Exportação**:
  - **Filtro de Contas**: Suporte a exportação de Todas as Contas ou de uma Conta Específica.
  - **Filtro de Período**: Suporte a três modos (Todo o período, Apenas o mês selecionado via `MonthYearPickerBar` e Intervalo customizado com Data Inicial e Data Final via date picker).
  - **Contador em Tempo Real**: Badge informativo calculando dinamicamente a quantidade de lançamentos correspondentes aos filtros antes da confirmação.
- **Integração das Rotinas Especializadas**:
  - Cards dedicados dentro da aba *Importar Dados* no Desktop (ocultados na versão Web por serem exclusivos para ambiente Desktop), ordenados prioritariamente:
    1. `Importar do Celular (openmoney_inbox.json)`
    2. `Importar Comprovantes por OCR (Imagens e PDFs)`
    3. `Importar da Carteira (Atalhos iOS CSV)`
  - Seguidos pela seção do Catálogo de Categorias e Subcategorias.

---

## Consequências

- **Consistência Visual Estrita**: Experiência 100% idêntica entre macOS (nativo Swift), iOS (nativo Swift), macOS (Flutter) e Windows (Flutter).
- **Maior Agilidade Operacional**: Redução do número de cliques ao cadastrar lançamentos na conta em que o usuário já se encontra.
- **Privacidade Instantânea**: Facilidade para ocultar patrimônio e previsões em apresentações ou ambientes compartilhados.
- **Cobertura de Testes**: Garantia de regressão zero com 100% dos testes unitários e de integração aprovados em ambas as stacks.
