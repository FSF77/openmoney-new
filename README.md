# OpenMoney (Multiplataforma: macOS, Windows, iPhone e iPad)

<p align="center">
  <strong>Aplicativo financeiro moderno, multiplataforma (Flutter / Dart) e open source para macOS, Windows, iOS (iPhone) e iPadOS (iPad), inspirado no clássico Microsoft Money 99.</strong>
</p>

---

## 🚀 Arquitetura Multiplataforma (Flutter 3.x / Dart)

O **OpenMoney** agora é desenvolvido em uma base de código unificada e moderna em **Flutter (Dart)**, garantindo compilação nativa de alta performance para **macOS Universal (Apple Silicon & Intel)**, **Windows (x64)**, **iOS (iPhone)** e **iPadOS (iPad)**. 

Mantém **100% de compatibilidade estrutural e contábil** com o esquema JSON `openmoney.json` (`v: 6`), além de compatibilidade com extratos `.csv`, arquivos `.qif` clássicos do Microsoft Money 99 e arquivos de coleta rápida mobile `openmoney_inbox.json`.

---

## 🌟 Visão Geral

O **OpenMoney** combina o rigor contábil e a confiabilidade de controle financeiro do clássico Microsoft Money 99 com uma interface moderna no padrão *Liquid Glass* (vidro translúcido, gradientes luminosos e cartões flutuantes).

Seus dados pertencem exclusivamente a você:
- **100% Local e Soberano**: Sem telemetria, sem logins proprietários e sem dependência de nuvens fechadas.
- **Armazenamento Transparente**: Seus dados ficam salvos em um arquivo legível `openmoney.json`.
- **Sincronização Livre**: Salve e sincronize sua base no **iCloud Drive**, **OneDrive**, **Dropbox**, **Google Drive** ou disco local.
- **Gravação Atômica com Proteção contra Falhas**: Gravação segura via arquivo temporário com substituição atômica, imune a quedas de energia.

---

## 💎 Principais Funcionalidades e Recursos

### 1. Gestão de Contas e Livro-Caixa (Extrato Inteligente)
- **Múltiplos Tipos de Contas**: Contas Correntes, Poupança, Investimentos, Dinheiro em Carteira e Cartões de Crédito.
- **Saldo Real vs. Saldo Previsto**:
  - **Saldo Real**: Apuração estrita das transações já conciliadas no extrato.
  - **Saldo Previsto**: Projeção incluindo lançamentos pendentes e parcelas agendadas do mês.
- **Agrupamento Cronológico Dia a Dia**:
  - Extrato organizado por data com dia da semana (ex.: `15/10/2026 · Qui`).
  - **Saldo por Quebra de Dia**: Barra horizontal ao final de cada dia informando o saldo acumulado real (e previsto quando houver pendências).
  - **Saldos do Período**: Cabeçalho e rodapé com Saldo Inicial (Real e Previsto), Total de Entradas (+), Total de Saídas (−) e Saldo Final (Real e Previsto).
- **Favorecido e Anotações em Duas Linhas**:
  - Linha 1: Favorecido/Descrição ampla e identificadores de parcelas `(x/y)`.
  - Linha 2: Anotações (`memo`) em tamanho subordinado, sem colunas extras truncando informações.
- **Conciliação com 1 Clique**: Ícone circular interativo antes da data para alternar status entre pendente e conciliado.
- **Organização de Contas na Barra Lateral**:
  - Grupos: **Favoritas**, **Contas Ativas** e **Contas Inativas**.
  - **Persistência de Estado**: O estado expandido/recolhido dos grupos de contas é lembrado e restaurado ao reabrir o app.
  - Proteção de exclusão: contas com movimentações não podem ser excluídas acidentalmente (podem ser desativadas com 1 clique).

---

### 2. Gestão Avançada de Cartões de Crédito e Faturas
- **Ciclo Dinâmico de Fechamento e Vencimento**: Configuração individual do dia de fechamento (`closeDay`), dia de vencimento (`dueDay`) e conta padrão de pagamento (`pay`).
- **Agrupamento por Fatura e Override Manual**:
  - Transações são vinculadas à chave da fatura correspondente (`ik`).
  - Lançamentos realizados após o fechamento entram automaticamente na fatura seguinte.
  - O usuário tem total liberdade para selecionar manualmente outra fatura no formulário de inserção ou edição.
- **Adiantamento e Pagamento Parcial**:
  - Pagamentos e adiantamentos realizados antes ou depois do fechamento abatem o saldo da fatura em aberto.
  - A rotina de sincronização (`syncCards`) gera o agendamento de liquidação cobrando **estritamente o saldo remanescente**.
  - Se a fatura for quitada integralmente, o status passa para **LIQUIDADA** (verde) e o agendamento é removido.
- **Exportação de Fatura em PDF A4**:
  - Relatório de conferência idêntico à fatura bancária.
  - Traz todos os lançamentos que pertencem ao ciclo da fatura, independentemente do mês de calendário selecionado.
  - Ícone de conciliação na 1ª coluna, data em linha única, favorecido na linha 1, notas na linha 2, categoria formatada com `›` e valor numérico alinhado à direita.

---

### 3. Relatórios Analíticos Mensais
- **Layout de Duas Colunas (Receitas à Esquerda, Despesas à Direita)**:
  - Organização visual executiva que facilita o comparativo direto entre entradas e saídas.
- **Exclusão Estrita de Transferências e Categorias Neutras**:
  - Transferências entre contas e categorias marcadas como fora dos relatórios não poluem os totais de receitas e despesas.
- **Cards KPI de Alta Resolução**:
  - Total de Receitas, Total de Despesas, Resultado Líquido do Mês e Taxa de Poupança (*Savings Rate* %).
- **Barras de Distribuição Percentual**:
  - Ranking de participação de cada categoria com barras de progresso proporcionais.
- **Exportação em PDF A4 em 1 Página Única**:
  - Layout calibrado para caber perfeitamente em uma única folha A4.
  - Receitas alinhadas à esquerda e despesas à direita, com dados do período, indicadores e fechamento consolidado.

---

### 4. Auditoria e Drill-Down de Categorias
- **Detalhamento Interativo**:
  - Clique em qualquer categoria ou subcategoria na tela de Categorias ou nos Relatórios para abrir a janela modal de auditoria.
- **Filtros e Busca em Tempo Real**:
  - Campo de busca instantânea filtrando por descrição, notas ou valor.
  - Alternância entre lançamentos do mês selecionado e histórico completo.
- **Ordenação Dinâmica**:
  - Ordene por **Data** (mais recentes ou mais antigos), **Nome/Favorecido** (A-Z ou Z-A) e **Valor** (maior ou menor).
- **Ações Rápidas**:
  - Duplo clique na linha para abrir a edição completa da transação.
- **Exportação em CSV do Extrato da Categoria**:
  - Exportação direta com diálogo nativo de escolha do local e nome do arquivo (`NSSavePanel` / diálogo nativo).

---

### 5. Gestão de Categorias e Subcategorias
- **Hierarquia em Dois Níveis**: Categorias Principais e Subcategorias organizadas em **Despesas** e **Receitas**.
- **Importação e Exportação Estruturada em CSV**:
  - **Exportação**: Gera CSV com `Tipo`, `Categoria Principal`, `Subcategoria` e `Categoria Completa` formatada com o separador oficial `›` (ex.: `Alimentação › Supermercado`).
  - **Importação Resiliente**: Detecta delimitadores (`;`, `,`, tab), suporta separadores `›`, `>`, `/`, cria automaticamente categorias-mãe faltantes e ignora duplicatas.
- **Proteção Contra Lançamentos Órfãos**:
  - Categorias com lançamentos vinculados não podem ser deletadas diretamente; o sistema exige a escolha de uma categoria de substituição para reclassificar os registros.

---

### 6. Matriz de Fluxo de Caixa (Cash Flow)
- **Visão Matricial Multidimensional**:
  - Modos: **Mensal** (12 meses do ano + Total Anual), **Trimestral** (4 trimestres + Total), **Semestral** (2 semestres + Total) e **Anual** (comparativo de anos).
- **Cálculo Rigoroso Contábil**:
  - Rendimentos operacionais, Despesas operacionais e Resultado Líquido.
  - **Saldo Anterior Acumulado**: Saldo real transitado de períodos anteriores.
  - **Saldo Final Acumulado**: Saldo consolidado em caixa e bancos no final de cada período.
- **Layout Adaptativo Protegido**:
  - Dimensionamento responsivo sem quebras ou faixas de advertência cobrindo colunas.
- **Exportação em CSV com Diálogo de Salvamento**:
  - Pergunta onde salvar o arquivo via diálogo nativo do sistema operacional.
  - Formatado em UTF-8 com BOM, delimitador `;` e números com vírgula padrão BRL para Excel e Planilhas.

---

### 7. Importador Mobile Inbox (`openmoney_inbox.json`)
- **Integração com Coletor Celular / PWA**:
  - Importa lotes de lançamentos coletados no celular via arquivo `openmoney_inbox.json`.
- **Prevenção de Duplicidades**:
  - Detecção automática de lançamentos repetidos por assinatura única de dados.
- **Alocação Inteligente de Fatura de Cartão**:
  - Calcula automaticamente a chave da fatura (`ik`) para lançamentos em contas de cartão de crédito.
- **Modal de Revisão Visual**:
  - Exibe resumo de despesas, receitas, duplicados ignorados e a lista completa para conferência antes da efetivação.

---

### 8. Importação e Exportação de CSV e QIF (Microsoft Money 99)
- **Importação QIF Clássica**:
  - Decodificação inteligente com fallback para **Windows CP1252 / Latin-1**, preservando acentuação original do Microsoft Money 99.
  - Criação automática de contas e transferências espelhadas no formato `[NomeDaConta]`.
- **Importação CSV Flexível**:
  - Reconhecimento automático de colunas, datas (`DD/MM/AAAA`, `AAAA-MM-DD`), valores e contas.
  - Opção para criar contas inexistentes automaticamente.
  - Flag configurável para permitir ou bloquear importação de lançamentos duplicados.

---

### 9. Proteção de Arquivos e Diálogos Nativos do Sistema
- **Seleção Nativa de Arquivos**:
  - Integração nativa com seletores do sistema operacional (`NSSavePanel` / `NSOpenPanel` no macOS; diálogos Win32 no Windows).
  - Garante persistência e compatibilidade com diretórios protegidos do **iCloud Drive** e **OneDrive**.
- **Proteção contra Criação de Base Vazia**:
  - Caso o arquivo configurado não seja localizado (ex.: pendrive desconectado ou nuvem não sincronizada), o sistema **não cria uma base vazia silenciosamente**.
  - Apresenta tela de resgate para localizar o arquivo original, escolher um dos recentes ou criar intencionalmente uma nova base.
- **Histórico de Bases Recentes**:
  - Lista das últimas bases abertas com acesso em 1 clique.

---

## 🔄 Sistema de Atualização Automática (Auto-Update)

O OpenMoney Flutter possui um motor de atualização in-app integrado ([`lib/services/update_service.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/services/update_service.dart)), conectado ao repositório oficial:

- **Repositório Oficial**: [https://github.com/FSF77/openmoney-new](https://github.com/FSF77/openmoney-new)
- **Feed de Versões**: [https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json](https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json)

### Estrutura de Downloads e Atualizações
Os pacotes e o feed residem diretamente no repositório principal:

```text
openmoney-new/
├── version.json                     # Feed oficial de versão (macOS e Windows)
├── install.sh                       # Script de instalação rápida no macOS (curl | bash)
└── downloads/
    ├── macos/
    │   └── OpenMoney-macOS-<versao>.zip
    └── windows/
        └── OpenMoney-Windows-<versao>.zip
```

### Formato do Feed `version.json`
```json
{
  "version": "2.0.0",
  "build": 1,
  "releaseDate": "25/10/2026",
  "title": "OpenMoney Flutter v2.0.0",
  "notes": "Lançamento oficial multiplataforma com suporte nativo a macOS e Windows.",
  "githubReleaseUrl": "https://github.com/FSF77/openmoney-new",
  "macos": {
    "version": "2.0.0",
    "build": 1,
    "releaseDate": "25/10/2026",
    "downloadUrl": "https://github.com/FSF77/openmoney-new/raw/main/downloads/macos/OpenMoney-macOS-2.0.0.zip",
    "sha256": "...",
    "sizeMb": 28
  },
  "windows": {
    "version": "2.0.0",
    "build": 1,
    "releaseDate": "25/10/2026",
    "downloadUrl": "https://github.com/FSF77/openmoney-new/raw/main/downloads/windows/OpenMoney-Windows-2.0.0.zip",
    "sha256": "...",
    "sizeMb": 24
  }
}
```

### Funcionamento do Atualizador In-App
1. **Verificação Silenciosa**: Ao iniciar, o app consulta o feed de forma não-bloqueante.
2. **Verificação Manual**: Botão de nuvem na barra superior e item de menu "Buscar Atualizações...".
3. **Download com Barra de Progresso**: Acompanhamento em tempo real de bytes baixados e percentual.
4. **Instalação Atômica e Reinício**:
   - **No macOS**: Descompacta via `ditto`, remove atributos de quarentena com `xattr -cr` e substitui o bundle em `/Applications/OpenMoney.app` ou diretório local.
   - **No Windows**: Descompacta o zip e atualiza os binários de forma atômica.

---

## 🛠️ Scripts de Compilação e Publicação

O projeto conta com scripts automatizados para compilar e publicar releases diretamente no repositório:

### 🍏 No macOS (`scripts/publish_release_macos.sh`)
Compila o app em modo Release, empacota o zip em `downloads/macos/`, calcula hash SHA256, atualiza `version.json` e envia para o GitHub:

```bash
# Executar a publicação (usa a versão configurada no pubspec.yaml)
./scripts/publish_release_macos.sh "Notas da versão opcional"
```

### 🪟 No Windows (`scripts/publish_release_windows.ps1` e `.bat`)
No PowerShell ou no prompt de comando do Windows:

```powershell
# Via PowerShell:
.\scripts\publish_release_windows.ps1 -CustomNotes "Lançamento v2.0.0 para Windows"

# Ou via duplo-clique no arquivo batch:
scripts\publish_release_windows.bat
```

---

## 💻 Como Rodar em Ambiente de Desenvolvimento

### Pré-requisitos
- Flutter SDK 3.x+ ([flutter.dev](https://flutter.dev))
- **macOS**: Xcode instalado para desenvolvimento desktop e iOS.
- **Windows**: Visual Studio 2022 com suporte a C++ Desktop.

### Comandos Básicos

```bash
# 1. Obter dependências
flutter pub get

# 2. Executar análise estática de código
flutter analyze

# 3. Executar testes automatizados
flutter test

# 4. Executar no macOS
flutter run -d macos

# 5. Executar no Windows
flutter run -d windows
```

---

## 📁 Estrutura de Diretórios (`lib/`)

```text
lib/
├── main.dart                             # Ponto de entrada, inicialização de janelas e tema
├── models/
│   └── openmoney_models.dart             # Schema JSON v6, contas, cartões, faturas e transações
├── store/
│   └── money_store.dart                  # Estado central reativo, I/O atômico, backups e conciliação
├── services/
│   ├── cash_flow_engine.dart             # Motor matricial de fluxo de caixa (Mensal/Trimestral/etc.)
│   ├── importers_exporters.dart          # Parsers CSV, QIF (CP1252/Money 99) e Categorias CSV
│   ├── native_file_picker.dart           # Seletores nativos de arquivo (macOS / Windows / iOS)
│   ├── pdf_report_generator.dart         # Motor de geração de PDFs (Relatório Mensal, Faturas e Extratos)
│   └── update_service.dart               # Motor de auto-atualização in-app e integridade de releases
└── ui/
    ├── app_shell.dart                    # Shell principal adaptativo Desktop/Tablet com sidebar
    ├── modals/
    │   ├── category_drill_down_modal.dart # Auditoria com busca, ordenação e exportação CSV
    │   ├── csv_qif_modal.dart             # Central de importação/exportação CSV e QIF
    │   ├── mobile_inbox_modal.dart        # Conferência e importação de lançamentos do celular
    │   ├── transaction_edit_modal.dart    # Criação, edição e cópia de transações
    │   └── welcome_database_modal.dart    # Painel de resgate e seleção segura de banco de dados
    └── views/
        ├── account_ledger_view.dart       # Extrato de contas, fechamento diário e faturas
        ├── budget_view.dart               # Orçamento mensal com metas e barras Liquid Glass
        ├── cash_flow_view.dart            # Matriz financeira multidimensional de fluxo de caixa
        ├── categories_view.dart           # Árvore hierárquica, exportação/importação CSV e drill-down
        ├── due_bills_view.dart            # Central de contas a pagar e receber (vencimentos)
        ├── global_search_view.dart        # Busca multicritério em toda a base de dados
        └── reports_view.dart              # Relatório mensal analítico (Receitas à esq., Despesas à dir.)
```

---

## 🎨 Ícones e Identidade Visual

O OpenMoney inclui o pacote completo de ícones de alta resolução (`AppIcon.icns` e `icon-1024.png`):
- **macOS**: `macos/Runner/Assets.xcassets/AppIcon.appiconset/` e `macos/Runner/AppIcon.icns` em resoluções 16x16 até 1024x1024 Retina.
- **Windows**: `windows/runner/resources/app_icon.ico` com suporte multi-resolução nativo Win32 (16, 32, 48, 64, 128, 256 px).
- **iOS / iPadOS**: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` completo para iPhone, iPad e App Store.

---

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo `LICENSE` para mais detalhes.

*OpenMoney é um projeto independente de código aberto. Não possui afiliação, vínculo ou endosso da Microsoft Corporation.*
