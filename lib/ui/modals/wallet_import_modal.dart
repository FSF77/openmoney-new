import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/importers_exporters.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../services/wallet_import_service.dart';
import '../../store/money_store.dart';

/// Abre o fluxo de importação dos lançamentos exportados pelo app Carteira (Apple Wallet / Atalhos iOS CSV)
Future<void> showWalletImportModal(
  BuildContext context,
  MoneyStore store,
) async {
  if (kIsWeb) {
    // No Web permite colar o texto CSV diretamente no diálogo
    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _WalletImportReviewDialog(
          store: store,
          filePath: null,
        ),
      );
    }
    return;
  }

  final selectedPath = await NativeFilePicker.pickFile(
    title: 'Importar Lançamentos da Carteira (Atalhos iOS CSV)',
    allowedExtensions: ['csv', 'txt'],
  );
  if (selectedPath == null || selectedPath.trim().isEmpty) return;

  final cleanPath = selectedPath.trim();
  final file = File(cleanPath);
  if (!file.existsSync()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Arquivo não encontrado: $cleanPath'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    return;
  }

  if (context.mounted) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WalletImportReviewDialog(
        store: store,
        filePath: cleanPath,
      ),
    );
  }
}

class _WalletImportReviewDialog extends StatefulWidget {
  final MoneyStore store;
  final String? filePath;

  const _WalletImportReviewDialog({
    required this.store,
    required this.filePath,
  });

  @override
  State<_WalletImportReviewDialog> createState() =>
      _WalletImportReviewDialogState();
}

class _WalletImportReviewDialogState extends State<_WalletImportReviewDialog> {
  bool _isLoading = true;
  final List<WalletDraftItem> _drafts = [];
  int _selectedIndex = 0;
  bool _rememberAccountMappings = true;

  late final TextEditingController _dateCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _memoCtrl;

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController();
    _payeeCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _memoCtrl = TextEditingController();
    _loadCsvFile();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCsvFile() async {
    if (widget.filePath == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final bytes = await File(widget.filePath!).readAsBytes();
      final items = WalletImportService.parseWalletBytes(bytes, widget.store);
      if (mounted) {
        setState(() {
          _drafts
            ..clear()
            ..addAll(items);
          _isLoading = false;
          if (_drafts.isNotEmpty) {
            _selectItem(0);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _selectItem(int index) {
    if (index < 0 || index >= _drafts.length) return;
    final item = _drafts[index];
    setState(() {
      _selectedIndex = index;
      _dateCtrl.text = fmtDate(item.date);
      _payeeCtrl.text = item.payee;
      _amountCtrl.text = (item.amountCents / 100.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _memoCtrl.text = item.memo;
    });
  }

  void _recomputeDuplicate(int index) {
    if (index < 0 || index >= _drafts.length) return;
    final d = _drafts[index];
    final isDup = widget.store.db.txs.any((tx) =>
        tx.acc == d.accountId &&
        tx.date == d.date &&
        tx.amt.abs() == d.amountCents &&
        WalletImportService.normalize(tx.payee) ==
            WalletImportService.normalize(d.payee));
    d.isDuplicate = isDup;
  }

  void _saveSelected() {
    final selected = _drafts
        .where((d) => d.isSelected && d.amountCents > 0 && d.accountId.isNotEmpty)
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum lançamento válido selecionado para importar.'),
        ),
      );
      return;
    }

    if (_rememberAccountMappings) {
      for (final item in selected) {
        if (item.rawAccountName.isNotEmpty) {
          widget.store.addWalletAlias(item.rawAccountName, item.accountId);
        }
      }
    }

    int importedCount = 0;
    for (final item in selected) {
      final signedAmt =
          item.isExpense ? -item.amountCents.abs() : item.amountCents.abs();
      final cleanMemo =
          item.memo.trim().toLowerCase() == 'notas' ? '' : item.memo.trim();

      widget.store.addTransaction(
        accId: item.accountId,
        date: item.date,
        payee: item.payee.isEmpty ? 'Compra Carteira' : item.payee,
        catSelection: item.category.isEmpty ? 'Outros' : item.category,
        memo: cleanMemo,
        signedAmt: signedAmt,
        mode: 'single',
        freq: 'monthly',
        installments: 2,
      );
      importedCount++;
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ $importedCount lançamento(s) da Carteira importado(s) com sucesso!',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 760;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isNarrow ? screenWidth * 0.96 : 980,
        height: 650,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1D24) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF222631)
                    : const Color(0xFFF3F4F6),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.blueAccent,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'Importar Lançamentos da Carteira (Atalhos iOS)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_drafts.length} registro(s)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (widget.filePath != null)
                          Text(
                            widget.filePath!,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Processando lançamentos do CSV...'),
                        ],
                      ),
                    )
                  : _drafts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.inbox_outlined,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Nenhum lançamento válido encontrado no arquivo.',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Formato esperado: Data;Conta;Descrição;Nota;Valor',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : isNarrow
                          ? Column(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: _buildDraftList(isDark),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  flex: 6,
                                  child: _buildReviewPanel(context, isDark),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                SizedBox(
                                  width: 390,
                                  child: _buildDraftList(isDark),
                                ),
                                Expanded(
                                  child: _buildReviewPanel(context, isDark),
                                ),
                              ],
                            ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF222631)
                    : const Color(0xFFF3F4F6),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _rememberAccountMappings,
                          onChanged: (v) => setState(
                            () => _rememberAccountMappings = v ?? true,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Memorizar De/Para de contas (walletAliases) nas contas selecionadas',
                            style: TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _drafts.any((d) => d.isSelected)
                        ? _saveSelected
                        : null,
                    icon: const Icon(Icons.check_circle),
                    label: Text(
                      'Importar ${_drafts.where((d) => d.isSelected).length} Lançamento(s)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftList(bool isDark) {
    final allSelected = _drafts.every((d) => d.isSelected);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lançamentos (${_drafts.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (final d in _drafts) {
                        d.isSelected = !allSelected;
                      }
                    });
                  },
                  child: Text(
                    allSelected ? 'Desmarcar Todos' : 'Marcar Todos',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _drafts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final d = _drafts[idx];
                final isSelectedRow = idx == _selectedIndex;
                final accObj = widget.store.accById(d.accountId);
                final accName = accObj?.name ?? 'Conta';
                final accCur = accObj?.effectiveCurrency ??
                    widget.store.baseCurrency;

                return ListTile(
                  selected: isSelectedRow,
                  selectedTileColor: Colors.blueAccent.withValues(alpha: 0.12),
                  onTap: () => _selectItem(idx),
                  leading: Checkbox(
                    value: d.isSelected,
                    onChanged: (val) {
                      setState(() {
                        d.isSelected = val ?? false;
                      });
                    },
                  ),
                  title: Text(
                    d.payee.isEmpty ? '(Sem Descrição)' : d.payee,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${fmtDate(d.date)} • $accName • ${d.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatCurrency(d.amountCents, accCur),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: d.isExpense ? Colors.redAccent : Colors.green,
                        ),
                      ),
                      if (d.isDuplicate)
                        const Text(
                          'Duplicado',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        )
                      else if (!d.isAccountAutoMatched)
                        const Text(
                          'Revisar Conta',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel(BuildContext context, bool isDark) {
    if (_selectedIndex < 0 || _selectedIndex >= _drafts.length) {
      return const SizedBox.shrink();
    }
    final current = _drafts[_selectedIndex];
    final currentAcc = widget.store.accById(current.accountId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.payee.isEmpty
                          ? 'Lançamento #${_selectedIndex + 1}'
                          : current.payee,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (current.rawAccountName.isNotEmpty)
                      Text(
                        'Conta na Carteira (CSV): "${current.rawAccountName}"',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Despesa')),
                  ButtonSegment(value: false, label: Text('Receita')),
                ],
                selected: {current.isExpense},
                onSelectionChanged: (val) {
                  setState(() {
                    current.isExpense = val.first;
                  });
                },
              ),
            ],
          ),

          if (current.isDuplicate) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Já existe um lançamento com mesma data, valor e favorecido nesta conta. Desmarque na lista ao lado caso não queira duplicar.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Seção De/Para de Conta
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Conta de Destino no OpenMoney (De/Para)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      current.isAccountAutoMatched
                          ? '✓ Associada automaticamente'
                          : '• Selecione a conta correspondente',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: current.isAccountAutoMatched
                            ? Colors.green
                            : Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('wallet_acc_${current.id}_${current.accountId}'),
                  isExpanded: true,
                  initialValue: widget.store.db.accounts
                          .any((a) => a.id == current.accountId)
                      ? current.accountId
                      : (widget.store.db.accounts.isNotEmpty
                          ? widget.store.db.accounts.first.id
                          : null),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance),
                    isDense: true,
                  ),
                  items: widget.store.db.accounts.map((a) {
                    return DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} (${a.type})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (newAccId) {
                    if (newAccId == null) return;
                    final rawName = current.rawAccountName;
                    setState(() {
                      current.accountId = newAccId;
                      current.isAccountAutoMatched = true;
                      _recomputeDuplicate(_selectedIndex);

                      // Propaga para demais itens do mesmo arquivo que possuam o mesmo nome na Carteira
                      if (rawName.isNotEmpty) {
                        final normRaw =
                            WalletImportService.normalize(rawName);
                        for (int i = 0; i < _drafts.length; i++) {
                          if (i != _selectedIndex &&
                              WalletImportService.normalize(
                                    _drafts[i].rawAccountName,
                                  ) ==
                                  normRaw) {
                            _drafts[i].accountId = newAccId;
                            _drafts[i].isAccountAutoMatched = true;
                            _recomputeDuplicate(i);
                          }
                        }
                      }
                    });
                  },
                ),
                if (current.rawAccountName.isNotEmpty && currentAcc != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ao confirmar a importação, "${current.rawAccountName}" ficará salvo em walletAliases da conta "${currentAcc.name}".',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Data e Valor
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Data (DD/MM/AAAA)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  onChanged: (v) {
                    final parsed = parseDateString(v.trim());
                    if (parsed != null) {
                      setState(() {
                        current.date = parsed;
                        _recomputeDuplicate(_selectedIndex);
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  decoration: InputDecoration(
                    labelText:
                        'Valor (${currencyMetaFor(widget.store.accById(current.accountId)?.effectiveCurrency ?? "BRL").symbol})',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final parsedCents = parseAmountCents(v);
                    if (parsedCents != null) {
                      setState(() {
                        current.amountCents = parsedCents.abs();
                        _recomputeDuplicate(_selectedIndex);
                      });
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Descrição / Favorecido
          TextField(
            controller: _payeeCtrl,
            decoration: const InputDecoration(
              labelText: 'Descrição / Favorecido',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.storefront),
            ),
            onChanged: (v) {
              final clean = v.trim();
              final match = widget.store.lastCategoryAndType(clean);
              setState(() {
                current.payee = clean;
                if (match != null) {
                  current.category = match.category;
                  current.isExpense = match.isExpense;
                }
                _recomputeDuplicate(_selectedIndex);
              });
            },
          ),

          const SizedBox(height: 16),

          // Categoria
          Builder(
            builder: (context) {
              final catType = current.isExpense ? 'Despesa' : 'Receita';
              final catOptions = widget.store.allCategoryOptions(catType);
              final effectiveCat =
                  catOptions.any((c) => c.value == current.category)
                      ? current.category
                      : (catOptions.isNotEmpty
                          ? catOptions.first.value
                          : current.category);

              return DropdownButtonFormField<String>(
                key: ValueKey(
                  'wallet_cat_${current.id}_${current.isExpense}_$effectiveCat',
                ),
                isExpanded: true,
                initialValue: effectiveCat,
                decoration: const InputDecoration(
                  labelText: 'Categoria (Sugerida pelos Últimos Lançamentos)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: [
                  if (current.category.isNotEmpty &&
                      !catOptions.any((c) => c.value == current.category))
                    DropdownMenuItem(
                      value: current.category,
                      child: Text(
                        current.category,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ...catOptions.map(
                    (c) => DropdownMenuItem(
                      value: c.value,
                      child: Text(
                        c.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => current.category = v);
                  }
                },
              );
            },
          ),

          const SizedBox(height: 16),

          // Nota
          TextField(
            controller: _memoCtrl,
            decoration: const InputDecoration(
              labelText: 'Nota / Observação',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
            onChanged: (v) {
              current.memo = v;
            },
          ),
        ],
      ),
    );
  }
}
