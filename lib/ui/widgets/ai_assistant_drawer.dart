import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/openmoney_models.dart';
import '../../services/ai_assistant_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/financial_insights_engine.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

Future<void> showAiAssistantModal(
  BuildContext context,
  MoneyStore store, {
  String? initialPrompt,
  String? focusAccountId,
  String? focusCategory,
}) async {
  if (initialPrompt != null && initialPrompt.trim().isNotEmpty) {
    store.pendingAiInitialPrompt = initialPrompt.trim();
  }
  if (focusAccountId != null) {
    store.pendingAiFocusAccountId = focusAccountId;
  }
  if (focusCategory != null) {
    store.pendingAiFocusCategory = focusCategory;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.92,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: AiAssistantSidePanel(
          store: store,
          isModal: true,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    ),
  );
}

class AiAssistantSidePanel extends StatefulWidget {
  final MoneyStore store;
  final bool isModal;
  final VoidCallback? onClose;

  const AiAssistantSidePanel({
    super.key,
    required this.store,
    this.isModal = false,
    this.onClose,
  });

  @override
  State<AiAssistantSidePanel> createState() => _AiAssistantSidePanelState();
}

class _AiAssistantSidePanelState extends State<AiAssistantSidePanel> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<AIAssistantMessage> _messages = <AIAssistantMessage>[];

  bool _isLoading = false;
  Uint8List? _pendingAttachmentBytes;
  String? _pendingAttachmentName;
  CloudAICapabilities _cloudCaps = const CloudAICapabilities();

  String _lastAiProvider = '';
  String _lastAiMode = '';

  @override
  void initState() {
    super.initState();
    _lastAiProvider = widget.store.aiProvider;
    _lastAiMode = widget.store.aiConsumptionMode;
    AIAssistantService.instance.initNativeListeners();
    widget.store.addListener(_onStoreChanged);
    AiInsightsCache.instance.attach(widget.store);
    AiInsightsCache.instance.addListener(_onInsightsUpdated);
    _initWelcomeMessage();
    _loadCloudCaps();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingPromptIfAny();
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    AiInsightsCache.instance.removeListener(_onInsightsUpdated);
    AiInsightsCache.instance.detach(widget.store);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onInsightsUpdated() {
    if (!mounted) return;
    setState(() {});
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _consumePendingPromptIfAny();
    if (widget.store.aiProvider != _lastAiProvider ||
        widget.store.aiConsumptionMode != _lastAiMode) {
      _lastAiProvider = widget.store.aiProvider;
      _lastAiMode = widget.store.aiConsumptionMode;
      setState(() {});
    }
  }

  Future<void> _loadCloudCaps() async {
    final caps = await AIAssistantService.instance.fetchCloudCapabilities();
    if (!mounted) return;
    setState(() {
      _cloudCaps = caps;
    });
  }

  void _initWelcomeMessage() {
    final overviewMd =
        FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
      widget.store,
      topic: 'overview',
    );
    _messages.add(
      AIAssistantMessage(
        isUser: false,
        text:
            'Olá! Sou sua **Assistente Financeira OpenMoney**.\n\n'
            '$overviewMd\n\n'
            'Você pode **lançar gastos por texto** (*"Gastei 45,90 no Uber hoje no Nubank #Transporte"*), **anexar faturas/comprovantes PDF ou foto**, ou clicar nos atalhos rápidos acima para analisar variações, faturas e recorrências.',
        providerLabel: 'Diagnóstico Local Instantâneo',
        isOfflineInsight: true,
      ),
    );
  }

  void _consumePendingPromptIfAny() {
    final pending = widget.store.consumePendingAiPrompt();
    if (pending != null && pending.trim().isNotEmpty && !_isLoading) {
      _sendPrompt(pending.trim());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickDocumentAttachment() async {
    final path = await NativeFilePicker.pickFile(
      title: 'Selecionar Comprovante, Fatura PDF, Imagem ou CSV',
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'heic', 'csv', 'txt'],
    );
    if (path == null || path.trim().isEmpty) return;

    try {
      final f = File(path);
      if (!f.existsSync()) return;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return;
      final fileName = path.split(RegExp(r'[/\\]')).last;
      if (!mounted) return;
      setState(() {
        _pendingAttachmentBytes = bytes;
        _pendingAttachmentName = fileName;
      });
    } catch (_) {}
  }

  Future<void> _sendPrompt([String? overrideText]) async {
    final text = (overrideText ?? _inputCtrl.text).trim();
    final attBytes = _pendingAttachmentBytes;
    final attName = _pendingAttachmentName;

    if (text.isEmpty && (attBytes == null || attName == null)) return;

    if (overrideText == null) {
      _inputCtrl.clear();
    }

    setState(() {
      _pendingAttachmentBytes = null;
      _pendingAttachmentName = null;
      _messages.add(
        AIAssistantMessage(
          isUser: true,
          text: text.isEmpty ? 'Analisar documento: $attName' : text,
          attachmentName: attName,
        ),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final focusAccId = widget.store.pendingAiFocusAccountId ??
          (widget.store.activeModule == NavModule.account
              ? widget.store.selectedAccountId
              : null);
      final focusCat = widget.store.pendingAiFocusCategory;

      final res = await AIAssistantService.instance.processUserMessage(
        store: widget.store,
        userMessage: text,
        focusAccountId: focusAccId,
        focusCategory: focusCat,
        attachmentBytes: attBytes,
        attachmentName: attName,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(
          AIAssistantMessage(
            isUser: false,
            text: res.reply,
            actions: res.actions,
            providerLabel: res.providerUsed,
            isOfflineInsight: res.isOffline,
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AIAssistantMessage(
            isUser: false,
            text: 'Não foi possível processar a solicitação: $e',
            providerLabel: 'Sistema',
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _runInstantOfflineInsight(String topic, String userLabel) {
    final focusAccId = widget.store.activeModule == NavModule.account
        ? widget.store.selectedAccountId
        : null;
    final md = FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
      widget.store,
      topic: topic,
      cardId: focusAccId,
    );

    final proposals = <AIActionProposal>[];
    if (topic == 'recurrences') {
      final recs =
          FinancialInsightsEngine.detectImplicitRecurrences(widget.store);
      for (final r in recs.take(5)) {
        final fmtAmt =
            formatCurrency(r.latestAmountCents.abs(), r.currency);
        proposals.add(
          AIActionProposal(
            type: 'create_recurrence',
            summary:
                'Automatizar ${r.displayPayee} ($fmtAmt · ${recurrenceFrequencyLabel(r.detectedFrequency)}) em ${r.accountName}',
            confidence: r.confidence,
            payload: {
              'startDate': r.predictedNextDateIso,
              'accountId': r.accountId,
              'payee': r.displayPayee,
              'category': r.category,
              'amountCents': r.latestAmountCents,
              'freq': r.detectedFrequency,
            },
          ),
        );
      }
    } else if (topic == 'organize') {
      final opps =
          FinancialInsightsEngine.findOrganizationOpportunities(widget.store);
      for (final o in opps
          .where((o) =>
              o.kind == 'uncategorized' &&
              o.suggestedCategory != null &&
              o.suggestedCategory!.isNotEmpty)
          .take(5)) {
        proposals.add(
          AIActionProposal(
            type: 'batch_edit_transactions',
            summary: '${o.title} → ${o.suggestedCategory}',
            payload: {
              'transactionIds': o.transactionIds,
              'newCategory': o.suggestedCategory,
            },
          ),
        );
      }
    }

    setState(() {
      _messages.add(AIAssistantMessage(isUser: true, text: userLabel));
      _messages.add(
        AIAssistantMessage(
          isUser: false,
          text: md,
          actions: proposals,
          providerLabel: 'Motor Analítico OpenMoney (Instantâneo)',
          isOfflineInsight: true,
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _copyExternalPromptBridge() async {
    final question = _inputCtrl.text.trim();
    final pkg = AIAssistantService.buildExternalPromptPackage(
      widget.store,
      userQuestion: question,
      focusAccountId: widget.store.activeModule == NavModule.account
          ? widget.store.selectedAccountId
          : null,
    );
    await Clipboard.setData(ClipboardData(text: pkg));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Contexto + Pergunta copiados! Cole no seu ChatGPT, Claude ou Gemini Web e depois clique em "Colar Resposta".',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _showPasteBridgeResponseDialog(OpenMoneyColors colors) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Row(
          children: [
            Icon(Icons.content_paste_go_outlined, color: colors.accent, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Colar Resposta do ChatGPT / Claude / Gemini',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cole abaixo a resposta (ou o bloco JSON) gerada pela IA externa para visualizar e confirmar os cartões de ação em 1 clique:',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 8,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Cole aqui a resposta ou JSON...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Interpretar Resposta'),
            onPressed: () {
              final raw = ctrl.text.trim();
              Navigator.of(ctx).pop();
              if (raw.isEmpty) return;
              final parsed = AIAssistantService.parseStructuredAIResponse(
                raw,
                providerLabel: 'IA Externa (Modo Sem Chave)',
              );
              setState(() {
                _messages.add(
                  AIAssistantMessage(
                    isUser: false,
                    text: parsed.reply,
                    actions: parsed.actions,
                    providerLabel: parsed.providerUsed,
                  ),
                );
              });
              _scrollToBottom();
            },
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showQuickAiConfigDialog(OpenMoneyColors colors) async {
    String selectedProvider = widget.store.aiProvider;
    String selectedMode = widget.store.aiConsumptionMode;
    final geminiCtrl =
        TextEditingController(text: widget.store.geminiApiKey);
    final claudeCtrl =
        TextEditingController(text: widget.store.claudeApiKey);
    final openaiCtrl =
        TextEditingController(text: widget.store.openaiApiKey);
    String testStatus = '';
    bool isTesting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final prov = AIProviderType.fromId(selectedProvider);
          final showKeyField = selectedMode == 'byok' &&
              prov != AIProviderType.appleIntelligence &&
              prov != AIProviderType.bridge;

          TextEditingController activeCtrl = geminiCtrl;
          String keyLabel = 'Chave API Google Gemini (Google AI Studio - Gratuita)';
          String keyHint = 'AIzaSy...';
          if (prov == AIProviderType.claude) {
            activeCtrl = claudeCtrl;
            keyLabel = 'Chave API Anthropic Claude (Console Anthropic)';
            keyHint = 'sk-ant-...';
          } else if (prov == AIProviderType.openai) {
            activeCtrl = openaiCtrl;
            keyLabel = 'Chave API OpenAI ChatGPT (Platform OpenAI)';
            keyHint = 'sk-proj-...';
          }

          return AlertDialog(
            backgroundColor: colors.bgSecondary,
            title: Row(
              children: [
                Icon(Icons.auto_awesome, color: colors.accent, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Configuração Rápida da Assistente IA',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Escolha o Motor de IA:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in AIProviderType.values)
                          if (p != AIProviderType.appleIntelligence ||
                              (!kIsWeb && (Platform.isMacOS || Platform.isIOS)))
                            ChoiceChip(
                              label: Text(
                                p.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: selectedProvider == p.id,
                              onSelected: (_) {
                                setModalState(() {
                                  selectedProvider = p.id;
                                  if (p == AIProviderType.bridge) {
                                    selectedMode = 'promptBridge';
                                  } else if (selectedMode == 'promptBridge') {
                                    selectedMode = 'byok';
                                  }
                                });
                              },
                            ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '2. Forma de Consumo:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        const ButtonSegment(
                          value: 'byok',
                          label: Text('Minha Chave', style: TextStyle(fontSize: 11.5)),
                          icon: Icon(Icons.key_outlined, size: 15),
                          tooltip:
                              'Usa sua própria chave de API (Gemini gratuito, Claude ou ChatGPT) conectando direto do seu dispositivo.',
                        ),
                        if (CloudSyncService.instance.isAuthenticated)
                          const ButtonSegment(
                            value: 'cloudManaged',
                            label: Text('Nuvem Cloud', style: TextStyle(fontSize: 11.5)),
                            icon: Icon(Icons.cloud_outlined, size: 15),
                            tooltip:
                                'Usa a IA integrada da nuvem OpenMoney Cloud da sua conta, sem precisar criar ou configurar chaves de API.',
                          ),
                        const ButtonSegment(
                          value: 'promptBridge',
                          label: Text('Sem Chave', style: TextStyle(fontSize: 11.5)),
                          icon: Icon(Icons.copy_all_outlined, size: 15),
                          tooltip:
                              'Gera o contexto financeiro pronto para você copiar e colar gratuitamente no ChatGPT, Claude ou Gemini Web.',
                        ),
                      ],
                      selected: {selectedMode},
                      onSelectionChanged: (s) {
                        setModalState(() {
                          selectedMode = s.first;
                          if (selectedMode == 'promptBridge') {
                            selectedProvider = AIProviderType.bridge.id;
                          } else if (selectedProvider ==
                              AIProviderType.bridge.id) {
                            selectedProvider = AIProviderType.gemini.id;
                          }
                        });
                      },
                    ),
                    if (showKeyField) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: activeCtrl,
                        obscureText: true,
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: keyLabel,
                          hintText: keyHint,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '🔒 Sua chave fica salva apenas neste aparelho (nunca entra no openmoney.json).',
                        style: TextStyle(fontSize: 11, color: colors.textSecondary),
                      ),
                    ],
                    if (testStatus.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.borderGlass),
                        ),
                        child: Text(
                          testStatus,
                          style: TextStyle(fontSize: 12, color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                icon: isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt_outlined, size: 16),
                label: const Text('Testar Conexão'),
                onPressed: isTesting
                    ? null
                    : () async {
                        setModalState(() {
                          isTesting = true;
                          testStatus = 'Testando conexão...';
                        });
                        final p = AIProviderType.fromId(selectedProvider);
                        final key = p == AIProviderType.claude
                            ? claudeCtrl.text.trim()
                            : p == AIProviderType.openai
                                ? openaiCtrl.text.trim()
                                : geminiCtrl.text.trim();
                        final res = await AIAssistantService.instance
                            .testProviderConnection(
                          provider: p,
                          apiKey: key,
                          useCloudManaged: selectedMode == 'cloudManaged',
                        );
                        setModalState(() {
                          isTesting = false;
                          testStatus = '${res.ok ? "✅" : "⚠️"} ${res.message}';
                        });
                      },
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  widget.store.setAiAssistantConfig(
                    enabled: true,
                    provider: selectedProvider,
                    consumptionMode: selectedMode,
                    geminiKey: geminiCtrl.text.trim(),
                    claudeKey: claudeCtrl.text.trim(),
                    openaiKey: openaiCtrl.text.trim(),
                  );
                  Navigator.of(ctx).pop();
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final provider = AIProviderType.fromId(widget.store.aiProvider);
    final mode = AIConsumptionMode.fromId(widget.store.aiConsumptionMode);

    final insightsCache = AiInsightsCache.instance;
    final spikesCount = insightsCache.spikes.length;
    final recsCount = insightsCache.recurrences.length;
    final oppsCount = insightsCache.opportunities.length;

    return Container(
      width: widget.isModal ? double.infinity : 410,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: widget.isModal
            ? null
            : Border(
                left: BorderSide(color: colors.borderGlass, width: 1),
              ),
      ),
      child: Column(
        children: [
          // 1. TOP HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: colors.bgPrimary.withValues(alpha: 0.55),
              border: Border(
                bottom: BorderSide(color: colors.borderGlass, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              'Assistente OpenMoney',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            margin: const EdgeInsets.only(top: 1.5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.income.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Privado',
                              style: TextStyle(
                                fontSize: 8.5,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                color: colors.income,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      InkWell(
                        onTap: () => _showQuickAiConfigDialog(colors),
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                mode == AIConsumptionMode.promptBridge
                                    ? 'Modo Sem Chave'
                                    : mode == AIConsumptionMode.cloudManaged
                                        ? '${provider.label} · Cloud (${_cloudCaps.remainingToday})'
                                        : provider.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: colors.accent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Configurar Provedor de IA (Gemini, Claude, ChatGPT)',
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => _showQuickAiConfigDialog(colors),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Limpar conversa',
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  onPressed: () {
                    setState(() {
                      _messages.clear();
                      _initWelcomeMessage();
                    });
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Fechar Assistente (Cmd/Ctrl + J)',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: colors.textSecondary,
                  ),
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      widget.store.closeAiAssistantPanel();
                    }
                  },
                ),
              ],
            ),
          ),

          // 2. STRIP DE AÇÕES RÁPIDAS (ÍCONES COMPACTOS COM TOOLTIP)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colors.bgPrimary.withValues(alpha: 0.30),
              border: Border(
                bottom: BorderSide(color: colors.borderGlass, width: 0.8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickActionIconButton(
                  colors: colors,
                  icon: Icons.trending_up_rounded,
                  tooltip: spikesCount > 0
                      ? 'Explicar Aumentos de Categorias ($spikesCount detectados)'
                      : 'Explicar Variações por Categoria',
                  highlight: spikesCount > 0,
                  onTap: () => _runInstantOfflineInsight(
                    'spikes',
                    'Por que meus gastos por categoria subiram neste mês?',
                  ),
                ),
                _buildQuickActionIconButton(
                  colors: colors,
                  icon: Icons.credit_card_rounded,
                  tooltip: 'Analisar Faturas de Cartão e Parcelas',
                  onTap: () => _runInstantOfflineInsight(
                    'invoices',
                    'Analise minhas faturas de cartão de crédito atuais e parcelas futuras.',
                  ),
                ),
                _buildQuickActionIconButton(
                  colors: colors,
                  icon: Icons.repeat_rounded,
                  tooltip: recsCount > 0
                      ? 'Detectar Assinaturas e Recorrências ($recsCount detectadas)'
                      : 'Detectar Assinaturas e Recorrências',
                  highlight: recsCount > 0,
                  onTap: () => _runInstantOfflineInsight(
                    'recurrences',
                    'Identifique assinaturas, recorrências e reajustes de preço na base.',
                  ),
                ),
                _buildQuickActionIconButton(
                  colors: colors,
                  icon: Icons.auto_fix_high_rounded,
                  tooltip: oppsCount > 0
                      ? 'Organizar Lançamentos ($oppsCount oportunidade(s) encontrada(s))'
                      : 'Organizar Lançamentos (sem categoria e duplicados)',
                  highlight: oppsCount > 0,
                  onTap: () => _runInstantOfflineInsight(
                    'organize',
                    'Organizar lançamentos sem categoria e revisar duplicidades reais',
                  ),
                ),
                _buildQuickActionIconButton(
                  colors: colors,
                  icon: Icons.document_scanner_outlined,
                  tooltip: 'Ler Comprovante, Fatura PDF ou Foto',
                  onTap: _pickDocumentAttachment,
                ),
              ],
            ),
          ),

          // 3. BARRA RÁPIDA DO MODO SEM CHAVE (PROMPT BRIDGE)
          if (widget.store.aiConsumptionMode == 'promptBridge' ||
              widget.store.aiProvider == AIProviderType.bridge.id)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.06),
                border: Border(
                  bottom: BorderSide(color: colors.borderGlass, width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.copy_all_outlined, size: 14, color: colors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Modo Sem Chave (Web):',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Copiar contexto para o ChatGPT/Claude/Gemini',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.copy_rounded,
                          size: 16, color: colors.accent),
                      onPressed: _copyExternalPromptBridge,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Colar resposta da IA externa',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.content_paste_go_rounded,
                          size: 16, color: colors.accent),
                      onPressed: () => _showPasteBridgeResponseDialog(colors),
                    ),
                  ),
                ],
              ),
            ),

          // 4. TIMELINE DE MENSAGENS E CARTÕES DE CONFIRMAÇÃO
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (ctx, idx) {
                if (idx == _messages.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Analisando seus dados financeiros...',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final msg = _messages[idx];
                return _buildMessageBubble(colors, msg);
              },
            ),
          ),

          // 5. ANEXO PENDENTE SE HOUVER
          if (_pendingAttachmentName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                border: Border(
                  top: BorderSide(color: colors.borderGlass),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.attach_file_rounded, size: 16, color: colors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _pendingAttachmentName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 15),
                    onPressed: () {
                      setState(() {
                        _pendingAttachmentBytes = null;
                        _pendingAttachmentName = null;
                      });
                    },
                  ),
                ],
              ),
            ),

          // 6. CAMPO DE ENTRADA (TEXTO + ANEXO DE DOCUMENTOS)
          RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: colors.bgPrimary,
                border: Border(
                  top: BorderSide(color: colors.borderGlass, width: 1),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Ler Comprovante, Fatura PDF ou Extrato',
                    icon: Icon(
                      Icons.upload_file_rounded,
                      color: colors.accent,
                      size: 21,
                    ),
                    onPressed: _isLoading ? null : _pickDocumentAttachment,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendPrompt(),
                      style:
                          TextStyle(fontSize: 12.5, color: colors.textPrimary),
                      decoration: InputDecoration(
                        hintText:
                            'Ex: "Gastei 48,90 no Uber hoje no Nubank" ou pergunte...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary.withValues(alpha: 0.75),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors.bgSecondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.borderGlass),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.borderGlass),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      minimumSize: const Size(38, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isLoading ? null : () => _sendPrompt(),
                    child: const Icon(
                      Icons.send_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionIconButton({
    required OpenMoneyColors colors,
    required IconData icon,
    required String tooltip,
    bool highlight = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: highlight
                ? colors.accent.withValues(alpha: 0.14)
                : colors.bgSecondary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlight
                  ? colors.accent.withValues(alpha: 0.45)
                  : colors.borderGlass,
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: highlight ? colors.accent : colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(OpenMoneyColors colors, AIAssistantMessage msg) {
    final isUser = msg.isUser;
    final cleanText = msg.text.replaceAll('**', '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 370),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isUser
                  ? colors.accent.withValues(alpha: 0.16)
                  : colors.bgPrimary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isUser
                    ? colors.accent.withValues(alpha: 0.35)
                    : colors.borderGlass,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser && msg.providerLabel != null) ...[
                  Row(
                    children: [
                      Icon(
                        msg.isOfflineInsight
                            ? Icons.bolt_rounded
                            : Icons.auto_awesome,
                        size: 12,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          msg.providerLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Copiar texto',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: cleanText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Texto copiado!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (msg.attachmentName != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.bgSecondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 13,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            msg.attachmentName!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(
                  cleanText,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.42,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (msg.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final action in msg.actions)
              _buildActionProposalCard(colors, action),
          ],
        ],
      ),
    );
  }

  Widget _buildActionProposalCard(
    OpenMoneyColors colors,
    AIActionProposal proposal,
  ) {
    if (proposal.isDiscarded) {
      return const SizedBox.shrink();
    }

    final budgetWarn = proposal.checkBudgetWarning(widget.store);
    final p = proposal.payload;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: proposal.isApplied
              ? colors.income.withValues(alpha: 0.6)
              : colors.accent.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                proposal.isApplied
                    ? Icons.check_circle_rounded
                    : Icons.task_alt_rounded,
                size: 16,
                color: proposal.isApplied ? colors.income : colors.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  proposal.summary,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (proposal.type == 'create_transaction') ...[
            _buildKeyValRow(
              colors,
              'Estabelecimento',
              (p['payee'] ?? '').toString(),
            ),
            _buildKeyValRow(
              colors,
              'Categoria',
              (p['category'] ?? 'Outros').toString(),
            ),
            _buildKeyValRow(
              colors,
              'Data',
              fmtDate((p['date'] ?? todayISO()).toString()),
            ),
            if (p['tags'] is List && (p['tags'] as List).isNotEmpty)
              _buildKeyValRow(
                colors,
                'Tags',
                (p['tags'] as List).map((t) => '#$t').join(' '),
              ),
          ],
          if (budgetWarn != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.expense.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.expense.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: colors.expense,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Atenção: Este lançamento ultrapassa o limite mensal de ${budgetWarn.categoryPath} (${formatCurrency(budgetWarn.budgetCents, budgetWarn.currency)}).',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.expense,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (proposal.isApplied)
            Row(
              children: [
                Icon(Icons.check, size: 15, color: colors.income),
                const SizedBox(width: 4),
                Text(
                  'Confirmado e gravado na base',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.income,
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Tooltip(
                  message: 'Descartar sugestão',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        proposal.isDiscarded = true;
                      });
                    },
                  ),
                ),
                if (proposal.type == 'create_transaction') ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Editar lançamento antes de salvar',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 17,
                        color: colors.accent,
                      ),
                      onPressed: () {
                        final rawAmt =
                            ((p['amountCents'] ?? p['amount_cents'] ?? 0) as num)
                                .toInt();
                        showTransactionCreateModal(
                          context,
                          widget.store,
                          initialAccountId: p['accountId']?.toString(),
                          initialDateIso: p['date']?.toString(),
                          initialPayee: p['payee']?.toString(),
                          initialAmountCents: rawAmt.abs(),
                          initialCategory: p['category']?.toString(),
                          initialMemo: p['memo']?.toString(),
                          initialIsExpense: rawAmt <= 0,
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Confirmar e gravar na base',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      backgroundColor: colors.income.withValues(alpha: 0.16),
                      hoverColor: colors.income.withValues(alpha: 0.28),
                    ),
                    icon: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: colors.income,
                    ),
                    onPressed: () {
                      final msg = proposal.executeOnStore(widget.store);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildKeyValRow(
    OpenMoneyColors colors,
    String label,
    String value,
  ) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
