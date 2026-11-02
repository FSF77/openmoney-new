import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/gemini_receipt_service.dart';
import '../../services/local_ocr_service.dart';
import '../../services/native_file_picker.dart';
import '../../services/receipt_parser_engine.dart';
import '../../store/money_store.dart';

/// Abre o fluxo de importação inteligente de comprovantes via pasta selecionada
Future<void> showReceiptOcrImportModal(
  BuildContext context,
  MoneyStore store,
) async {
  if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A importação de comprovantes por OCR está disponível para macOS e Windows.'),
      ),
    );
    return;
  }

  final selectedFolder = await NativeFilePicker.pickFolder(
    title: 'Selecionar Pasta de Comprovantes (PDFs e Imagens)',
  );
  if (selectedFolder == null || selectedFolder.isEmpty) return;

  final dir = Directory(selectedFolder);
  if (!dir.existsSync()) return;

  if (context.mounted) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReceiptOcrReviewDialog(
        store: store,
        folderPath: selectedFolder,
      ),
    );
  }
}

class _ReceiptOcrReviewDialog extends StatefulWidget {
  final MoneyStore store;
  final String folderPath;

  const _ReceiptOcrReviewDialog({
    required this.store,
    required this.folderPath,
  });

  @override
  State<_ReceiptOcrReviewDialog> createState() => _ReceiptOcrReviewDialogState();
}

class _ReceiptOcrReviewDialogState extends State<_ReceiptOcrReviewDialog> {
  bool _isLoading = true;
  String _loadingMessage = 'Varrendo arquivos da pasta...';
  double _progress = 0.0;
  final List<ParsedReceiptDraft> _drafts = [];
  int _selectedIndex = 0;
  bool _moveToProcessed = true;

  // Controllers para edição do item selecionado
  late final TextEditingController _dateCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController();
    _payeeCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _processDirectory();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _processDirectory() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Varrendo arquivos da pasta...';
      _progress = 0.0;
      _drafts.clear();
    });

    try {
      final dir = Directory(widget.folderPath);
      final validExtensions = {'pdf', 'png', 'jpg', 'jpeg', 'heic'};
      final allFiles = dir.listSync(followLinks: false);

      final targetFiles = allFiles.whereType<File>().where((file) {
        final name = file.uri.pathSegments.last.toLowerCase();
        if (name.startsWith('.')) return false;
        final ext = name.split('.').last;
        return validExtensions.contains(ext);
      }).toList();

      if (targetFiles.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadingMessage = 'Nenhum comprovante (PDF ou imagem) encontrado na pasta.';
          });
        }
        return;
      }

      for (var i = 0; i < targetFiles.length; i++) {
        final f = targetFiles[i];
        final fileName = f.uri.pathSegments.last;
        if (mounted) {
          setState(() {
            _progress = (i + 1) / targetFiles.length;
            _loadingMessage = widget.store.isGeminiAiEnabled && widget.store.geminiApiKey.isNotEmpty
                ? 'Analisando com IA (${i + 1}/${targetFiles.length}): $fileName...'
                : 'Lendo e analisando (${i + 1}/${targetFiles.length}): $fileName...';
          });
        }

        ParsedReceiptDraft? draft;

        // 1. Extrai texto via OCR nativo
        final extractedText = await LocalOcrService.extractText(f.path);

        // 2. Tenta análise por IA se ativada
        if (widget.store.isGeminiAiEnabled && widget.store.geminiApiKey.isNotEmpty) {
          try {
            final aiRes = await GeminiReceiptService.analyzeReceipt(
              filePath: f.path,
              apiKey: widget.store.geminiApiKey,
              extractedText: extractedText,
            );
            if (aiRes != null) {
              var targetAcc = '';
              if (aiRes.detectedBank.isNotEmpty) {
                for (final acc in widget.store.db.accounts) {
                  if (acc.name.toLowerCase().contains(aiRes.detectedBank.toLowerCase())) {
                    targetAcc = acc.id;
                    break;
                  }
                }
              }
              if (targetAcc.isEmpty) {
                targetAcc = widget.store.db.accounts.isNotEmpty ? widget.store.db.accounts.first.id : '';
              }

              var cat = 'Outros';
              var isExp = aiRes.isExpense;
              final history = widget.store.lastCategoryAndType(aiRes.payee);
              if (history != null) {
                cat = history.category;
                isExp = history.isExpense;
              }

              draft = ParsedReceiptDraft(
                filePath: f.path,
                fileName: fileName,
                date: aiRes.date.isEmpty ? todayISO() : aiRes.date,
                payee: aiRes.payee,
                amountCents: aiRes.amountCents,
                isExpense: isExp,
                accountId: targetAcc,
                category: cat,
                rawOcrText: 'Análise por IA Gemini Flash:\n${aiRes.rawJson}\n\nTexto OCR Original:\n$extractedText',
                isSelected: true,
                hasError: aiRes.amountCents == 0 || aiRes.payee.isEmpty,
              );
            }
          } catch (_) {}
        }

        // 3. Fallback OCR nativo se IA desativada ou falhar
        if (draft == null) {
          draft = ReceiptParserEngine.parse(
            filePath: f.path,
            fileName: fileName,
            text: extractedText,
            store: widget.store,
          );
        }

        _drafts.add(draft);
      }
    } catch (e) {
      debugPrint('Erro ao processar pasta OCR: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (_drafts.isNotEmpty) {
          _selectItem(0);
        }
      });
    }
  }

  void _selectItem(int index) {
    if (index < 0 || index >= _drafts.length) return;
    setState(() {
      _selectedIndex = index;
      final current = _drafts[index];
      _dateCtrl.text = current.date;
      _payeeCtrl.text = current.payee;
      _amountCtrl.text = (current.amountCents / 100.0).toStringAsFixed(2);
    });
  }

  void _showAiConfigModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _GeminiAiConfigDialog(
        store: widget.store,
        onSaved: () {
          _processDirectory();
        },
      ),
    );
  }

  void _saveAllSelected() {
    final selectedItems = _drafts.where((d) => d.isSelected).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum comprovante selecionado para importação.')),
      );
      return;
    }

    final processedDir = Directory('${widget.folderPath}/processados');
    if (_moveToProcessed && !processedDir.existsSync()) {
      try {
        processedDir.createSync(recursive: true);
      } catch (e) {
        debugPrint('Não foi possível criar pasta processados: $e');
      }
    }

    var importedCount = 0;
    for (final item in selectedItems) {
      if (item.amountCents <= 0 || item.accountId.isEmpty) continue;

      final signedAmt = item.isExpense ? -item.amountCents.abs() : item.amountCents.abs();

      widget.store.addTransaction(
        accId: item.accountId,
        date: item.date,
        payee: item.payee,
        catSelection: item.category,
        signedAmt: signedAmt,
        memo: 'Importado via OCR: ${item.fileName}',
      );
      importedCount++;

      // Move arquivo conferido para pasta processados
      if (_moveToProcessed && processedDir.existsSync()) {
        try {
          final originalFile = File(item.filePath);
          if (originalFile.existsSync()) {
            final destPath = '${processedDir.path}/${item.fileName}';
            originalFile.renameSync(destPath);
          }
        } catch (e) {
          debugPrint('Falha ao mover arquivo ${item.fileName}: $e');
        }
      }
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✓ $importedCount lançamento(s) importado(s) com sucesso!'
          '${_moveToProcessed ? ' Comprovantes movidos para "processados/".' : ''}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        width: size.width * 0.85,
        height: size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E222A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.document_scanner, color: Colors.blueAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Importação de Comprovantes',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.store.isGeminiAiEnabled && widget.store.geminiApiKey.isNotEmpty
                                    ? Colors.blueAccent.withValues(alpha: 0.15)
                                    : Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.store.isGeminiAiEnabled && widget.store.geminiApiKey.isNotEmpty
                                    ? 'IA Gemini Ativa'
                                    : 'OCR Nativo',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: widget.store.isGeminiAiEnabled && widget.store.geminiApiKey.isNotEmpty
                                      ? Colors.blueAccent
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Pasta: ${widget.folderPath}',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showAiConfigModal(context),
                    icon: Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: widget.store.isGeminiAiEnabled ? Colors.blueAccent : Colors.grey,
                    ),
                    label: Text(
                      widget.store.isGeminiAiEnabled ? 'IA Ativada' : 'Ativar IA (Gemini)',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.store.isGeminiAiEnabled ? Colors.blueAccent : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),

            // Conteúdo
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(value: _progress > 0 ? _progress : null),
                          const SizedBox(height: 20),
                          Text(_loadingMessage, style: const TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                    )
                  : _drafts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_open, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(_loadingMessage, style: const TextStyle(fontSize: 15)),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            // Painel Esquerdo: Lista de Comprovantes
                            SizedBox(
                              width: 380,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${_drafts.where((d) => d.isSelected).length} de ${_drafts.length} selecionados',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    for (var d in _drafts) {
                                                      d.isSelected = true;
                                                    }
                                                  });
                                                },
                                                child: const Text('Todos', style: TextStyle(fontSize: 12)),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    for (var d in _drafts) {
                                                      d.isSelected = false;
                                                    }
                                                  });
                                                },
                                                child: const Text('Nenhum', style: TextStyle(fontSize: 12)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: _drafts.length,
                                        itemBuilder: (context, idx) {
                                          final item = _drafts[idx];
                                          final isCur = idx == _selectedIndex;

                                          return InkWell(
                                            onTap: () => _selectItem(idx),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isCur
                                                    ? (isDark ? Colors.blueAccent.withOpacity(0.18) : Colors.blue.withOpacity(0.1))
                                                    : Colors.transparent,
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Checkbox(
                                                    value: item.isSelected,
                                                    onChanged: (val) {
                                                      setState(() {
                                                        item.isSelected = val ?? false;
                                                      });
                                                    },
                                                  ),
                                                  Icon(
                                                    item.fileName.toLowerCase().endsWith('.pdf')
                                                        ? Icons.picture_as_pdf
                                                        : Icons.image,
                                                    size: 24,
                                                    color: item.hasError ? Colors.amber : Colors.blueAccent,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          item.payee.isNotEmpty ? item.payee : item.fileName,
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '${item.date} • ${item.category}',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: isDark ? Colors.white60 : Colors.black54,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Text(
                                                    'R\$ ${(item.amountCents / 100.0).toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: item.isExpense ? Colors.redAccent : Colors.green,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Painel Direito: Formulário de Conferência & Edição
                            Expanded(
                              child: _drafts.isEmpty
                                  ? const SizedBox.shrink()
                                  : _buildReviewPanel(context, isDark),
                            ),
                          ],
                        ),
            ),

            // Barra Inferior de Ações
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _moveToProcessed,
                    onChanged: (v) => setState(() => _moveToProcessed = v ?? true),
                  ),
                  const Text('Mover comprovantes conferidos para subpasta "processados/"'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _drafts.any((d) => d.isSelected) ? _saveAllSelected : null,
                    icon: const Icon(Icons.check_circle),
                    label: Text('Importar ${_drafts.where((d) => d.isSelected).length} Lançamentos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  Widget _buildReviewPanel(BuildContext context, bool isDark) {
    if (_selectedIndex < 0 || _selectedIndex >= _drafts.length) {
      return const SizedBox.shrink();
    }
    final current = _drafts[_selectedIndex];

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
                      current.fileName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      current.filePath,
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                      overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 24),

          // Campos Lado a Lado
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Data (AAAA-MM-DD)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  onChanged: (v) => current.date = v.trim(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor (R\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final normalized = v.replaceAll(',', '.').trim();
                    final parsed = double.tryParse(normalized);
                    if (parsed != null) {
                      current.amountCents = (parsed * 100).round();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Favorecido
          TextField(
            controller: _payeeCtrl,
            decoration: const InputDecoration(
              labelText: 'Favorecido / Estabelecimento',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            onChanged: (v) {
              current.payee = v.trim();
              // Atualiza categoria inteligente com base no novo nome
              final match = widget.store.lastCategoryAndType(current.payee);
              if (match != null) {
                setState(() {
                  current.category = match.category;
                  current.isExpense = match.isExpense;
                });
              }
            },
          ),
          const SizedBox(height: 16),

          // Conta e Categoria
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: widget.store.db.accounts.any((a) => a.id == current.accountId)
                      ? current.accountId
                      : (widget.store.db.accounts.isNotEmpty ? widget.store.db.accounts.first.id : null),
                  decoration: const InputDecoration(
                    labelText: 'Conta',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance),
                  ),
                  items: widget.store.db.accounts.map((a) {
                    return DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => current.accountId = v);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final catType = current.isExpense ? 'Despesa' : 'Receita';
                    final catOptions = widget.store.allCategoryOptions(catType);
                    final effectiveCat = catOptions.any((c) => c.value == current.category)
                        ? current.category
                        : (catOptions.isNotEmpty ? catOptions.first.value : current.category);

                    return DropdownButtonFormField<String>(
                      initialValue: effectiveCat,
                      decoration: const InputDecoration(
                        labelText: 'Categoria (Sugerida pelo Histórico)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: [
                        if (current.category.isNotEmpty && !catOptions.any((c) => c.value == current.category))
                          DropdownMenuItem(value: current.category, child: Text(current.category)),
                        ...catOptions.map((c) => DropdownMenuItem(value: c.value, child: Text(c.label))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => current.category = v);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Text(
            'Texto Extraído do Documento (OCR):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            height: 160,
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                current.rawOcrText.isEmpty
                    ? '(Nenhum texto pôde ser extraído deste arquivo)'
                    : current.rawOcrText,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeminiAiConfigDialog extends StatefulWidget {
  final MoneyStore store;
  final VoidCallback onSaved;

  const _GeminiAiConfigDialog({
    required this.store,
    required this.onSaved,
  });

  @override
  State<_GeminiAiConfigDialog> createState() => _GeminiAiConfigDialogState();
}

class _GeminiAiConfigDialogState extends State<_GeminiAiConfigDialog> {
  late bool _isEnabled;
  late final TextEditingController _keyCtrl;

  @override
  void initState() {
    super.initState();
    _isEnabled = widget.store.isGeminiAiEnabled;
    _keyCtrl = TextEditingController(text: widget.store.geminiApiKey);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Configuração de IA (Google Gemini)'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativar Reconhecimento por IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text(
                'Usa a visão multimodal do Gemini Flash para reconhecer lojas, logotipos e totais.',
                style: TextStyle(fontSize: 12),
              ),
              value: _isEnabled,
              onChanged: (v) => setState(() => _isEnabled = v),
            ),
            const SizedBox(height: 12),
            if (_isEnabled) ...[
              TextField(
                controller: _keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Sua Chave de API Gemini (Gratuita - BYOK)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Não tem uma chave?', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(width: 6),
                  SelectableText(
                    'https://aistudio.google.com/app/apikey',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.lightBlueAccent : Colors.blue,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Com a IA desativada, o app utiliza o motor de OCR nativo do sistema operacional.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.store.setGeminiConfig(
              enabled: _isEnabled,
              apiKey: _keyCtrl.text.trim(),
            );
            Navigator.of(context).pop();
            widget.onSaved();
          },
          child: const Text('Salvar Configurações'),
        ),
      ],
    );
  }
}
