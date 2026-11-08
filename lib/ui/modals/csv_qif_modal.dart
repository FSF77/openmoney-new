import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import 'mobile_inbox_modal.dart';
import 'wallet_import_modal.dart';

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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Procurar Arquivo para Importar (Finder)'),
                    onPressed: () async {
                      final selected = await NativeFilePicker.pickFile(
                        title: 'Selecionar Arquivo CSV ou QIF',
                        allowedExtensions: ['csv', 'qif'],
                      );
                      if (selected != null && selected.isNotEmpty) {
                        setState(() {
                          _filePathCtrl.text = selected;
                        });
                      }
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.save_as_outlined, size: 16),
                    label: const Text('Definir Destino para Exportar CSV'),
                    onPressed: () async {
                      final savePath = await NativeFilePicker.saveFile(
                        title: 'Escolher Destino para Salvar CSV',
                        defaultName: 'openmoney-${todayISO()}.csv',
                        allowedExtensions: ['csv'],
                      );
                      if (savePath != null && savePath.isNotEmpty) {
                        setState(() {
                          _filePathCtrl.text = savePath;
                        });
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 22),
              const Text(
                'Coletor Mobile (.json) & Catálogo de Categorias (CSV):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 16,
                    ),
                    label: const Text('Importar da Carteira (Atalhos CSV)'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await showWalletImportModal(context, widget.store);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.phone_iphone, size: 16),
                    label: const Text('Importar do Celular (.json)'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await showMobileInboxImportFlow(context, widget.store);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.category_outlined, size: 16),
                    label: const Text('Importar Categorias (CSV)'),
                    onPressed: () async {
                      final selected = await NativeFilePicker.pickFile(
                        title: 'Importar Categorias e Subcategorias (CSV)',
                        allowedExtensions: ['csv'],
                      );
                      if (selected != null && selected.isNotEmpty) {
                        try {
                          final bytes = File(selected).readAsBytesSync();
                          final summary =
                              widget.store.importCategoriesCSVBytes(bytes);
                          setState(() {
                            _isError = false;
                            _statusMessage = summary.formattedMessage;
                          });
                        } catch (e) {
                          setState(() {
                            _isError = true;
                            _statusMessage =
                                'Erro ao importar categorias: $e';
                          });
                        }
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Exportar Categorias (CSV)'),
                    onPressed: () async {
                      final savePath = await NativeFilePicker.saveFile(
                        title: 'Exportar Categorias e Subcategorias (CSV)',
                        defaultName: 'openmoney-categorias-${todayISO()}.csv',
                        allowedExtensions: ['csv'],
                      );
                      if (savePath != null && savePath.isNotEmpty) {
                        try {
                          final csv = widget.store.exportCategoriesCSVString();
                          final f = File(savePath);
                          f.parent.createSync(recursive: true);
                          f.writeAsStringSync(csv, flush: true);
                          setState(() {
                            _isError = false;
                            _statusMessage =
                                '✓ Categorias exportadas com sucesso em:\n$savePath';
                          });
                        } catch (e) {
                          setState(() {
                            _isError = true;
                            _statusMessage =
                                'Erro ao exportar categorias: $e';
                          });
                        }
                      }
                    },
                  ),
                ],
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
  String? feedback;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        return AlertDialog(
          backgroundColor: colors.bgSecondary,
          title: const Row(
            children: [
              Icon(Icons.folder_open_outlined, color: Colors.lightBlueAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Base de Dados Local'),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.bgPrimary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, size: 16, color: colors.income),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Base de Dados em Uso',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                store.dbPath.isEmpty ? 'Memória Local' : store.dbPath,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: colors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text(
                            'Abrir Base Existente',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: () async {
                            final selected = await NativeFilePicker.pickFile(
                              title: 'Escolher Base OpenMoney (.json)',
                              allowedExtensions: ['json'],
                            );
                            if (selected != null && selected.isNotEmpty) {
                              if (store.openDatabaseFromPath(selected)) {
                                Navigator.pop(ctx);
                              } else {
                                setModalState(() {
                                  feedback =
                                      'Não foi possível abrir o arquivo "$selected". Verifique se o formato é válido.';
                                });
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: colors.borderGlass),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text(
                            'Criar Nova Base',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: () async {
                            final savePath = await NativeFilePicker.saveFile(
                              title: 'Escolher Local para Salvar Nova Base',
                              defaultName: 'openmoney.json',
                            );
                            if (savePath != null && savePath.isNotEmpty) {
                              store.createNewDatabaseAtPath(savePath);
                              Navigator.pop(ctx);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (feedback != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.expense.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.expense.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: colors.expense),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feedback!,
                              style: TextStyle(color: colors.expense, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Arquivos Recentes',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (store.recentFiles.isNotEmpty)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colors.expense,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                          label: const Text(
                            'Limpar Recentes',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            setModalState(() {
                              store.clearRecentFiles();
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (store.recentFiles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Nenhum arquivo recente registrado.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
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
                        title: Text(
                          item.displayName,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                            color: colors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: colors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isCurrent)
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
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
                                child: const Text('Abrir', style: TextStyle(fontSize: 12)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Remover da lista',
                              onPressed: () {
                                setModalState(() {
                                  store.removeRecentFile(item.path);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            if (store.hasConfiguredLocalDatabase)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: colors.expense,
                ),
                onPressed: () {
                  store.disconnectLocalDatabase();
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Desconectar Base Local'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    ),
  );
}
