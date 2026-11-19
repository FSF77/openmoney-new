# ADR 031: Isolamento de Armazenamento em Ambiente de Teste e Proteção do config.json

## Status
Aprovado / Implementado

## Contexto
Durante o ciclo de desenvolvimento e execução de testes automatizados (`flutter test`) no macOS, foi observado que o arquivo de configuração real do usuário/desenvolvedor (`~/Library/Application Support/OpenMoneyNew/config.json`) era periodicamente sobrescrito.

Ao término dos testes, quando o usuário abria o aplicativo desktop localmente, deparava-se com o modal de segurança:
> **"Proteção contra Perda de Base"**
> *"A base de dados configurada anteriormente não foi localizada no caminho: `/var/folders/.../T/openmoney_test_db_....json`"*

Essa situação obrigava o desenvolvedor a recriar seu `config.json` e reautenticar suas contas Cloud e locais a cada execução de testes.

### Análise de Causa Raiz
1. O teste `Alternância entre Modo Local e Modo Cloud preserva lastLocalDbPath` em `test/safety_guard_and_sync_test.dart` instanciou `MoneyStore(autoBoot: false)` sem o parâmetro `appSupportDirOverride`.
2. Como resultado, o `MoneyStore._initPaths` e o serviço nativo `platform_io_native.dart` utilizaram o caminho padrão da plataforma (`~/Library/Application Support/OpenMoneyNew/`).
3. O teste criou um arquivo temporário em `/var/folders/...`, chamou `switchToLocalMode(path: tempFile.path)` (que persiste `dbPath` e `lastLocalDbPath` no `config.json`), e no bloco `finally` excluiu o arquivo temporário.
4. Quando o aplicativo nativo inicializava, encontrava a referência para um arquivo inexistente, ativando a proteção de integridade da base.

## Decisões Tomadas

### 1. Salvaguarda Automática no `MoneyStore` para Ambientes de Teste
- No método `_initPaths` de `lib/store/money_store.dart`, adicionou-se uma verificação explícita da variável de ambiente `Platform.environment.containsKey('FLUTTER_TEST')`.
- Quando presente (caso de qualquer execução via `flutter test`), se `appSupportDirOverride` não for fornecido explicitamente, `_appSupportDirPath` é automaticamente apontado para um subdiretório temporário isolado do sistema:
  ```dart
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    final testDir = '${Directory.systemTemp.path}${sep}OpenMoney_Test_Support';
    _appSupportDirPath = testDir;
    _configFilePath = '$_appSupportDirPath${sep}config.json';
    _defaultDbFilePath = '$_appSupportDirPath${sep}openmoney.json';
    return;
  }
  ```
- Garante-se que nenhuma instância padrão de `MoneyStore` criada em testes unitários ou de widget consiga ler ou gravar no `config.json` real da máquina de desenvolvimento.

### 2. Salvaguarda Automática na Camada de I/O Nativo (`platform_io_native.dart`)
- No método `_getAppSupportDir` de `lib/services/platform_io_native.dart`, a detecção de `FLUTTER_TEST` também foi implementada.
- Garante que o armazenamento KV leve (`sync_kv_store.json`), tokens e deltas de teste permaneçam contidos no ambiente temporário sem vazar para o Application Support real.

### 3. Isolamento Explícito por Teste em `safety_guard_and_sync_test.dart`
- O teste de alternância de modo em `test/safety_guard_and_sync_test.dart` foi atualizado para criar e passar explicitamente `tempDir.path` via `appSupportDirOverride: tempDir.path`, limpando seu próprio diretório no `finally`.

## Consequências
- O `config.json` da máquina de desenvolvimento onde o app é executado e testado fica **100% blindado contra corrupções ou perdas de referência**.
- As contas locais e credenciais Cloud Sync v2 configuradas no macOS e Windows permanecem intactas antes, durante e após a execução de qualquer suite de testes (`flutter test`).
- O isolamento é transparente e automático, não dependendo de parâmetros manuais em futuros testes criados por desenvolvedores ou agentes.
