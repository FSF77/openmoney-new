import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import 'mobile_inbox_modal.dart';
import 'receipt_ocr_import_modal.dart';
import 'wallet_import_modal.dart';

enum _ExportPeriodMode {
  all,
  month,
  custom,
}

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
  int _selectedTab = 0; // 0: Importar, 1: Exportar
  String? _statusMessage;
  bool _isError = false;

  // Parâmetros de Importação
  String _importAccountId = 'auto';
  bool _allowDuplicates = false;

  // Parâmetros de Exportação
  String _exportAccountId = 'all';
  _ExportPeriodMode _periodMode = _ExportPeriodMode.all;
  late String _exportMonthYM;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _exportMonthYM = widget.store.month;
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
  }

  String? get _effectiveStartDate {
    switch (_periodMode) {
      case _ExportPeriodMode.all:
        return null;
      case _ExportPeriodMode.month:
        return '$_exportMonthYM-01';
      case _ExportPeriodMode.custom:
        return '${_startDate.year.toString().padLeft(4, '0')}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
    }
  }

  String? get _effectiveEndDate {
    switch (_periodMode) {
      case _ExportPeriodMode.all:
        return null;
      case _ExportPeriodMode.month:
        return '$_exportMonthYM-31';
      case _ExportPeriodMode.custom:
        return '${_endDate.year.toString().padLeft(4, '0')}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}';
    }
  }

  int get _exportCount {
    return widget.store.countTransactionsForExport(
      accountFilterId: _exportAccountId == 'all' ? null : _exportAccountId,
      startDate: _effectiveStartDate,
      endDate: _effectiveEndDate,
    );
  }

  Future<void> _handleImportCSV() async {
    final selected = await NativeFilePicker.pickFile(
      title: 'Selecionar Arquivo CSV de Lançamentos',
      allowedExtensions: ['csv'],
    );
    if (selected != null && selected.isNotEmpty) {
      try {
        final bytes = File(selected).readAsBytesSync();
        final targetId = _importAccountId == 'auto' ? null : _importAccountId;
        final summary = widget.store.importCSVBytes(
          bytes,
          targetAccountId: targetId,
          allowDuplicates: _allowDuplicates,
        );
        setState(() {
          _isError = false;
          _statusMessage = '✓ ${summary.formattedMessage}';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Falha ao importar CSV: $e';
        });
      }
    }
  }

  Future<void> _handleImportQIF() async {
    final selected = await NativeFilePicker.pickFile(
      title: 'Selecionar Arquivo QIF (Money 99 / Quicken)',
      allowedExtensions: ['qif'],
    );
    if (selected != null && selected.isNotEmpty) {
      try {
        final bytes = File(selected).readAsBytesSync();
        final targetId = _importAccountId == 'auto' ? null : _importAccountId;
        final summary = widget.store.importQIFBytes(
          bytes,
          targetAccountId: targetId,
        );
        setState(() {
          _isError = false;
          _statusMessage = '✓ ${summary.formattedMessage}';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Falha ao importar QIF: $e';
        });
      }
    }
  }

  Future<void> _handleImportCategories() async {
    final selected = await NativeFilePicker.pickFile(
      title: 'Selecionar Arquivo CSV de Categorias',
      allowedExtensions: ['csv'],
    );
    if (selected != null && selected.isNotEmpty) {
      try {
        final bytes = File(selected).readAsBytesSync();
        final summary = widget.store.importCategoriesCSVBytes(bytes);
        setState(() {
          _isError = false;
          _statusMessage = '✓ ${summary.formattedMessage}';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Erro ao importar categorias: $e';
        });
      }
    }
  }

  Future<void> _handleExportCSV() async {
    final count = _exportCount;
    if (count == 0) {
      setState(() {
        _isError = true;
        _statusMessage =
            'Nenhum lançamento encontrado para os filtros selecionados.';
      });
      return;
    }

    final targetAcc = _exportAccountId == 'all'
        ? null
        : widget.store.accById(_exportAccountId);
    final accSlug = targetAcc != null
        ? '-${targetAcc.name.replaceAll(RegExp(r'[^\w\d_-]'), '_')}'
        : '';
    final periodSlug = _periodMode == _ExportPeriodMode.all
        ? '-todos'
        : (_periodMode == _ExportPeriodMode.month
            ? '-$_exportMonthYM'
            : '-periodo');
    final defaultFileName = 'openmoney$accSlug$periodSlug-${todayISO()}.csv';

    final savePath = await NativeFilePicker.saveFile(
      title: 'Escolher Local para Salvar CSV de Lançamentos',
      defaultName: defaultFileName,
      allowedExtensions: ['csv'],
    );

    if (savePath != null && savePath.isNotEmpty) {
      try {
        final filterId = _exportAccountId == 'all' ? null : _exportAccountId;
        final csv = widget.store.exportCSVString(
          accountFilterId: filterId,
          startDate: _effectiveStartDate,
          endDate: _effectiveEndDate,
        );
        if (!kIsWeb) {
          final f = File(savePath);
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(csv, flush: true);
          setState(() {
            _isError = false;
            _statusMessage =
                '✓ $count lançamentos exportados com sucesso em:\n$savePath';
          });
          return;
        }
        Clipboard.setData(ClipboardData(text: csv));
        setState(() {
          _isError = false;
          _statusMessage =
              '✓ $count lançamentos copiados para a área de transferência!';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Erro ao exportar lançamentos: $e';
        });
      }
    }
  }

  Future<void> _handleExportCategories() async {
    final savePath = await NativeFilePicker.saveFile(
      title: 'Escolher Local para Salvar CSV de Categorias',
      defaultName: 'openmoney-categorias-${todayISO()}.csv',
      allowedExtensions: ['csv'],
    );

    if (savePath != null && savePath.isNotEmpty) {
      try {
        final csv = widget.store.exportCategoriesCSVString();
        if (!kIsWeb) {
          final f = File(savePath);
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(csv, flush: true);
          setState(() {
            _isError = false;
            _statusMessage =
                '✓ Categorias exportadas com sucesso em:\n$savePath';
          });
          return;
        }
        Clipboard.setData(ClipboardData(text: csv));
        setState(() {
          _isError = false;
          _statusMessage = '✓ Categorias copiadas para a área de transferência!';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Erro ao exportar categorias: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.import_export, color: colors.accent, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Central de Importação / Exportação',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Lançamentos, faturas, carteira iOS, OCR e categorias (CSV & QIF)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Fechar',
          ),
        ],
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Abas Principais: Importar Dados vs Exportar Dados
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.file_download_outlined, size: 18),
                    label: Text(
                      'Importar Dados',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(
                      'Exportar Dados',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (newVal) {
                  setState(() {
                    _selectedTab = newVal.first;
                    _statusMessage = null;
                  });
                },
              ),
              const SizedBox(height: 16),

              if (_selectedTab == 0)
                _buildImportTab(colors)
              else
                _buildExportTab(colors),

              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isError ? colors.expense : colors.income)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isError ? colors.expense : colors.income,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: _isError ? colors.expense : colors.income,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _isError ? colors.expense : colors.income,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
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
      ],
    );
  }

  Widget _buildImportTab(OpenMoneyColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card de Configurações para Lançamentos
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Importação Geral de Lançamentos (CSV & QIF)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _importAccountId,
                decoration: const InputDecoration(
                  labelText: 'Conta de Destino',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'auto',
                    child: Text(
                        'Automático (usar coluna "Conta" do arquivo / Extrato)'),
                  ),
                  ...widget.store.db.accounts.map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _importAccountId = v);
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Permitir Lançamentos Duplicados',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _allowDuplicates
                      ? 'Atenção: Transações com a mesma conta, data, valor e favorecido serão importadas novamente.'
                      : 'Proteção ativa: Transações idênticas já existentes na base serão ignoradas automaticamente.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _allowDuplicates
                        ? colors.expense
                        : colors.textSecondary,
                  ),
                ),
                value: _allowDuplicates,
                onChanged: (v) => setState(() => _allowDuplicates = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text(
                        'Importar Lançamentos (CSV)...',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: _handleImportCSV,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: colors.borderGlass),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text(
                        'Importar QIF (Money 99)...',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: _handleImportQIF,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!kIsWeb) ...[
          const SizedBox(height: 16),
          Text(
            'Rotinas Especializadas de Importação',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _buildSpecialRoutineCard(
            colors: colors,
            icon: Icons.phone_iphone,
            title: 'Importar do Celular (openmoney_inbox.json)',
            subtitle:
                'Importação direta de arquivo de lançamentos rápidos capturados no aplicativo móvel.',
            buttonLabel: 'Importar Arquivo Inbox',
            onTap: () {
              Navigator.pop(context);
              showMobileInboxImportFlow(context, widget.store);
            },
          ),
          const SizedBox(height: 8),
          _buildSpecialRoutineCard(
            colors: colors,
            icon: Icons.document_scanner_outlined,
            title: 'Importar Comprovantes por OCR (Imagens e PDFs)',
            subtitle:
                'Reconhecimento ótico local e IA Gemini para ler cupons fiscais NFC-e, notas e comprovantes bancários.',
            buttonLabel: 'Abrir Leitor de Comprovantes',
            onTap: () {
              Navigator.pop(context);
              showReceiptOcrImportModal(context, widget.store);
            },
          ),
          const SizedBox(height: 8),
          _buildSpecialRoutineCard(
            colors: colors,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Importar da Carteira (Atalhos iOS CSV)',
            subtitle:
                'Importação assistida de compras e faturas do Apple Wallet via Atalhos com revisão de De/Para de contas.',
            buttonLabel: 'Abrir Assistente da Carteira',
            onTap: () {
              Navigator.pop(context);
              showWalletImportModal(context, widget.store);
            },
          ),
        ],
        const SizedBox(height: 16),

        // Catálogo de Categorias
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Row(
            children: [
              Icon(Icons.category_outlined,
                  size: 24, color: colors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catálogo de Categorias e Subcategorias',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Importe árvore completa de categorias via arquivo CSV padronizado.',
                      style:
                          TextStyle(fontSize: 11.5, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Importar Categorias...'),
                onPressed: _handleImportCategories,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialRoutineCard({
    required OpenMoneyColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: colors.borderGlass),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: onTap,
            child: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildExportTab(OpenMoneyColors colors) {
    final count = _exportCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card de Filtros de Exportação de Lançamentos
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filtros para Exportação de Lançamentos (CSV)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // 1. Filtro de Conta
              DropdownButtonFormField<String>(
                initialValue: _exportAccountId,
                decoration: const InputDecoration(
                  labelText: 'Conta',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(
                      'Todas as Contas (${widget.store.db.txs.length} lançamentos na base)',
                    ),
                  ),
                  ...widget.store.db.accounts.map((a) {
                    final accCount = widget.store.db.txs
                        .where((t) => t.acc == a.id)
                        .length;
                    return DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} ($accCount lançamentos)'),
                    );
                  }),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _exportAccountId = v);
                },
              ),
              const SizedBox(height: 14),

              // 2. Filtro de Período
              Text(
                'Período dos Lançamentos',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<_ExportPeriodMode>(
                segments: const [
                  ButtonSegment(
                    value: _ExportPeriodMode.all,
                    label: Text('Todo o Período', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _ExportPeriodMode.month,
                    label: Text('Apenas o Mês', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _ExportPeriodMode.custom,
                    label: Text('Definir Início e Fim',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_periodMode},
                onSelectionChanged: (val) {
                  setState(() => _periodMode = val.first);
                },
              ),
              const SizedBox(height: 12),

              // Detalhe do período selecionado
              if (_periodMode == _ExportPeriodMode.month) ...[
                Row(
                  children: [
                    MonthYearPickerBar(
                      currentMonthYM: _exportMonthYM,
                      availableYears: widget.store.allYearsInDatabase(),
                      onMonthChanged: (ym) => setState(() => _exportMonthYM = ym),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _exportMonthYM = todayISO().substring(0, 7);
                        });
                      },
                      child: const Text('Mês Atual',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ] else if (_periodMode == _ExportPeriodMode.custom) ...[
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = picked;
                              if (_endDate.isBefore(_startDate)) {
                                _endDate = _startDate;
                              }
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data Inicial',
                            prefixIcon: Icon(Icons.calendar_today, size: 16),
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          child: Text(
                            '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _endDate = picked;
                              if (_startDate.isAfter(_endDate)) {
                                _startDate = _endDate;
                              }
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data Final',
                            prefixIcon: Icon(Icons.event, size: 16),
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          child: Text(
                            '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // Badge de contagem e botão de exportação
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.income.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: colors.income.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list_alt, size: 16, color: colors.income),
                        const SizedBox(width: 6),
                        Text(
                          '$count lançamento${count == 1 ? '' : 's'} filtrado${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.income,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text(
                      'Exportar Lançamentos (CSV)...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onPressed: count > 0 ? _handleExportCSV : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Catálogo de Categorias Exportação
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_shared_outlined,
                  size: 24, color: colors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exportar Categorias e Subcategorias',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Exporta todas as ${widget.store.db.cats.length} categorias em formato CSV compatível.',
                      style:
                          TextStyle(fontSize: 11.5, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Exportar Categorias...'),
                onPressed: _handleExportCategories,
              ),
            ],
          ),
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
