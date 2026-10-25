import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showCsvQifCenterModal(
  BuildContext context,
  MoneyStore store,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _CsvQifCenterDialog(store: store),
  );
}

class _CsvQifCenterDialog extends StatefulWidget {
  final MoneyStore store;
  const _CsvQifCenterDialog({required this.store});

  @override
  State<_CsvQifCenterDialog> createState() => _CsvQifCenterDialogState();
}

class _CsvQifCenterDialogState extends State<_CsvQifCenterDialog> {
  String _targetAccountId = 'auto';
  bool _allowDuplicates = false;
  late final TextEditingController _filePathCtrl;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final dir = widget.store.defaultCloudOrDocumentsDir();
    _filePathCtrl = TextEditingController(
      text: dir.isNotEmpty
          ? '$dir${kIsWeb ? "/" : Platform.pathSeparator}openmoney-${todayISO()}.csv'
          : 'openmoney-${todayISO()}.csv',
    );
  }

  @override
  void dispose() {
    _filePathCtrl.dispose();
    super.dispose();
  }

  void _importFile({required bool isQif}) {
    if (kIsWeb) return;
    final path = _filePathCtrl.text.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() {
        _isError = true;
        _statusMessage = 'Arquivo não localizado em: $path';
      });
      return;
    }
    try {
      final bytes = File(path).readAsBytesSync();
      final targetId = _targetAccountId == 'auto' ? null : _targetAccountId;
      final summary = isQif
          ? widget.store.importQIFBytes(bytes, targetAccountId: targetId)
          : widget.store.importCSVBytes(
              bytes,
              targetAccountId: targetId,
              allowDuplicates: _allowDuplicates,
            );
      setState(() {
        _isError = false;
        _statusMessage = summary.formattedMessage;
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _statusMessage = 'Falha ao importar: $e';
      });
    }
  }

  void _exportCsv() {
    final filterId = _targetAccountId == 'auto' ? null : _targetAccountId;
    final csv = widget.store.exportCSVString(accountFilterId: filterId);
    if (!kIsWeb) {
      final path = _filePathCtrl.text.trim();
      try {
        File(path).writeAsStringSync(csv, flush: true);
        setState(() {
          _isError = false;
          _statusMessage = '✓ CSV exportado com sucesso em:\n$path';
        });
        return;
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Erro ao gravar arquivo: $e';
        });
      }
    }
    Clipboard.setData(ClipboardData(text: csv));
    setState(() {
      _isError = false;
      _statusMessage = '✓ Conteúdo CSV copiado para a área de transferência!';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: const Row(
        children: [
          Icon(Icons.import_export, color: Colors.lightBlueAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text('Central de Importação / Exportação (CSV & QIF)'),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _targetAccountId,
                decoration: const InputDecoration(
                  labelText: 'Conta de Destino / Filtro de Exportação',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'auto',
                    child: Text(
                        'Automático (Usar coluna "Conta" do CSV / Todas as Contas)'),
                  ),
                  ...widget.store.db.accounts.map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _targetAccountId = v);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Permitir Lançamentos Duplicados'),
                subtitle: const Text(
                    'Desativado por padrão (verificação O(1) por conta, data, valor e favorecido)'),
                value: _allowDuplicates,
                onChanged: (v) => setState(() => _allowDuplicates = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _filePathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Caminho do Arquivo (.csv ou .qif)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isError ? colors.expense : colors.income)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isError ? colors.expense : colors.income,
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _isError ? colors.expense : colors.income,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Importar QIF (Money 99)'),
          onPressed: () => _importFile(isQif: true),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.file_upload_outlined, size: 18),
          label: const Text('Importar CSV'),
          onPressed: () => _importFile(isQif: false),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Exportar CSV'),
          onPressed: _exportCsv,
        ),
      ],
    );
  }
}

Future<void> showDatabaseFileManagerModal(
  BuildContext context,
  MoneyStore store,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colors = OpenMoneyColors(isDark);
  final defaultCloud = store.defaultCloudOrDocumentsDir();
  final sep = kIsWeb ? '/' : Platform.pathSeparator;
  final pathCtrl = TextEditingController(
    text: store.dbPath.isNotEmpty
        ? store.dbPath
        : '$defaultCloud${sep}openmoney.json',
  );
  String? feedback;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        return AlertDialog(
          backgroundColor: colors.bgSecondary,
          title: const Row(
            children: [
              Icon(Icons.cloud_sync_outlined, color: Colors.lightBlueAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Base de Dados & Sincronização (iCloud Drive / OneDrive)'),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Arquivo Ativo: ${store.dbPath.isEmpty ? "Memória Local" : store.dbPath}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pathCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          'Caminho Completo do Arquivo (.json) no Finder / Explorer',
                      hintText:
                          'Ex.: .../iCloud Drive/openmoney.json ou C:\\Users\\...\\OneDrive\\openmoney.json',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.cloud_outlined, size: 16),
                        label: const Text('Pasta Nuvem Padrão (iCloud/OneDrive)'),
                        onPressed: () {
                          setModalState(() {
                            pathCtrl.text =
                                '$defaultCloud${sep}openmoney.json';
                          });
                        },
                      ),
                    ],
                  ),
                  if (store.recentFiles.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Arquivos Recentes:',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    ...store.recentFiles.map((item) {
                      final isCurrent = item.path == store.dbPath;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle
                              : Icons.description_outlined,
                          color:
                              isCurrent ? colors.income : colors.textSecondary,
                          size: 18,
                        ),
                        title: Text(item.displayName),
                        subtitle: Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            if (store.openDatabaseFromPath(item.path)) {
                              Navigator.pop(ctx);
                            } else {
                              setModalState(() {
                                feedback =
                                    'Arquivo não encontrado: ${item.path}';
                              });
                            }
                          },
                          child: const Text('Abrir'),
                        ),
                      );
                    }),
                  ],
                  if (feedback != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      feedback!,
                      style: TextStyle(color: colors.accent, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Criar Nova Base Aqui'),
              onPressed: () {
                final p = pathCtrl.text.trim();
                if (p.isEmpty) return;
                store.createNewDatabaseAtPath(p);
                Navigator.pop(ctx);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              label: const Text('Mover Base Atual para cá'),
              onPressed: () {
                final p = pathCtrl.text.trim();
                if (p.isEmpty) return;
                store.moveDatabaseToPath(p);
                Navigator.pop(ctx);
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Abrir Base Existente'),
              onPressed: () {
                final p = pathCtrl.text.trim();
                if (store.openDatabaseFromPath(p)) {
                  Navigator.pop(ctx);
                } else {
                  setModalState(() {
                    feedback =
                        'Não foi possível abrir "$p". Verifique se o arquivo existe.';
                  });
                }
              },
            ),
          ],
        );
      },
    ),
  );
}
