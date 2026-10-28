# OpenMoney (Multiplataforma: macOS, Windows, iPhone e iPad)

<p align="center">
  <strong>Aplicativo financeiro moderno, multiplataforma (Flutter / Dart) e open source para macOS, Windows, iOS (iPhone) e iPadOS (iPad), inspirado no clássico Microsoft Money 99.</strong>
</p>

<p align="center">
  <img src="icon-1024.png" alt="OpenMoney Logo" width="128" height="128" />
</p>

---

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
3. **Precisão Financeira em Centavos Inteiros (`Int`)**:
   - Todos os valores monetários são calculados e armazenados internamente como centavos inteiros (`amt: Int`), eliminando dízimas periódicas e erros de arredondamento de ponto flutuante (`Double` / `Float`).
4. **Resiliência e Gravação Atômica**:
   - Proteção estrita contra corrupção em quedas de energia: a gravação ocorre em arquivo temporário com substituição atômica imediata.
   - Rotina automatizada de **Backups em ZIP** com histórico e retenção segura.

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
- **Proteção contra Lançamentos Órfãos**:
  - Categorias com transações vinculadas não podem ser excluídas sem que o usuário defina uma categoria de destino para transferir os registros.

---

### 8. Orçamento Mensal Planejado (Budget)
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

### 12. Coletor Mobile Web / PWA (`coletor/`)
- Módulo PWA independente para registrar despesas e receitas rapidamente no smartphone (offline-first).
- Recursos do coletor:
  - Registro de lançamentos rápidos com autocompletar de favorecidos da base.
  - Suporte a leitura de comprovantes via **OCR de câmera** e inserção rápida por voz.
  - Exportação do lote em `openmoney_inbox.json`.
- **Importação Desktop**:
  - No OpenMoney Desktop, abra o importador Mobile Inbox para validar, auditar e importar os lançamentos pendentes com prevenção contra duplicidades e alocação automática de faturas.

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

*OpenMoney é um projeto independente de código aberto desenvolvido para a comunidade. Não possui afiliação, vínculo comercial ou endosso da Microsoft Corporation.*
