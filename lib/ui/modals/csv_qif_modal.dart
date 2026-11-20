import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import 'mobile_inbox_modal.dart';
import 'ofx_reconciliation_modal.dart';
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
    builder: (ctx) => _CsvQifCenterDialog(
      store: store,
      parentContext: context,
    ),
  );
}

class _CsvQifCenterDialog extends StatefulWidget {
  final MoneyStore store;
  final BuildContext parentContext;
  const _CsvQifCenterDialog({
    required this.store,
    required this.parentContext,
  });

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

  Future<void> _handleImportAccounts() async {
    final selected = await NativeFilePicker.pickFile(
      title: 'Selecionar Arquivo CSV de Contas',
      allowedExtensions: ['csv'],
    );
    if (selected != null && selected.isNotEmpty) {
      try {
        final bytes = File(selected).readAsBytesSync();
        final summary = widget.store.importAccountsCSVBytes(bytes);
        setState(() {
          _isError = false;
          _statusMessage = '✓ ${summary.formattedMessage}';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Erro ao importar contas: $e';
        });
      }
    }
  }

  Future<void> _handleExportAccounts() async {
    final savePath = await NativeFilePicker.saveFile(
      title: 'Escolher Local para Salvar CSV de Contas',
      defaultName: 'openmoney-contas-${todayISO()}.csv',
      allowedExtensions: ['csv'],
    );

    if (savePath != null && savePath.isNotEmpty) {
      try {
        final csv = widget.store.exportAccountsCSVString();
        if (!kIsWeb) {
          final f = File(savePath);
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(csv, flush: true);
          setState(() {
            _isError = false;
            _statusMessage =
                '✓ Contas exportadas com sucesso em:\n$savePath';
          });
          return;
        }
        Clipboard.setData(ClipboardData(text: csv));
        setState(() {
          _isError = false;
          _statusMessage = '✓ Contas copiadas para a área de transferência!';
        });
      } catch (e) {
        setState(() {
          _isError = true;
          _statusMessage = 'Erro ao exportar contas: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final screenSize = MediaQuery.sizeOf(context);
    final isMobile = screenSize.width < 700;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      titlePadding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 16 : 20,
        isMobile ? 16 : 24,
        isMobile ? 12 : 16,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24),
      actionsPadding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 8 : 12,
        isMobile ? 16 : 24,
        isMobile ? 14 : 20,
      ),
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.import_export,
              color: colors.accent,
              size: isMobile ? 20 : 24,
            ),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importação / Exportação',
                  style: TextStyle(
                    fontSize: isMobile ? 15.5 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isMobile
                      ? 'OFX, CSV, QIF, Carteira iOS e Categorias'
                      : 'Conciliação OFX, lançamentos, faturas, carteira iOS e OCR (OFX, CSV & QIF)',
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: Colors.grey,
                  ),
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
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: SizedBox(
          width: isMobile ? double.maxFinite : 660,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Abas Principais: Importar Dados vs Exportar Dados
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment<int>(
                        value: 0,
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: Text(
                          isMobile ? 'Importar' : 'Importar Dados',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: Text(
                          isMobile ? 'Exportar' : 'Exportar Dados',
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
                ),
                const SizedBox(height: 16),

                if (_selectedTab == 0)
                  _buildImportTab(colors, isMobile)
                else
                  _buildExportTab(colors, isMobile),

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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Widget _buildImportTab(OpenMoneyColors colors, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpecialRoutineCard(
          colors: colors,
          icon: Icons.fact_check_outlined,
          title: 'Conciliação Bancária e Fatura (OFX / QFX)',
          subtitle:
              'Importe extratos bancários e faturas de cartão OFX, pareando lançamentos pendentes, sugerindo categorias/transferências e conferindo o saldo final.',
          buttonLabel: 'Conciliar OFX...',
          isMobile: isMobile,
          onTap: () {
            final parentCtx = widget.parentContext;
            final preferredAcc =
                _importAccountId == 'auto' ? null : _importAccountId;
            Navigator.pop(context);
            showOfxReconciliationModal(
              parentCtx,
              widget.store,
              preferredAccountId: preferredAcc,
            );
          },
        ),
        const SizedBox(height: 12),
        // Card de Configurações para Lançamentos
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 12 : 14),
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
                  fontSize: isMobile ? 13 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _importAccountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta de Destino',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text(
                      isMobile
                          ? 'Automático (coluna "Conta" / Extrato)'
                          : 'Automático (usar coluna "Conta" do arquivo / Extrato)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...widget.store.db.accounts.map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        a.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _importAccountId = v);
                },
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
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
              ),
              const SizedBox(height: 12),
              if (isMobile) ...[
                SizedBox(
                  width: double.infinity,
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
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
              ] else ...[
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
            isMobile: isMobile,
            onTap: () {
              final parentCtx = widget.parentContext;
              Navigator.pop(context);
              showMobileInboxImportFlow(parentCtx, widget.store);
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
            isMobile: isMobile,
            onTap: () {
              final parentCtx = widget.parentContext;
              Navigator.pop(context);
              showReceiptOcrImportModal(parentCtx, widget.store);
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
            isMobile: isMobile,
            onTap: () {
              final parentCtx = widget.parentContext;
              Navigator.pop(context);
              showWalletImportModal(parentCtx, widget.store);
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
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.category_outlined,
                            size: 20, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Catálogo de Categorias',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Importe árvore completa de categorias via arquivo CSV padronizado.',
                      style: TextStyle(
                          fontSize: 11.5, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Importar Categorias...'),
                        onPressed: _handleImportCategories,
                      ),
                    ),
                  ],
                )
              : Row(
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
                            style: TextStyle(
                                fontSize: 11.5, color: colors.textSecondary),
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
        const SizedBox(height: 16),

        // Contas Cadastradas
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_outlined,
                            size: 20, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Contas Cadastradas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Importe contas bancárias e cartões via arquivo CSV padronizado.',
                      style: TextStyle(
                          fontSize: 11.5, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Importar Contas...'),
                        onPressed: _handleImportAccounts,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.account_balance_outlined,
                        size: 24, color: colors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contas Cadastradas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Importe contas bancárias e cartões via arquivo CSV padronizado.',
                            style: TextStyle(
                                fontSize: 11.5, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Importar Contas...'),
                      onPressed: _handleImportAccounts,
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
    bool isMobile = false,
  }) {
    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.bgPrimary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderGlass),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: colors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: colors.borderGlass),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: onTap,
                child: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

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

  Widget _buildExportTab(OpenMoneyColors colors, bool isMobile) {
    final count = _exportCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card de Filtros de Exportação de Lançamentos
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 12 : 14),
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
                  fontSize: isMobile ? 13 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // 1. Filtro de Conta
              DropdownButtonFormField<String>(
                initialValue: _exportAccountId,
                isExpanded: true,
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
                      isMobile
                          ? 'Todas as Contas (${widget.store.db.txs.length})'
                          : 'Todas as Contas (${widget.store.db.txs.length} lançamentos na base)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...widget.store.db.accounts.map((a) {
                    final accCount = widget.store.db.txs
                        .where((t) => t.acc == a.id)
                        .length;
                    return DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} ($accCount)',
                        overflow: TextOverflow.ellipsis,
                      ),
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
                segments: [
                  ButtonSegment(
                    value: _ExportPeriodMode.all,
                    label: Text(
                      isMobile ? 'Tudo' : 'Todo o Período',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  ButtonSegment(
                    value: _ExportPeriodMode.month,
                    label: Text(
                      isMobile ? 'Mês' : 'Apenas o Mês',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  ButtonSegment(
                    value: _ExportPeriodMode.custom,
                    label: Text(
                      isMobile ? 'Período' : 'Definir Início e Fim',
                      style: const TextStyle(fontSize: 12),
                    ),
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
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    MonthYearPickerBar(
                      currentMonthYM: _exportMonthYM,
                      availableYears: widget.store.allYearsInDatabase(),
                      onMonthChanged: (ym) => setState(() => _exportMonthYM = ym),
                    ),
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
                          decoration: InputDecoration(
                            labelText: isMobile ? 'Início' : 'Data Inicial',
                            prefixIcon: const Icon(Icons.calendar_today, size: 16),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 8 : 10, vertical: 8),
                          ),
                          child: Text(
                            '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                            style: TextStyle(fontSize: isMobile ? 12 : 13),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
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
                          decoration: InputDecoration(
                            labelText: isMobile ? 'Fim' : 'Data Final',
                            prefixIcon: const Icon(Icons.event, size: 16),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 8 : 10, vertical: 8),
                          ),
                          child: Text(
                            '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}',
                            style: TextStyle(fontSize: isMobile ? 12 : 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // Badge de contagem e botão de exportação
              if (isMobile) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.income.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: colors.income.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.list_alt, size: 16, color: colors.income),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$count lançamento${count == 1 ? '' : 's'} filtrado${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.income,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
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
                ),
              ] else ...[
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
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_shared_outlined,
                            size: 20, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Exportar Categorias',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Exporta todas as ${widget.store.db.cats.length} categorias em formato CSV compatível.',
                      style: TextStyle(
                          fontSize: 11.5, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('Exportar Categorias...'),
                        onPressed: _handleExportCategories,
                      ),
                    ),
                  ],
                )
              : Row(
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
                            style: TextStyle(
                                fontSize: 11.5, color: colors.textSecondary),
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
        const SizedBox(height: 16),

        // Contas Cadastradas Exportação
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_outlined,
                            size: 20, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Exportar Contas Cadastradas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Exporta todas as ${widget.store.db.accounts.length} contas em formato CSV compatível.',
                      style: TextStyle(
                          fontSize: 11.5, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('Exportar Contas...'),
                        onPressed: _handleExportAccounts,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.account_balance_outlined,
                        size: 24, color: colors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exportar Contas Cadastradas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Exporta todas as ${widget.store.db.accounts.length} contas em formato CSV compatível.',
                            style: TextStyle(
                                fontSize: 11.5, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('Exportar Contas...'),
                      onPressed: _handleExportAccounts,
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
        final screenSize = MediaQuery.sizeOf(context);
        final isMobile = screenSize.width < 700;

        return AlertDialog(
          backgroundColor: colors.bgSecondary,
          surfaceTintColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 32,
            vertical: isMobile ? 16 : 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.borderGlass),
          ),
          titlePadding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 24,
            isMobile ? 16 : 20,
            isMobile ? 16 : 24,
            isMobile ? 12 : 16,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24),
          actionsPadding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 24,
            isMobile ? 8 : 12,
            isMobile ? 16 : 24,
            isMobile ? 14 : 20,
          ),
          title: Row(
            children: [
              Icon(Icons.folder_open_outlined,
                  color: Colors.lightBlueAccent, size: isMobile ? 20 : 24),
              SizedBox(width: isMobile ? 8 : 10),
              Expanded(
                child: Text(
                  'Base de Dados Local',
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SizedBox(
              width: isMobile ? double.maxFinite : 540,
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
                    if (isMobile) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                    ] else ...[
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
                    ],
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
