# ADR 038 — Adoção do Padrão de Versionamento por Data (CalVer `YYYY.M.D+BUILD`) e Automação de Releases

## Status
Aprovado e Implementado (Novembro/2026).

---

## 1. Contexto e Motivação
Até o build `+170` (`2.5.8+170`), o **OpenMoney** utilizava o modelo de versionamento semântico tradicional (`MAJOR.MINOR.PATCH+BUILD`). Com a consolidação da stack única multiplataforma em **Flutter / Dart** (ADR 029) e o fluxo de entrega contínua (*rolling release*) para **Web PWA (`openmoney.app.br`)**, **macOS** e **Windows**, surgiram três necessidades práticas:

1. **Clareza Temporal Imediata para o Usuário e Suporte:**
   Ao visualizar uma versão como `v2.5.8`, o usuário não sabe intuitivamente quão recente é a instalação sem consultar notas de lançamento externas. Com uma versão baseada em data (`v2026.11.24 (Build 170)`), qualquer pessoa identifica instantaneamente o dia exato da versão em uso.
2. **Eliminação de Fricção no Processo de Publicação:**
   No modelo manual anterior, era necessário escolher ou incrementar manualmente o número da versão a cada publicação. Com o versionamento por calendário (**CalVer**), o script de release calcula automaticamente a data do dia e incrementa o número sequencial de build (`+1`).
3. **Compatibilidade Integral com Auto-Update e `pubspec.yaml`:**
   O comparador de versão do `UpdateService` já avalia cada segmento numérico separado por ponto (`.`) como inteiro (`int.tryParse`), usando o `build` (`+BUILD`) como critério de desempate.

---

## 2. Decisões de Arquitetura

### 2.1. Formato Oficial CalVer (`YYYY.M.D+BUILD`)
- O formato canônico de versão passa a ser **`YYYY.M.D+BUILD`** (ex.: `2026.11.24+170`, `2027.1.5+185`):
  - **`YYYY`**: Ano com 4 dígitos (ex.: `2026`).
  - **`M`**: Mês de `1` a `12`, **sem zero à esquerda** (`1..12`).
  - **`D`**: Dia do mês de `1` a `31`, **sem zero à esquerda** (`1..31`).
  - **`+BUILD`**: Número inteiro sequencial sempre crescente (`+170`, `+171`, `+172`...), incrementado automaticamente a cada compilação de release.
- **Motivo da ausência de zeros à esquerda em `M` e `D`:** A especificação do `pubspec.yaml` do Dart/Flutter segue a gramática estrita do SemVer 2.0 para os três segmentos numéricos (`MAJOR.MINOR.PATCH`), que proíbe zeros à esquerda em segmentos numéricos (ex.: `01` gera erro no parser do `flutter pub`, enquanto `1` é 100% válido e compara numericamente de forma exata).

### 2.2. Algoritmo de Comparação e Múltiplos Builds no Mesmo Dia
- O método `UpdateService.isVersionGreaterThan(remote, remoteBuild, local, localBuild)` em `lib/services/update_service.dart` compara os segmentos `[YYYY, M, D]` como inteiros:
  - **Transição SemVer → CalVer:** Para qualquer cliente ainda na série `2.x.x` (ex.: `2.5.8`), a comparação do primeiro segmento (`2026 > 2`) retorna `true` imediatamente, acionando o auto-update sem necessidade de regras de exceção.
  - **Múltiplas releases no mesmo dia:** Caso duas ou mais compilações sejam publicadas na mesma data (ex.: `2026.11.24+171` pela manhã e `2026.11.24+172` à tarde), os três segmentos da data empatam e o comparador desempata automaticamente por `remoteBuild > localBuild` (`172 > 171`).

### 2.3. Automação e Sanitização no Script de Publicação (`scripts/publish_release_macos.sh`)
- **Geração automática da data:** Quando executado apenas com as notas da versão (`./scripts/publish_release_macos.sh "Notas..."`), o script calcula automaticamente `TODAY_CALVER=$(date "+%Y.%-m.%-d")`.
- **Normalização automática de zeros à esquerda:** Caso uma versão customizada seja informada manualmente com zeros à esquerda (ex.: `2027.01.05`), o script sanitiza os segmentos via `awk -F. '{printf "%d.%d.%d", $1, $2, $3}'`, convertendo-a automaticamente para `2027.1.5`.
- **Sincronização encadeada com Windows (`scripts/publish_release_windows.ps1`):** O script Windows continua extraindo a versão e o build diretamente do `pubspec.yaml` após o `git pull origin main`, gerando o pacote `OpenMoney-Windows-YYYY.M.D.zip` e atualizando o `version.json` e o `README.md` de maneira uniforme.

---

## 3. Consequências e Benefícios
- **Transparência para o Usuário Final:** Identificação imediata da idade e atualidade do aplicativo instalado em qualquer plataforma (macOS, Windows, Web e Mobile).
- **Publicação com Comando Único Simplificado:** Não é mais necessário informar o número da versão ao publicar (`./scripts/publish_release_macos.sh "Notas da versão"`).
- **Retrocompatibilidade Total:** Clientes antigos (`2.5.x`) atualizam automaticamente para a nova numeração CalVer pelo motor nativo de Auto-Update.
