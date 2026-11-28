# ❓ Perguntas Frequentes (FAQ) — OpenMoney

Este documento reúne, em um único lugar, as respostas para as dúvidas mais comuns sobre o **OpenMoney** — desde os primeiros passos, contas, cartões, faturas, orçamentos, investimentos e multi-moeda até sincronização em nuvem, segurança, automações, Assistente IA e arquitetura interna.

> [!TIP]
> Use o **Índice** abaixo para ir direto ao tema que procura ou utilize a busca (`Cmd + F` / `Ctrl + F`) para localizar termos específicos. Cada resposta também traz links diretos para o manual ou decisão de arquitetura (ADR) correspondente.

---

## 📑 Índice

1. [Visão Geral, Plataformas, Instalação e Atualizações](#1-visão-geral-plataformas-instalação-e-atualizações)
2. [Primeiros Passos, Contas, Saldos e Personalização](#2-primeiros-passos-contas-saldos-e-personalização)
3. [Lançamentos, Edição, Recorrências, Parcelamentos e Transferências](#3-lançamentos-edição-recorrências-parcelamentos-e-transferências)
4. [Cartão de Crédito e Gestão de Faturas](#4-cartão-de-crédito-e-gestão-de-faturas)
5. [Categorias, Tags (#tags), Previsões Orçamentárias e Limite de Gastos](#5-categorias-tags-tags-previsões-orçamentárias-e-limite-de-gastos)
6. [Agenda Financeira, Vencimentos, Fluxo de Caixa, Relatórios e Gráficos](#6-agenda-financeira-vencimentos-fluxo-de-caixa-relatórios-e-gráficos)
7. [Carteira de Investimentos (Ações, FIIs, Renda Fixa, Tesouro e Cripto)](#7-carteira-de-investimentos-ações-fiis-renda-fixa-tesouro-e-cripto)
8. [Multi-Moeda, Câmbio e Cotações Históricas](#8-multi-moeda-câmbio-e-cotações-históricas)
9. [Importação, Exportação, Conciliação OFX, OCR e Coletor Mobile](#9-importação-exportação-conciliação-ofx-ocr-e-coletor-mobile)
10. [Sincronização na Nuvem (OpenMoney Cloud — Sync v2), Modo Híbrido e Múltiplas Contas](#10-sincronização-na-nuvem-openmoney-cloud--sync-v2-modo-híbrido-e-múltiplas-contas)
11. [Assistente Financeira com IA & Servidor MCP Remoto](#11-assistente-financeira-com-ia--servidor-mcp-remoto)
12. [Segurança, Privacidade, Autofill, Passkeys, Biometria, Backups e Recuperação](#12-segurança-privacidade-autofill-passkeys-biometria-backups-e-recuperação)
13. [Atalhos de Teclado e Dicas Rápidas](#13-atalhos-de-teclado-e-dicas-rápidas)
14. [Perguntas Técnicas e de Arquitetura (Para Desenvolvedores e Administradores)](#14-perguntas-técnicas-e-de-arquitetura-para-desenvolvedores-e-administradores)

---

## 1. Visão Geral, Plataformas, Instalação e Atualizações

### O que é o OpenMoney? Ele é gratuito e open source?
Sim. O **OpenMoney** é um aplicativo de gestão financeira pessoal e patrimonial de código aberto (licença **MIT**), inspirado no rigor contábil do clássico *Microsoft Money 99* com interface moderna (*Liquid Glass* e *Flat Clean*). Ele funciona sem mensalidades obrigatórias, sem telemetria e com total soberania dos seus dados: você pode usar 100% offline com um arquivo local `openmoney.json` ou sincronizar em tempo real pelo **OpenMoney Cloud (Sync v2)**.

### Em quais plataformas o OpenMoney funciona? O que aconteceu com a versão antiga em Swift?
O OpenMoney opera em **código único unificado em Flutter / Dart**, atendendo nativamente:
- **macOS** (`arm64` / Apple Silicon e `x64` / Intel)
- **Windows** (`x64`)
- **Web PWA** ([openmoney.app.br](https://openmoney.app.br))
- **Mobile** (iOS/iPadOS e Android, além da experiência responsiva via PWA)

A antiga stack nativa em Swift (macOS/iOS) foi congelada e **descontinuada oficialmente na `v2.5.0`** para unificar toda a evolução funcional e visual na base Flutter ([ADR 029](../adr/029-swift-deprecation-and-flutter-single-stack-unification.md)).

### Como instalar o OpenMoney no macOS, no Windows e acessar pela Web?
- **macOS (Terminal):**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.sh | bash
  ```
- **Windows (PowerShell):**
  ```powershell
  irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex
  ```
- **Windows (Prompt / CMD):**
  ```cmd
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.bat -o install.bat && install.bat
  ```
- **Web (sem instalar):** Acesse [https://openmoney.app.br](https://openmoney.app.br) no navegador ou adicione à Tela de Início do celular como PWA.

Os pacotes `.zip` oficiais também estão disponíveis na tabela de downloads do [README principal](../../README.md).

### O macOS exibiu *"OpenMoney está danificado e não pode ser aberto"*. O que fazer?
Esse aviso pode ocorrer quando o `.zip` é baixado manualmente pelo navegador porque o pacote aberto ainda não é notarizado pela Apple. Execute uma única vez no Terminal:
```bash
xattr -cr /Applications/OpenMoney.app
```
Instalações via script (`install.sh`) e atualizações feitas pelo próprio aplicativo já tratam isso automaticamente.

### Como funciona o versionamento por data (CalVer) e a atualização automática?
O OpenMoney usa **CalVer (`YYYY.M.D+BUILD`)**, por exemplo `v2026.11.27 (Build 188)` ([ADR 038](../adr/038-calver-date-versioning-and-release-automation.md) e [Guia de Atualizações](guia-atualizacao-e-versionamento.md)):
- **Ano, Mês e Dia (`2026.11.27`):** indicam a data exata da publicação.
- **Build (`+188`):** contador sequencial que desempata múltiplos lançamentos no mesmo dia.
- **No Desktop:** o app verifica atualizações silenciosamente ao abrir ou sob demanda em **OpenMoney > Buscar Atualizações...** / **Ajuda > Buscar Atualizações...** (ou em **Ajustes & Personalização**). Ao clicar em **Instalar e Reiniciar** (ou **Atualizar Agora**), o pacote é baixado com verificação `SHA-256`, instalado e reaberto automaticamente.
- **Na Web:** a atualização é instantânea a cada deploy no Cloudflare Pages — basta recarregar a página.

### Estou em uma versão antiga (`v2.5.8`), consigo atualizar normalmente? E se saírem duas atualizações no mesmo dia?
- **De `v2.x` para `v2026.x`:** **Sim.** O comparador avalia cada bloco numérico; como `2026 > 2`, a atualização automática funciona normalmente com 1 clique.
- **Duas atualizações no mesmo dia:** o número de **Build** sobe (ex.: `187` → `188`), permitindo detectar e instalar a nova compilação no mesmo dia.
- **Por que meses e dias menores que 10 não têm zero à esquerda (`2027.1.5` em vez de `2027.01.05`)?** O `pubspec.yaml` do Dart/Flutter segue a norma *SemVer 2.0*, que exige inteiros sem zero à esquerda.

### Atualizar o aplicativo altera ou apaga meus lançamentos?
**Nunca.** A atualização substitui apenas o executável do programa. Sua base local (`openmoney.json`), seus backups em `.zip` e sua conta no OpenMoney Cloud permanecem 100% intactos.

### Quais são as diferenças entre a versão Desktop e a versão Web?
A versão Web ([openmoney.app.br](https://openmoney.app.br)) opera exclusivamente no **Modo Online (Sync v2)** e oculta recursos dependentes do sistema de arquivos local, como o seletor de modo *Local*, o gerenciador de arquivos de backup locais no disco (na Web os backups ficam na nuvem por 15 dias), o OCR nativo de pastas de recibos e a verificação de atualizações de executável. Veja o comparativo completo em [Guia de Sincronização Cloud](guia-sincronizacao-cloud.md).

---

## 2. Primeiros Passos, Contas, Saldos e Personalização

### Quais tipos de conta o OpenMoney suporta?
São 7 tipos oficiais:
- **Corrente:** movimentação bancária diária, PIX, transferências e pagamentos.
- **Poupança**, **Caixinha** e **Cofrinhos:** reservas de liquidez imediata (agrupadas no card *Investimentos & Poupança* no Dashboard e consideradas na liquidez imediata, sem compor o caixa livre de corretoras).
- **Investimento:** contas de corretoras e custódia de ativos (opera em conjunto com o módulo **Investimentos**).
- **Dinheiro:** carteira física e gastos em espécie.
- **Cartão de crédito:** controle de limite, fechamento, vencimento, faturas e pagamentos parciais/adiantamentos.

### Qual é a diferença entre **Saldo Real** e **Saldo Previsto**?
- **Saldo Real:** soma apenas os lançamentos já marcados como **Conciliados (`✓`)** até a data considerada — é o valor que deve bater exatamente com o extrato real do banco.
- **Saldo Previsto:** inclui o Saldo Real mais todos os lançamentos **pendentes** (não conciliados), agendamentos, parcelas e previsões do período.

### O que significa marcar um lançamento como **Conciliado (`✓`)**?
Conciliar significa confirmar que aquele lançamento já foi efetivado/compensado no extrato real do seu banco ou na fatura do cartão. Você pode conciliar com 1 clique no ícone circular da linha, em lote na tela de **Lançamentos**, na **Agenda**, em **Vencimentos** ou automaticamente via importação **OFX**.

### Por que não consigo excluir uma conta? Como desativar/arquivar e reativar?
Para proteger a integridade histórica dos relatórios e do fluxo de caixa, o OpenMoney **bloqueia a exclusão física de qualquer conta que possua lançamentos**.
- Para parar de usar uma conta antiga, clique em **Desativar (Arquivar)** com 1 clique: todo o histórico é preservado nos relatórios, mas ela deixa de aceitar novos lançamentos e vai para a seção **Contas Inativas** (podendo ser reativada a qualquer momento).
- Somente contas com **0 lançamentos** podem ser excluídas definitivamente.

### Como funcionam Contas Favoritas, grupos recolhíveis, reordenação, Negócio (`PF`/`PJ`) e Logos Bancários?
- **Favoritas (★):** marque "Favoritar conta" no cadastro/edição para fixá-la no grupo **Favoritas** no topo da barra lateral e no card *Contas* do Dashboard.
- **Grupos recolhíveis:** clique no título de **Favoritas**, **Contas Ativas** ou **Contas Inativas** para recolher/expandir; o estado é salvo automaticamente.
- **Reordenação:** arraste e solte ou use o menu de contexto para reordenar suas contas; a mesma ordem é respeitada no Dashboard.
- **Negócio (`PF`/`PJ`):** associe contas a entidades de negócio para filtrar Fluxo de Caixa e Relatórios separadamente.
- **Logos Bancários:** escolha o logotipo oficial do banco/instituição com busca rápida por nome ([ADR 030](../adr/030-batch-edit-categories-quick-actions-transfer-autofill-and-logo-picker.md)).

### Como personalizar a aparência, o Dashboard e os extratos?
Abra **Ajustes & Personalização** (`Cmd + ,` no Mac / `Ctrl + ,` no Windows) — veja todos os detalhes no [Guia do Dashboard e Personalização](guia-dashboard-e-personalizacao.md):
- **Design & Tema:** alterne entre modo **Claro/Escuro**, escolha uma das **6 paletas de cor de destaque** (*Azul Oceano*, *Esmeralda*, *Índigo*, *Sunset Laranja*, *Ciano Futurista* e *Titanium Slate*) e ajuste o zoom/densidade.
- **Barra Lateral:** alterne entre expandida e **Mini Rail** (`Cmd/Ctrl + B`).
- **Dashboard Geral:** ative/desative e reordene qualquer card (*Patrimônio*, *Contas*, *Investimentos*, *A Pagar*, *A Receber*, *Faturas de Cartão*, *Gastos por Categoria*, *Ações Rápidas*, *Insights IA*), oculte contas/investimentos/faturas zeradas e use o ícone de **olho** individual em cada card para privacidade de valores.
- **Extratos:** alterne entre **Lista Diária** e **Datagrid Contínua** (`Cmd/Ctrl + D`), escolha ordenação padrão crescente ou decrescente (ou clique na coluna **DIA**), e opcionalmente oculte a barra de inserção rápida inline (substituída por um botão circular `+` no cabeçalho).

---

## 3. Lançamentos, Edição, Recorrências, Parcelamentos e Transferências

### Como funciona o autocompletar inteligente de favorecidos? Por que previsões não aparecem?
Ao digitar no campo **Descrição / Favorecido**, o OpenMoney sugere entradas anteriores e preenche automaticamente a **última categoria** e o **tipo** (Despesa ou Receita) usados para aquele favorecido ([ADR 032](../adr/032-payee-suggestion-filters-and-configurable-scope.md)):
- **Filtro por tipo:** em modo *Despesa*, sugere apenas despesas; em modo *Receita*, apenas receitas.
- **Escopo configurável em Ajustes:** por padrão preenche apenas *Nome e Categoria* (mantendo a conta que você já escolheu), mas você pode mudar para *Nome, Categoria e Conta* e ajustar a janela de histórico (30, 60, 90 dias [padrão], 6 meses, 1 ano ou todo o histórico).
- **Exclusão de previsões:** lançamentos iniciados com `Previsão` são excluídos automaticamente do autocompletar para não poluir sugestões do dia a dia ([ADR 034](../adr/034-date-validation-range-warnings-and-prediction-payee-exclusion.md)).

### Posso fazer contas matemáticas no campo de valor? Como funciona a máscara de data?
- **Avaliação matemática e mini calculadora:** sim! Você pode digitar expressões como `10 + 10`, `150 / 3` ou `80,50 * 2` diretamente no campo de valor e pressionar `Enter` ou sair do campo para calcular automaticamente, ou clicar no ícone de calculadora para abrir a **mini calculadora integrada** ([ADR 033](../adr/033-csv-opening-balance-accounts-auto-date-calculator.md)).
- **Máscara automática de data:** basta digitar os 8 dígitos (ex.: `27112026`) que as barras `/` são inseridas automaticamente (`27/11/2026`), inclusive ao colar datas. No celular, tocar em campos de Data ou Valor abre diretamente o **teclado numérico**.

### Por que o aplicativo bloqueia datas inválidas ou pede confirmação para datas antigas/muito futuras?
Para evitar erros de digitação acidentais ([ADR 034](../adr/034-date-validation-range-warnings-and-prediction-payee-exclusion.md)):
- Datas inexistentes no calendário (ex.: `31/02/2026`, `31/04/2026`, `29/02/2025`) são bloqueadas no salvamento.
- Datas **anteriores a mais de 30 dias** ou **posteriores a mais de 12 meses** exibem um aviso visual e pedem confirmação (*"Corrigir Data"* ou *"Salvar Mesmo Assim"*).

### Como funcionam os lançamentos recorrentes e por quanto tempo eles são projetados?
Você pode criar recorrências nas frequências **Diário**, **Semanal**, **Quinzenal**, **Mensal**, **Bimestral**, **Trimestral**, **Semestral** ou **Anual**, com **data de término** ou por **tempo indeterminado**. O motor (`syncRecs`) projeta automaticamente:
- **Anual:** 5 anos (60 meses)
- **Semestral:** 4 anos (48 meses)
- **Trimestral:** 3 anos (36 meses)
- **Bimestral e Mensal:** 2 anos (24 meses)
- **Diário, Semanal e Quinzenal:** 1 ano (12 meses)

Ao navegar para meses mais distantes no futuro, novas ocorrências são materializadas sob demanda.

### Como funcionam compras parceladas e a edição/exclusão em série? Lançamentos conciliados são alterados?
- **Parcelamento:** divide o valor total em **2x até 120x** com ajuste exato de centavos (sem perda de arredondamento) e numeração automática `(1/N)` no favorecido.
- **Escopo de alteração/exclusão:** ao editar ou excluir um item de série (parcelado ou recorrente), o sistema pergunta se deseja aplicar a **Apenas este**, **Este e todos os futuros não conciliados** ou **Todos da série**.
- **Proteção absoluta:** lançamentos que já estão **conciliados (`✓`) nunca são alterados ou excluídos** por operações em série.

### Como funcionam Transferências Entre Contas e Transferências Recorrentes?
- Uma transferência cria um **par espelhado atômico** (débito na origem e crédito no destino ligados pelo mesmo `xfer`), mantendo neutralidade nos Relatórios de receitas/despesas.
- Editar data, valor ou excluir uma das pontas atualiza/remove automaticamente a outra ponta.
- **Transferências Recorrentes ([ADR 026](../adr/026-recurring-transfers-parity.md)):** permitem automatizar aportes mensais, mesadas ou reservas em qualquer frequência, com ou sem data de fim, e edição em série sincronizada nas duas contas. Consulte o [Guia de Lançamentos e Transferências Recorrentes](guia-lancamentos-e-transferencias-recorrentes.md).

### Posso copiar um lançamento ou movê-lo para outra conta?
- **Copiar como Novo:** cria um novo registro independente pré-preenchido com descrição (removendo sufixos de parcela `(x/y)`), categoria, nota e valor, inicializando a data com **hoje** e permitindo escolher outra conta ou modo (único, recorrente, parcelado). Não aparece para pagamentos automáticos de fatura (`auto == true`).
- **Mover de Conta:** na edição do lançamento, basta trocar a conta de destino. Ao mover para um cartão de crédito, a fatura (`ik`) é calculada automaticamente; ao mover de um cartão para conta corrente/dinheiro, o vínculo de fatura é removido. Em séries (`.forward`), todas as parcelas futuras não conciliadas acompanham a mudança.

### Como usar a tela consolidada **Lançamentos**, a **Pesquisa Global**, a **Edição em Massa** e a **Exclusão em Lote**?
- **Lançamentos (Consolidado):** reúne todas as contas com filtro de **Dia / Mês / Ano**, alternância **Por Data do Lançamento vs. Por Fatura/Pagamento** e filtros combináveis por Conta, Categoria, Tag, Tipo e Conciliação.
- **Pesquisa Global (`Cmd/Ctrl + Shift + F`):** busca simultaneamente por favorecido, categoria, nota, `#tag` e valor em toda a base e leva você direto ao registro com destaque visual.
- **Edição em Massa:** clique em **Selecionar** na tela *Lançamentos* para marcar múltiplos itens (lançamentos `FATURA AUTO` ficam bloqueados por segurança) e alterar em lote Nome, Categoria, Tags (*Adicionar*, *Substituir*, *Remover*), Notas, Valor, Data, Conta ou Conciliação. Veja o [Guia de Edição em Massa](guia-edicao-em-massa.md).
- **Exclusão em Lote:** disponível tanto via seleção múltipla quanto por **Período e/ou Conta** (menu *Lançamentos* ou *Arquivo*). Sempre exibe prévia estatística, preserva contas/categorias e gera **backup preventivo obrigatório** antes de remover.

### Como o OpenMoney ordena múltiplos lançamentos no mesmo dia?
Cada lançamento guarda um carimbo temporal de criação (`createdAt`). Novos lançamentos na mesma data são posicionados na linha imediatamente abaixo dos anteriores, mantendo ordem cronológica estável sem saltos aleatórios.

---

## 4. Cartão de Crédito e Gestão de Faturas

### Como o OpenMoney nomeia as faturas e decide em qual fatura cada compra entra?
No **Schema `v: 7`** ([ADR 001](../adr/001-schema-v7-adoption.md)), toda fatura é identificada pelo **mês da sua data de vencimento** (`dueDay`), seguindo o padrão bancário:
- Se `dueDay <= closeDay` (ex.: fecha dia 23 e vence dia 03 do mês seguinte): compras de 24/09 a 23/10 vencem em 03/11 e pertencem à **Fatura de Novembro (`11/2026`)**.
- Se `dueDay > closeDay` (ex.: fecha dia 05 e vence dia 12 do mesmo mês): compras até 05/11 pertencem à **Fatura de Novembro (`11/2026`)**.

### O que acontece entre o fechamento e o vencimento da fatura?
- **Abertura automática na fatura pendente (`defaultInvoiceForAccount`):** se a fatura anterior já fechou, ainda está dentro do prazo até o vencimento (`closeDate <= hoje <= dueDate`) e tem saldo em aberto, ao abrir a conta do cartão o app posiciona você diretamente nessa fatura fechada para facilitar conferência e pagamento ([ADR 003](../adr/003-is-vigente-invoice-strategy.md)).
- **Sem rolagem prematura:** enquanto `hoje <= dueDate`, o pagamento automático programado evita que o saldo da fatura fechada seja somado indevidamente ao mês seguinte.

### Por que compras feitas após o fechamento começam como não conciliadas?
Quando há uma fatura anterior fechada e ainda em aberto, novas compras lançadas para a fatura posterior iniciam automaticamente como **não conciliadas (`rec = false`)**. Isso preserva o **Saldo Real** da fatura fechada até que ela seja paga.

### Posso escolher manualmente outra fatura para uma compra?
**Sim.** Tanto na barra de inserção rápida quanto na criação/edição do lançamento em cartão, há o **seletor manual de fatura** (*Override*) para alocar a compra em uma fatura anterior ou futura ([ADR 028](../adr/028-quick-entry-invoice-selector-parity.md)).

### Como fazer pagamento parcial ou adiantamento de fatura?
Use o botão **Pagar / Adiantar...** no cabeçalho da fatura:
1. Escolha a conta corrente de débito, a data e o valor (há o atalho **Preencher Saldo Restante**).
2. O motor `syncCards` consolida todas as compras e pagamentos parciais vinculados à fatura (`ik`) e ajusta automaticamente o lançamento agendado no vencimento para cobrar **apenas o saldo restante** ([ADR 004](../adr/004-card-invoice-settlement.md)).
3. Se você quitar 100% da fatura antecipadamente, a cobrança automática no vencimento é removida e a fatura recebe o status verde **LIQUIDADA**.

### Como imprimir ou exportar a Fatura do Cartão e o Extrato Mensal em PDF?
- **Cartão de Crédito:** clique em **Fatura PDF** no cabeçalho do cartão ou na janela de pagamento. O PDF A4 vetorial traz cabeçalho com fechamento/vencimento, cards KPI (*Compras*, *Pagamentos*, *Saldo a Pagar*, *Situação*), ícone de conciliação antes da data, notas em segunda linha e valores sem quebra.
- **Outras Contas:** clique em **Extrato PDF** no cabeçalho para gerar o extrato mensal A4 com saldo inicial/final (Real e Previsto) e saldo acumulado por quebra diária.

---

## 5. Categorias, Tags (`#tags`), Previsões Orçamentárias e Limite de Gastos

### Como funcionam Categorias e Subcategorias? Por que não consigo excluir uma categoria em uso?
As categorias são organizadas em 2 níveis (`Categoria Principal › Subcategoria`), separadas em **Despesas** e **Receitas**:
- **Exclusão protegida:** se uma categoria possuir lançamentos vinculados, o sistema impede a exclusão direta e abre a tela de **substituição assistida** para reclassificar todos os registros para outra categoria sem deixar lançamentos órfãos.
- **Bloqueio de categoria (`blocked`):** oculta a categoria de novos lançamentos mantendo todo o histórico antigo intacto (bloquear a categoria pai propaga o bloqueio às subcategorias).
- **Detalhamento:** clique no botão **Lançamentos** ou na pílula de contagem de qualquer categoria para auditar, filtrar, editar ou exportar seus lançamentos em CSV.

### Para que serve a opção "Considerar nos relatórios" (`includeInReports`)?
Cada categoria possui duas opções independentes de visibilidade (ambas marcadas por padrão):
- **Incluir nos Relatórios:** controla se a categoria aparece nos totais de receitas e despesas dos **Relatórios** e do módulo **Gráficos** (ideal para ocultar movimentações neutras de patrimônio).
- **Incluir no Fluxo de Caixa:** controla se a categoria entra na matriz do **Fluxo de Caixa**. Assim, você pode manter categorias históricas ocultas dos Relatórios, mas visíveis no Fluxo para compor o saldo acumulado, ou desmarcar ambas em categorias de ajuste técnico (como migração de saldo antigo de corretora).

### O que são e como usar Tags (`#tags`)?
Tags são etiquetas transversais (ex.: `#Viagem`, `#Reembolso`, `#Trabalho`) que complementam as categorias ([Guia de Tags](guia-tags.md) e [ADR 023](../adr/023-tags-and-batch-transaction-editing.md)):
- **Criar/vincular:** na tela dedicada **Tags** (no menu lateral) ou digitando no campo **Tags** do lançamento e pressionando `,` ou `Enter`.
- **Onde filtrar:** nos extratos (chips na linha), na tela consolidada **Lançamentos** (filtro dedicado *Tag*), na **Pesquisa Global** e nos **Relatórios** (mensal e anual).
- **Gerenciamento:** na tela **Tags**, clicar em uma tag abre todos os lançamentos vinculados; você também pode renomear ou excluir tags em massa.

### O que são Previsões Orçamentárias e como funciona o botão "Ajustar"?
Previsões são reservas prévias de teto de gastos no mês (lançamentos com prefixo `Previsão`, ex.: *Previsão Mercado*). Gerencie todas na tela **Planejamento › Previsões** ([Guia de Gestão de Previsões](guia-gestao-de-previsoes.md) e [ADR 020](../adr/020-predictions-management-view-and-zero-balance-retention.md)):
- **Modos de abatimento (`predMode`):** em *Ajustes & Personalização*, escolha **Por Mês** (abate gastos reais pela data do lançamento) ou **Por Fatura** (abate gastos bancários pela data e compras de cartão pela competência da fatura — [ADR 010](../adr/010-smart-predictions-offset-modes.md)).
- **Horizonte de meses (`predMonths`):** configurável para 1, 2, 3 (padrão), 6 ou 12 meses consecutivos a partir do mês atual real.
- **Sem dedução duplicada:** a base original fica salva na nota (`[Previsão base: R$ X,XX]`), permitindo clicar em **Ajustar** quantas vezes quiser no mês.
- **Previsão esgotada (`R$ 0,00` + `ESGOTADA`):** quando os gastos atingem ou superam o teto, a previsão **não é apagada** — ela vai para `R$ 0,00` com a tag `ESGOTADA` para manter o histórico e o drill-down dos gastos. Previsões já zeradas (`R$ 0,00`) não são recalculadas automaticamente nas execuções seguintes; use **Restaurar Teto** se quiser reativá-la manualmente.

### Como funciona o Limite de Gastos Mensal e o Alerta Preventivo de Orçamento?
Na tela **Limite de Gastos**, você define tetos mensais por categoria de despesa (categorias principais somam automaticamente os limites e gastos das subcategorias):
- **Alerta Preventivo ([ADR 021](../adr/021-budget-limit-verification-on-transaction-entry.md)):** ao lançar ou copiar uma despesa real (excluindo transferências e previsões), o OpenMoney verifica o acumulado real do mês na categoria — ou herda o teto da categoria pai se a subcategoria não tiver limite próprio. Em parcelamentos, considera o impacto da 1ª parcela. Se ultrapassar o limite, exibe um alerta detalhado (*Limite de Gastos Excedido*) permitindo **Cancelar** ou **Continuar**. Veja o [Guia de Limite de Gastos](guia-limite-de-gastos-e-alertas.md).

---

## 6. Agenda Financeira, Vencimentos, Fluxo de Caixa, Relatórios e Gráficos

### Como funciona a Agenda Financeira? Alterações lá afetam dados reais? Funciona offline?
A **Agenda** reúne contas a pagar, receitas previstas e faturas de cartão (agrupadas no dia do vencimento) em um calendário mensal ([Guia da Agenda Financeira](guia-agenda-financeira.md)):
- **Afeta dados reais?** **Sim**, com segurança total: marcar como pago/recebido, pagar fatura ou criar lançamentos pelo botão `+` do dia aplica exatamente as mesmas regras contábeis, auditoria e Sync v2 do restante do app.
- **Parcelas no cartão:** cada parcela aparece consolidada dentro da fatura do seu mês de vencimento.
- **Offline:** funciona 100% offline; no modo Online, sincroniza assim que houver conexão.
- **Impressão:** gera PDF em **1 única página A4 horizontal (paisagem)**.

### Como funciona a Central de Contas a Pagar & Receber (Vencimentos)?
Acessível pelo menu lateral ou `Cmd + Option + 5`, lista pendências não conciliadas classificadas por urgência (`ATRASADO`, `HOJE`, `EM X DIAS`) conforme a janela de antecedência configurável (1 a 30 dias; padrão **3 dias**). No Desktop/Mobile nativo, conta com notificações locais matinais às 08:30 e badge dinâmico no ícone do app, além de conciliação em 1 clique e botão *Ver* que leva direto ao lançamento no extrato.

### Qual é a diferença entre **Fluxo de Caixa** e **Relatórios**?
- **Relatórios (Mensal / Anual):** focam em desempenho de receitas e despesas. **Excluem** transferências entre contas, pagamentos automáticos de fatura e categorias com *"Considerar nos relatórios"* desmarcado. Calculam a **Taxa de Poupança** (*Savings Rate*) e exportam em **1 página A4** ou CSV.
- **Fluxo de Caixa:** é uma matriz contábil completa (Diária, Mensal, Trimestral, Semestral ou Anual) que calcula `Saldo Anterior Acumulado` e `Saldo Final Acumulado` conciliando todas as contas selecionadas — incluindo **valor de mercado das contas de Investimento** (sem duplicar compras/vendas vinculadas `investOpId`), transferências parciais e conversão de contas estrangeiras (`USD`, `EUR`, etc.) pela **cotação atual** (enquanto receitas/despesas usam a taxa histórica do lançamento). Suprime transferências internas entre as contas do filtro ativo e suporta anotações na linha de saldo final (`comments`).

### Como funcionam o drill-down interativo e os filtros nos Relatórios e Fluxo de Caixa?
- **Drill-down:** clicar em qualquer categoria/subcategoria nos Relatórios ou em qualquer célula numérica da matriz do Fluxo de Caixa abre a lista exata de lançamentos que compõem aquele valor, com busca em tempo real, filtro de conciliação (*Todos*, *Conciliados*, *Pendentes*), edição direta e exportação CSV ([ADR 024](../adr/024-drill-down-reconciliation-filter-and-ui-cleanup.md)).
- **Filtros combináveis:** selecione *Todas as Contas*, múltiplas contas por checkbox, *Negócio* (`PF`/`PJ`), *Status de Conciliação* e *Tag* (nos Relatórios).

### O que oferece o módulo **Gráficos** (Analytics)?
O módulo **Gráficos** ([ADR 035](../adr/035-charts-dashboard-analytics.md)) usa `fl_chart` e o motor contábil `AnalyticsEngine` (100% alinhado aos Relatórios oficiais) com seletor **Tudo · Finanças · Investimentos**, filtros de período (*Mês*, *3M*, *6M*, *12M*, *Ano atual*, *Ano anterior*, *Todo período*) e status de conciliação. Inclui evolução de fluxo de caixa, **Reserva de Emergência (Runway)** com subindicador de **Liquidez imediata**, proventos mensais, alocação da carteira de investimentos, escada de vencimentos e insights automáticos.

---

## 7. Carteira de Investimentos (Ações, FIIs, Renda Fixa, Tesouro e Cripto)

### Quais classes de ativos a Carteira de Investimentos suporta?
O módulo **Investimentos** ([Guia de Investimentos](guia-investimentos.md) e [ADR 039](../adr/039-investment-portfolio-management.md)) suporta: **Ações**, **FIIs**, **ETFs**, **BDRs**, **Renda Fixa** (CDB, RDB, LC, LCI, LCA, Debêntures, CRI/CRA), **Tesouro Direto** e **Criptomoedas** (com suporte a até 8 casas decimais na quantidade e preenchimento bidirecional por *Preço Unitário* ou *Total da Operação*).

### Compras e vendas de ativos distorcem meus Relatórios mensais?
**Não.** Quando a opção *"Movimentar caixa da conta selecionada"* está marcada, compras usam a categoria `Transferência (-)` e vendas usam `Transferência (+)`. Por serem transferências, não inflam suas despesas nem suas receitas nos Relatórios ou orçamentos.

### Como funcionam Preço Médio, Proventos e IR Regressivo?
- **Preço Médio:** calculado automaticamente nas compras; a venda **não altera o Preço Médio de Compra** — ela apura o Lucro/Prejuízo Realizado e o Preço Médio de Venda.
- **Renda Fixa & Tesouro (IR Regressivo):** na venda/resgate de títulos tributados, o IR Retido na Fonte é pré-calculado em ordem **FIFO** pela tabela regressiva (`22,5%` até 180d, `20,0%` 181–360d, `17,5%` 361–720d, `15,0%` > 720d) e lançado em `Investimentos (-) › IR` (títulos isentos como LCI/LCA/CRI/CRA ficam zerados).
- **Proventos B3:** o botão **Proventos B3** consulta dividendos, JCP (já descontando 15% de IR) e rendimentos de FIIs anunciados na B3 pela posição na Data-Com e agenda na **Agenda** para a data de pagamento em `Investimentos (+) › Dividendos`.

### Preciso criar um ativo de Renda Fixa novo a cada aporte?
**Não**, se for o mesmo título (ex.: vários aportes no mesmo *Tesouro Selic 2029* ou *CDB Liquidez Diária 100% CDI*): lance todas as compras no mesmo ativo, pois o motor controla lote a lote pela data de cada aporte. Crie ativos separados apenas para títulos com emissor, taxa, indexador ou vencimento distintos.

### De onde vêm as cotações automáticas e como usar preço manual?
Ao clicar em **Cotações**:
- **Ações, FIIs, ETFs, BDRs:** Yahoo Finance (`.SA` B3 e exterior).
- **Tesouro Direto:** PU de Resgate oficial (`PU Venda`) no **Tesouro Transparente (Gov.br)** (basta o nome conter o tipo e o ano, ou preencher o campo Vencimento).
- **Cripto:** cadeia automática `Binance → Coinbase → Mercado Bitcoin → CoinGecko → AwesomeAPI → Yahoo Finance`.
- **Renda Fixa:** indicadores CDI, Selic, IPCA, série histórica diária do CDI (`BCB SGS 12`) e **calendário bancário oficial ANBIMA** (dias úteis exatos descontando feriados nacionais).
- **Preço Manual:** clique sobre o preço na coluna *Preço Atual* para editar manualmente (exibe badge `M`) ou selecione *"Voltar p/ Automático"* quando quiser.

### Como importar planilhas da B3 e controlar múltiplas corretoras?
- **Importar B3:** exporte o relatório de *Posição* ou *Movimentação* da Área do Investidor B3 em `.xlsx` ou `.csv`, clique em **Importar B3** e escolha a corretora de destino (com opção de converter o saldo atual em Posição Inicial para evitar dupla contagem).
- **Multi-Corretora:** a custódia fica vinculada a cada operação, permitindo ter o mesmo ticker (ex.: `PETR4`) na XP e na Rico com filtro individual por corretora e Preço Médio consolidado na visão geral.

### Como o saldo da conta de Investimentos aparece no Dashboard e no menu lateral?
O saldo exibido é **`Caixa Livre + Valor Atualizado Bruto dos Ativos`**. Sempre que as cotações são atualizadas, o saldo da conta e o **Patrimônio Líquido Total** são recalculados na hora. Para títulos tributados, o Valor Líquido Estimado e o IR Estimado são mostrados de forma complementar.

---

## 8. Multi-Moeda, Câmbio e Cotações Históricas

### Quais moedas são suportadas e como configurar a moeda padrão?
O OpenMoney suporta **11 moedas**: `BRL`, `USD`, `EUR`, `CAD`, `AUD`, `GBP`, `PYG` (sem centavos), `ARS`, `UYU`, `CHF` e `CLP` (sem centavos). Em **Ajustes & Personalização › Moedas & Cotações**, você define a **Moeda Base / Padrão** (`BRL` por padrão) usada para consolidar o Patrimônio e os Relatórios ([Guia Multi-Moeda](guia-multi-moeda-e-cambio.md) e [ADR 018](../adr/018-multi-currency-and-historical-rates.md)).

### Como o OpenMoney escolhe a cotação histórica de cada lançamento em moeda estrangeira?
As cotações do dia são atualizadas no máximo 1 vez a cada 24h via **AwesomeAPI** (apenas se houver conta estrangeira ativa, respeitando taxas travadas como `Manual`). Para lançamentos em conta estrangeira, a taxa (`Transaction.rate`, sempre normalizada para `BRL`) segue esta prioridade:
1. **Última transferência de câmbio** feita para aquela conta até a data do lançamento (preservando IOF/spread real).
2. **Cotação Oficial Histórica do Banco Central (Olinda PTAX)** da data (buscando até 7 dias úteis anteriores em fins de semana/feriados) com fallback AwesomeAPI.
3. **Cotação atual** cadastrada no sistema.

Você também pode editar a taxa livremente ou usar os chips de 1 clique (`Transf.`, `Buscar BCB`, `Atual`).

### Como funcionam transferências entre contas de moedas diferentes e a ferramenta "Corrigir Passados"?
- **Transferência Multi-Moeda:** permite editar o valor em ambas as moedas ou a taxa diretamente; se você ajustar o valor recebido (devido a IOF/tarifa), a taxa efetiva é recalculada e salva para servir de referência aos gastos futuros daquela conta.
- **Corrigir Passados:** em *Ajustes & Personalização › Moedas & Cotações*, percorre lançamentos passados (`data < hoje`) em moeda estrangeira (exceto transferências) e atualiza taxas antigas com a transferência da época ou PTAX histórica do Banco Central, registrando tudo no log de auditoria.

### Como valores estrangeiros aparecem nos Relatórios, Fluxo de Caixa e CSV?
- Ao filtrar apenas contas da mesma moeda estrangeira, a tabela exibe a moeda da conta e os cards mostram o equivalente `≈` na moeda padrão respeitando a taxa histórica individual de cada transação.
- Ao consolidar múltiplas moedas, tudo é convertido para a moeda base pela taxa histórica gravada em cada lançamento.
- A exportação **CSV (17 colunas)** preserva valor na moeda original, moeda padrão, valor convertido, taxa de câmbio e valores/taxas de contrapartida.

---

## 9. Importação, Exportação, Conciliação OFX, OCR e Coletor Mobile

### Quais formatos de arquivo o OpenMoney importa e exporta?
- **Importação:** CSV de lançamentos, CSV de Contas, CSV de Categorias, **QIF** (*Microsoft Money 99 / Quicken* com fallback `Windows CP1252 / Latin-1`), **OFX / QFX**, planilhas B3 (`.xlsx`/`.csv`), lote do celular (`openmoney_inbox.json`), recibos/faturas via OCR/IA e restauração de backup `.zip` / `.json`.
- **Exportação:** CSV de lançamentos (17 colunas + lançamento automático `SALDO INICIAL` quando diferente de zero, UTF-8 com BOM e `;` para abrir perfeito no Excel), CSV de Contas, CSV de Categorias, PDF A4 (Fatura, Extrato, Relatório Mensal, Agenda, Investimentos) e Backup Completo `.zip` / `.json`.

Consulte o [Guia de Importação e Exportação](guia-importacao-e-exportacao-csv-ofx.md).

### Como funciona a Conciliação Bancária e de Faturas via OFX?
Disponível no cabeçalho de qualquer conta, na Central de Importação ou pelo atalho `Cmd/Ctrl + Shift + O` ([Guia OFX](guia-conciliacao-bancaria-ofx.md) e [ADR 027](../adr/027-ofx-bank-and-invoice-reconciliation.md)):
- **Pareamento automático:** localiza lançamentos compatíveis, preserva sua descrição e categoria originais, marca como conciliado (`✓`) e grava o `FITID` do banco (permitindo reimportar o mesmo arquivo sem duplicar).
- **Novos lançamentos:** limpa prefixos bancários longos (mantendo o texto original na Nota), sugere categorias pelo histórico e detecta transferências entre suas contas cadastradas.
- **Conferência `LEDGERBAL`:** compara o saldo do arquivo OFX com o saldo projetado e permite criar um lançamento de ajuste com 1 clique se houver diferença residual.

### Como o sistema evita duplicidades e cria contas na importação CSV/QIF?
- Antes de inserir qualquer lançamento, o importador valida todas as contas citadas no arquivo, ignora nomes de cabeçalho e **cria automaticamente contas ausentes** inferindo o tipo pelo nome (*Cartão/Crédito*, *Poupança*, *Investimento*, *Dinheiro* ou *Corrente*).
- Por padrão, a verificação $O(1)$ de duplicidade (`conta|data|valor|favorecido`) ignora registros idênticos já existentes (há uma flag opcional para permitir duplicados caso desejado).

### Como funciona a Importação de Comprovantes via OCR Nativo e IA (Desktop)?
Disponível no macOS e Windows ([ADR 007](../adr/007-receipts-ocr-ai-import.md)): você seleciona uma pasta com comprovantes (PDF, PNG, JPG, JPEG, HEIC); o app extrai texto localmente via **Apple Vision / PDFKit** (macOS) ou **Windows.Media.Ocr** (Windows) e usa **Google Gemini Flash (BYOK)** para identificar Favorecido, Data e Valor Líquido em uma tela de conferência *Split View*, movendo os processados para a subpasta `processados/`.

### O que é o OpenMoney Coletor Mobile (PWA) e a automação com Atalhos do iOS / Apple Pay?
O **Coletor Mobile** ([coletor/](https://fsf77.github.io/openmoney-new/coletor/)) é um Web App offline focado em entrada rápida na rua sem risco de conflitos ou duplicação de `openmoney.json` no iCloud Drive ([ADR 008](../adr/008-coletor-smart-account-ios-automation.md)):
- Extrai apenas a estrutura leve (~20 KB) do seu `openmoney.json` (contas, categorias e até 1.000 favorecidos).
- Possui **OCR local em WebAssembly (Tesseract.js)** pela câmera do celular (nenhuma foto sai do aparelho).
- Integra-se com **Atalhos do iOS / Apple Wallet (Apple Pay)** via URL parametrizada (`?recibo=...`) usando **Resolução de Contas em 4 Níveis** (De-Para configurado → Sinônimos/Token Scorer → Memória do estabelecimento → Conta favorita/ativa).
- Exporta apenas os novos lançamentos no arquivo leve `openmoney_inbox.json` (~1–2 KB), que você importa no Desktop com `Cmd + Option + M` passando por uma janela de revisão visual com bloqueio de duplicatas.

---

## 10. Sincronização na Nuvem (OpenMoney Cloud — Sync v2), Modo Híbrido e Múltiplas Contas

### É obrigatório criar conta na nuvem? Qual a diferença entre Modo Local e Modo Online?
**Não é obrigatório.** No Desktop (macOS e Windows), você escolhe livremente:
- **Modo Local:** 100% offline sobre um arquivo `openmoney.json` no seu disco ou pasta de nuvem pessoal.
- **Modo Online (OpenMoney Cloud — Sync v2):** sincronização granular em tempo real por registro (`seq` incremental + WebSockets), com acesso pela Web (`openmoney.app.br`), Desktop e Mobile simultaneamente, sem sobrescrever edições feitas em aparelhos diferentes.

### Como alternar entre Modo Local e Modo Online, ou usar múltiplas contas Cloud?
- **Alternar Local ↔ Online:** no rodapé da barra lateral do Desktop, clique nas pílulas **💻 Local** ou **☁️ Online**.
- **Múltiplas Contas Salvas:** no painel **OpenMoney Cloud & Sincronização**, o card *Alternar entre Contas e Bases* permite trocar com 1 clique entre várias contas (ex.: Pessoal e Empresa), ordenar A–Z, conectar outra conta ou criar uma nova base na nuvem.

### O Modo Online funciona se a internet cair?
**Sim.** O Sync v2 mantém cache local isolado em disco (`cloud_cache/`) e uma fila offline resiliente (**Outbox**). Você continua lançando normalmente sem internet e tudo é sincronizado automaticamente assim que a conexão retorna.

### Posso salvar minha base local no iCloud Drive, Dropbox, Google Drive ou OneDrive?
**Sim.** Basta salvar ou mover (`Cmd + Shift + M`) seu arquivo `openmoney.json` para a pasta sincronizada desejada. No macOS, o OpenMoney usa *Security-Scoped Bookmarks* para manter permissão persistente de acesso e lista as últimas 10 bases abertas em **Arquivo › Abrir Recente**. *(Dica: evite abrir e editar o mesmo arquivo local simultaneamente em dois computadores ao mesmo tempo; para uso simultâneo multi-dispositivo, prefira o Modo Online Sync v2).*

### Como alterar meu e-mail da conta Cloud ou excluir minha base/conta com segurança?
- **Alterar e-mail:** em **Cloud & Sincronização › Configurações da Conta**, informe o novo e-mail e valide o código de 6 dígitos enviado para ele.
- **Exclusão segura (apenas dados da base ou conta definitiva):** exige digitar `"EXCLUIR"` em maiúsculas. Antes de apagar qualquer registro, o servidor gera automaticamente um **backup `.zip` com seu `openmoney.json` e envia para o seu e-mail via Resend**.

---

## 11. Assistente Financeira com IA & Servidor MCP Remoto

### Como ativar e usar a Assistente Financeira com IA integrada?
Em **Ajustes & Personalização › Assistente Financeira & IA**, ative a chave mestre **"Ativar Assistente Financeira & IA"** (se desativar, todos os botões, atalhos e o card de Insights somem da interface). Quando ativada:
- Abra com **`Cmd + J`** (macOS) / **`Ctrl + J`** (Windows/Web) ou pelo botão **`✨ Assistente IA`**.
- Use comandos em linguagem natural para lançar gastos, ler comprovantes/faturas (PDF ou foto), ou clique nos botões contextuais (*Explicar Variações*, *Raio-X da Fatura*, *Detectar Recorrências*, *Organizar Base*, *Analisar IA* em Previsões e *Análise de Investimentos*).
- No macOS e iOS, também há integração com **Siri e Atalhos da Apple** (`openmoney://?prompt=...`) e **Apple Intelligence Local** offline ([Guia da Assistente IA](guia-assistente-ia.md) e [ADR 030](../adr/030-ai-assistant-multi-provider-and-siri.md)).

### Qual a diferença entre "Minha Chave (BYOK)", "Nuvem Cloud" e "Modo Sem Chave"?
- **Minha Chave (BYOK):** usa sua própria chave de API (Google Gemini Flash, OpenRouter.ai, Anthropic Claude ou OpenAI ChatGPT) salva apenas localmente no aparelho.
- **Nuvem Cloud:** usa a infraestrutura gerenciada no Cloudflare (cota diária padrão de 25 consultas/dia, sem precisar configurar chaves externas, quando habilitada no servidor).
- **Modo Sem Chave (Prompt Bridge):** gera um resumo compacto e seguro para copiar e colar na versão web gratuita do ChatGPT, Claude ou Gemini e colar a resposta JSON de volta em cartões de confirmação.

### Como conectar o OpenMoney ao ChatGPT, Claude, Gemini, Cursor ou LM Studio?
Pelo **Servidor MCP Remoto** em `https://openmoney.app.br/api/mcp` ([Guia do Servidor MCP](guia-servidor-mcp-e-ia.md) e [ADR 036](../adr/036-mcp-remote-server-and-oauth2.md)):
- **Google Gemini, ChatGPT e Claude Web:** conectam com 1 clique via **OAuth 2.1**, abrindo a tela oficial de login do OpenMoney para autorizar.
- **Claude Desktop, Cursor, LM Studio e Custom GPTs:** gere um Bearer Token (`opm_live_...`) em **Ajustes & Personalização › Servidor MCP & Acesso Externo** (há botão pronto para copiar o JSON do Claude Desktop). Você pode revogar qualquer acesso com 1 clique na mesma tela.

### A IA pode apagar minha base inteira? Posso usar em modo somente leitura?
- **Pode apagar a base?** **Não.** O servidor MCP não expõe comandos para apagar contas, zerar saldos ou excluir a base; exclusões são sempre unitárias por ID de lançamento, e toda mutação externa fica marcada como **`[MCP Remoto]`** nos logs de auditoria.
- **Somente leitura:** **Sim**, ao autorizar OAuth ou gerar um token MCP, selecione o escopo **"Somente Leitura" (`read_only`)**.
- **E se o app estiver aberto quando a IA criar um gasto?** Pelo Sync v2 (WebSocket), o lançamento criado pela IA aparece automaticamente na tela do app em tempo real, sem conflitos.
- **Diferença entre Saldo Atual e Saldo Previsto informado pela IA:** *Saldo Atual do Dia (Conciliado)* considera apenas lançamentos conciliados até hoje (bate com o banco); *Saldo Previsto no Mês* projeta receitas a receber e contas/faturas pendentes até o fim do mês.

---

## 12. Segurança, Privacidade, Autofill, Passkeys, Biometria, Backups e Recuperação

### Como configurar Autofill, Chaves-senha (Passkeys) e Bloqueio Biométrico?
Consulte o [Guia de Autofill, Passkeys e Biometria](guia-autofill-passkeys-e-biometria.md) ([ADR 037](../adr/037-autofill-passkeys-webauthn-and-biometric-lock.md)):
- **Autofill:** compatível nativamente com 1Password, Bitwarden, Apple Chaves e Google Password Manager na Web, Desktop e Mobile.
- **Passkeys (WebAuthn / FIDO2):** acesse **Cloud & Sincronização › Configurações da Conta › Gerenciar Chaves-senha (Passkeys)** e clique em **+ Cadastrar Chave-senha neste Dispositivo**. Na Web, entra com 1 clique via Touch ID / Face ID / Windows Hello; no Desktop, usa o navegador padrão via *Desktop Session Bridge* automaticamente.
- **Bloqueio Biométrico ao abrir o app:** vem **desativado por padrão**. Ative em **Ajustes & Personalização › Geral & Inicialização** (exige confirmação biométrica prévia ao ativar).

### Como desativar o bloqueio biométrico? E se falhar ou eu perder/trocar de aparelho? Posso ter mais de uma Passkey?
- **Desativar bloqueio:** em *Ajustes & Personalização › Geral & Inicialização*, desmarque a opção (salvo no `config.json` local).
- **Se a biometria falhar:** o prompt nativo do sistema oferece fallback com a **senha/PIN da sua máquina**.
- **Se perder ou trocar de aparelho:** entre com seu **e-mail e senha** (ou recupere pelo código de 6 dígitos no e-mail) e cadastre a Passkey do novo aparelho.
- **Múltiplas Passkeys:** **sim**, você pode cadastrar várias chaves (ex.: Mac, PC Windows e iPhone) e remover chaves antigas a qualquer momento em *Cloud & Sincronização*.

### Como funcionam os Backups Automáticos locais e na nuvem? Por que o `.bak` foi descontinuado?
- **Fim do `.bak`:** o antigo `openmoney.json.bak` era sobrescrito a cada 350ms e poluía pastas de nuvem. Foi substituído por snapshots compactados `.zip` (~85–90% menores) em pasta isolada do aplicativo:
  - **macOS:** `~/Library/Application Support/OpenMoney/Backups/`
  - **Windows:** `%APPDATA%\OpenMoney\Backups\`
- **Retenção local:** gera até **4 snapshots diários** (no Modo Local e também para contas Online no Desktop!) com retenção mínima de **7 dias corridos** — e uma trava garante que nunca apaga snapshots se houver **7 ou menos arquivos** na pasta.
- **Retenção na nuvem (OpenMoney Cloud):** gera **3 a 4 snapshots por dia** com retenção automática de **15 dias**, restauráveis com 1 clique em **Cloud & Sincronização › Backups na Nuvem**.

### Como restaurar um backup ou recuperar quando o arquivo local não é encontrado?
- **Restaurar backup:** pressione **`Cmd + Shift + B`** (ou acesse *Arquivo › Backups de Segurança*) para restaurar snapshots `.zip` locais ou `.json` antigos com validação prévia em memória. No Modo Online, restaurar um backup sincroniza o estado restaurado para todos os dispositivos.
- **Arquivo local não localizado (`MissingDatabaseSheet`):** se o arquivo sumir (ex.: pendrive desconectado ou movido), o app **nunca cria uma base vazia por cima** — exibe uma tela de resgate com opções para *Localizar Arquivo...*, *Escolher dos Recentes...* ou *Criar Nova Base...*.

### O que é a Blindagem Anti-Wipe em 3 Camadas e para que servem os Logs de Auditoria?
- **Blindagem Anti-Wipe ([ADR 013](../adr/013-realtime-record-sync.md) e [ADR 014](../adr/014-desktop-hybrid-sync-audit-and-safety-backups.md)):**
  1. **Boot & Cache:** enquanto a base remota não carrega, exibe tela de carregamento (nunca tela zerada); caches locais vazios em contas já populadas (`revision > 1`) são descartados com retentativa de `forceFullPull`.
  2. **Cliente:** deltas pré-carga e gravações/compactações vazias suspeitas (`_isSuspiciousEmptyDb`) são bloqueados; desconectar da base local interrompe o `SyncEngine`.
  3. **Backend Cloudflare:** `PUT /api/db` bloqueia com `HTTP 409` qualquer payload `< 50 KB` sobre bases `chunked:*` sem `force=true`.
- **Logs de Auditoria:** registram criações, edições, exclusões, operações em lote, correções cambiais e ações de IA (`[MCP Remoto]`) na tabela `user_audit_logs` (retenção de 30 dias na nuvem) e em arquivo `.log` local no Desktop, visíveis em **Logs de Alterações**.

### Como meus dados são protegidos na nuvem?
- **Criptografia `AES-256-GCM`** com chaves derivadas por usuário (`HKDF-SHA256`).
- **Verificação 2FA por código de 6 dígitos** (validade de 15 min) no cadastro, recuperação de senha e troca de e-mail.
- **Hardening D1 ([ADR 015](../adr/015-web-and-d1-security-hardening.md)):** proteção anti-força-bruta, tokens de API armazenados apenas como hash `SHA-256` e isolamento estrito multi-tenant por `user_id`.

---

## 13. Atalhos de Teclado e Dicas Rápidas

| Atalho (macOS / Windows) | Ação |
| :--- | :--- |
| `Cmd + K` / `Ctrl + K` | Abrir **Command Palette** (busca e navegação rápida) |
| `Cmd + J` / `Ctrl + J` | Abrir / recolher **Assistente Financeira com IA** |
| `Cmd + ,` / `Ctrl + ,` | Abrir **Ajustes & Personalização** |
| `Cmd + D` / `Ctrl + D` | Alternar extrato entre **Lista Diária** e **Datagrid Contínua** |
| `Cmd + B` / `Ctrl + B` | Alternar barra lateral (**Expandida / Mini Rail**) |
| `Cmd + Shift + F` / `Ctrl + Shift + F` | **Pesquisa Global** em toda a base de dados |
| `Cmd + Shift + O` / `Ctrl + Shift + O` | **Conciliação Bancária / Fatura via OFX** |
| `Cmd + Option + 1..5` | **Fluxo de Caixa (`1`)**, **Relatórios (`2`)**, **Limite de Gastos (`3`)**, **Categorias (`4`)**, **Vencimentos (`5`)** |
| `Cmd + Option + I` / `Ctrl + Alt + I` | Central de **Importação / Exportação CSV** |
| `Cmd + Option + M` | Importar lançamentos do celular (`openmoney_inbox.json`) |
| `Cmd + Shift + B` | **Histórico de Backups** automáticos (`.zip`) |
| `Cmd + Shift + Q` | Importar arquivo **QIF** (*Microsoft Money 99*) |
| `Cmd + Shift + E` | Exportar backup completo (`.zip` / `.json`) |
| `Cmd + N` / `Cmd + O` / `Cmd + Shift + M` | Nova base local / Abrir base / Mover base |
| `Cmd + P` / `Cmd + ?` | Imprimir / Exportar PDF e Ajuda integrada |

### Como funcionam os ícones e cores das categorias? Posso personalizar?
Sim! Todas as categorias padrão já possuem ícones e cores automáticos e fáceis de identificar, que aparecem tanto na **escolha da categoria** (Novo Lançamento, Lançamento Rápido, OFX) quanto nas **telas de lançamentos** (Extratos, Todos os Lançamentos, Limite de Gastos).
- **Herança inteligente:** Subcategorias herdam o ícone e a cor da categoria principal por padrão, mas você pode alterá-los individualmente a qualquer momento.
- **Como alterar:** Em **Categorias**, edite a categoria ou subcategoria, toque em **Ícone e Cor** e escolha na biblioteca pesquisável em português (ou clique em **Automático / Herdar do Pai** para restaurar o padrão). Veja o passo a passo completo no [Guia de Dashboard e Personalização](guia-dashboard-e-personalizacao.md#7-%EF%B8%8F-ícones-e-cores-nas-categorias).

---

## 14. Perguntas Técnicas e de Arquitetura (Para Desenvolvedores e Administradores)

### Qual é o padrão oficial do Schema (`v: 7`) e por que os valores são armazenados em centavos inteiros?
Todos os valores monetários (`amt`, `opening`, `budgets`, `minBalance`) são armazenados como **inteiros na menor unidade da moeda** para eliminar imprecisões de ponto flutuante binário (IEEE-754). A especificação completa de todos os campos locais (`openmoney.json`), DTOs, chaves de persistência e tabelas D1 está no [Dicionário de Dados Completo](../architecture/dicionario-de-dados.md) e no [Compilado de Engenharia](../architecture/compilado-do-sistema.md).

### Como o Sync v2 persiste cache e fila offline no dispositivo?
- **Desktop e Mobile nativo ([ADR 025](../adr/025-sync-kv-store-local-persistence.md)):** metadados leves (`seq`, `outbox`) ficam em `sync_kv_store.json`; snapshots por conta ficam isolados em `cloud_cache/<key>.json` gravados de forma atômica (`.tmp.<pid>` + `renameSync`); preferências/credenciais ficam em `config.json`.
- **Web:** utiliza `window.localStorage`.

### Como funciona o backend serverless da Cloudflare?
Documentado no [Diagrama da Arquitetura Flutter](../architecture/diagrama-arquitetura-flutter.md) e nos [ADRs 011](../adr/011-web-multiuser-cloudflare-architecture.md), [013](../adr/013-realtime-record-sync.md) e [015](../adr/015-web-and-d1-security-hardening.md):
- **Cloudflare Pages Functions (`functions/api/[[route]].js`):** API REST de autenticação, snapshots Gzip, backups, logs, proxy CORS de mercado (`/api/market/quotes`, `/api/market/indicators`), IA gerenciada (`/api/ai/capabilities`, `/api/ai/chat`) e Servidor MCP (`/api/mcp`).
- **Cloudflare D1:** SQLite distribuído com tabelas de usuários, registros delta (`user_sync_records`), snapshots (`user_databases`), auditoria (`user_audit_logs`), passkeys (`user_passkeys`, `passkey_challenges`, `passkey_desktop_sessions`) e cotas de IA (`user_ai_usage`).
- **Cloudflare Durable Objects (`cloudflare/sync-worker/`):** `UserSyncRoom` mantém conexões WebSocket por usuário para broadcast instantâneo de deltas em tempo real.

### Como funcionam o Servidor MCP Remoto e o OAuth 2.1?
Implementa **Streamable HTTP (`POST /api/mcp`, JSON-RPC 2.0, `protocolVersion: "2025-03-26"`)** com autodescoberta **RFC 9728** (`/.well-known/oauth-protected-resource/api/mcp`), **RFC 8414 / OIDC Discovery**, **Dynamic Client Registration (RFC 7591)**, **PKCE `S256`** e mitigação **RFC 9207 (`iss`)**. Veja o catálogo completo das 12 ferramentas MCP no [Guia do Servidor MCP](guia-servidor-mcp-e-ia.md) e no [ADR 036](../adr/036-mcp-remote-server-and-oauth2.md).

### Como os testes automatizados evitam alterar minha base ou `config.json` real?
O `MoneyStore` e a camada de I/O nativo (`platform_io_native`) detectam `Platform.environment['FLUTTER_TEST']` e redirecionam automaticamente o diretório de suporte para uma sandbox temporária (`OpenMoney_Test_Support`), garantindo isolamento total da máquina de desenvolvimento ([ADR 031](../adr/031-test-environment-storage-isolation-and-config-guard.md)).

### Como compilar, testar e publicar releases oficiais?
```bash
# 1. Dependências, análise estática e testes
flutter pub get
flutter analyze
flutter test

# 2. Publicar macOS & Web (define versão CalVer YYYY.M.D e incrementa +BUILD)
./scripts/publish_release_macos.sh ["Notas da Versão"]
```
Em seguida, no Windows, execute `scripts\publish_release_windows.bat` para puxar a mesma versão/build via `git pull origin main`, compilar o binário Windows, atualizar `version.json` / `README.md` e enviar a tag `v<VERSÃO>-windows`.
