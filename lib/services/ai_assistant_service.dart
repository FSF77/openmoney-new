import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'cloud_sync_service.dart';
import 'financial_insights_engine.dart';
import 'local_ocr_service.dart';
import 'ofx_reconciliation_service.dart';
import 'platform_io.dart';
import 'shortcut_url_service.dart';
import 'wallet_import_service.dart';

enum AIProviderType {
  gemini('gemini', 'Google Gemini', 'Gemini Flash (Rápido & Multimodal)'),
  claude('claude', 'Anthropic Claude', 'Claude Sonnet / Haiku'),
  openai('openai', 'OpenAI ChatGPT', 'GPT-4o / GPT-4o-mini'),
  appleIntelligence(
    'apple',
    'Apple Intelligence',
    'IA Local da Apple (On-Device / Offline)',
  ),
  bridge(
    'bridge',
    'Modo Sem Chave',
    'Copiar Prompt / Colar Resposta (ChatGPT / Claude / Gemini Web)',
  );

  final String id;
  final String label;
  final String subtitle;
  const AIProviderType(this.id, this.label, this.subtitle);

  static AIProviderType fromId(String? raw) {
    final clean = (raw ?? '').trim().toLowerCase();
    for (final p in AIProviderType.values) {
      if (p.id == clean) return p;
    }
    return AIProviderType.gemini;
  }
}

enum AIConsumptionMode {
  byok('byok', 'Minha Chave (BYOK)'),
  cloudManaged('cloudManaged', 'OpenMoney Cloud (Gerenciado)'),
  promptBridge('promptBridge', 'Modo Sem Chave (Copiar & Colar)');

  final String id;
  final String label;
  const AIConsumptionMode(this.id, this.label);

  static AIConsumptionMode fromId(String? raw) {
    final clean = (raw ?? '').trim();
    for (final m in AIConsumptionMode.values) {
      if (m.id == clean) return m;
    }
    return AIConsumptionMode.byok;
  }
}

class AIActionProposal {
  final String id;
  final String type;
  final String summary;
  final double confidence;
  final Map<String, dynamic> payload;
  bool isApplied;
  bool isDiscarded;

  AIActionProposal({
    String? id,
    required this.type,
    required this.summary,
    this.confidence = 0.92,
    required this.payload,
    this.isApplied = false,
    this.isDiscarded = false,
  }) : id = id ?? uid();

  factory AIActionProposal.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final mapPayload = rawPayload is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawPayload)
        : rawPayload is Map
            ? Map<String, dynamic>.from(rawPayload)
            : <String, dynamic>{};

    return AIActionProposal(
      id: json['id']?.toString() ?? uid(),
      type: (json['type'] ?? 'create_transaction').toString().trim(),
      summary: (json['summary'] ?? 'Ação sugerida pela Assistente')
          .toString()
          .trim(),
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0.90)
          .clamp(0.0, 1.0),
      payload: mapPayload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'summary': summary,
        'confidence': confidence,
        'payload': payload,
      };

  /// Verifica se esta proposta (quando for `create_transaction`) ultrapassa o limite de gastos mensal (ADR 021).
  BudgetCheckResult? checkBudgetWarning(MoneyStore store) {
    if (type != 'create_transaction') return null;
    final accId = _resolveAccountId(store, payload['accountId']?.toString());
    final date = (payload['date'] ?? todayISO()).toString();
    final cat = (payload['category'] ?? 'Outros').toString();
    final signedCents = _extractSignedCents(payload);
    final installments =
        ((payload['installments'] as num?)?.toInt() ?? 1).clamp(1, 120);
    return store.checkBudgetExceeded(
      accId: accId,
      date: date,
      catSelection: cat,
      signedAmt: signedCents,
      payee: payload['payee']?.toString(),
      mode: installments > 1 ? 'installment' : 'single',
      installments: installments,
    );
  }

  static String _resolveAccountId(MoneyStore store, String? hint) {
    final raw = (hint ?? '').trim();
    if (raw.isNotEmpty) {
      final direct = store.accById(raw);
      if (direct != null) return direct.id;
      final resolved =
          WalletImportService.resolveAccount(raw, store.db.accounts);
      if (resolved.accountId.isNotEmpty) return resolved.accountId;
    }
    if (store.selectedAccountId.isNotEmpty &&
        store.accById(store.selectedAccountId) != null) {
      return store.selectedAccountId;
    }
    if (store.activeAccounts.isNotEmpty) {
      return store.activeAccounts.first.id;
    }
    return store.db.accounts.isNotEmpty ? store.db.accounts.first.id : 'a1';
  }

  static int _extractSignedCents(Map<String, dynamic> p) {
    int intVal = 0;
    if (p.containsKey('amountCents') || p.containsKey('amount_cents')) {
      final rawAmt = p['amountCents'] ?? p['amount_cents'] ?? 0;
      if (rawAmt is int) {
        intVal = rawAmt;
      } else if (rawAmt is double) {
        intVal = (rawAmt % 1) != 0 ? (rawAmt * 100).round() : rawAmt.toInt();
      } else {
        final str = rawAmt.toString().trim();
        intVal = int.tryParse(str) ?? (parseCents(str) ?? 0);
      }
    } else if (p.containsKey('amount') || p.containsKey('limit')) {
      final rawAmt = p['amount'] ?? p['limit'] ?? 0;
      if (rawAmt is num) {
        intVal = (rawAmt * 100).round();
      } else {
        intVal = parseCents(rawAmt.toString()) ?? 0;
      }
    }
    if (p.containsKey('isExpense') || p.containsKey('is_expense')) {
      final isExp = (p['isExpense'] ?? p['is_expense']) == true;
      return isExp ? -intVal.abs() : intVal.abs();
    }
    return intVal;
  }

  /// Executa a ação confirmada pelo usuário no `MoneyStore` com total segurança contábil e sincronização Sync v2.
  String executeOnStore(MoneyStore store) {
    switch (type) {
      case 'create_transaction':
        final accId =
            _resolveAccountId(store, payload['accountId']?.toString());
        final date = (payload['date'] ?? todayISO()).toString().trim();
        final payee = (payload['payee'] ?? 'Lançamento').toString().trim();
        final signedAmt = _extractSignedCents(payload);
        final isExpense = signedAmt <= 0;
        String category = (payload['category'] ?? '').toString().trim();
        if (category.isEmpty) {
          final hist = store.lastCategoryAndType(payee, isExpense: isExpense);
          category = hist?.category ??
              (store.allCategoryPaths(isExpense ? 'Despesa' : 'Receita').firstOrNull ??
                  'Outros');
        }
        final memo = (payload['memo'] ?? '').toString().trim();
        final installments =
            ((payload['installments'] as num?)?.toInt() ?? 1).clamp(1, 120);
        final customIk = payload['invoiceKey']?.toString().trim();
        final tags = <String>[
          if (payload['tags'] is List)
            ...(payload['tags'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
        ];

        store.addTransaction(
          accId: accId,
          date: date.isEmpty ? todayISO() : date,
          payee: payee,
          catSelection: category,
          memo: memo,
          signedAmt: signedAmt,
          mode: installments > 1 ? 'installment' : 'single',
          installments: installments,
          customIk: (customIk != null && customIk.isNotEmpty) ? customIk : null,
          tags: tags.isEmpty ? null : tags,
        );
        isApplied = true;
        final accName = store.accById(accId)?.name ?? accId;
        final cur = store.accById(accId)?.effectiveCurrency ?? store.baseCurrency;
        return 'Lançamento "$payee" (${formatCurrency(signedAmt.abs(), cur)}) registrado em $accName.';

      case 'create_transfer':
        final fromId = _resolveAccountId(
          store,
          (payload['fromAccountId'] ?? payload['accountId'])?.toString(),
        );
        final toId = _resolveAccountId(
          store,
          (payload['toAccountId'] ?? payload['peerAccountId'])?.toString(),
        );
        final date = (payload['date'] ?? todayISO()).toString().trim();
        final absCents = _extractSignedCents(payload).abs();
        final memo = (payload['memo'] ?? '').toString().trim();
        final rate = (payload['rate'] as num?)?.toDouble();

        store.addTransaction(
          accId: fromId,
          date: date.isEmpty ? todayISO() : date,
          payee: 'Transferência',
          catSelection: 'xfer:$toId',
          memo: memo,
          signedAmt: -absCents,
          txRate: rate,
        );
        isApplied = true;
        final fromName = store.accById(fromId)?.name ?? fromId;
        final toName = store.accById(toId)?.name ?? toId;
        return 'Transferência registrada de $fromName para $toName.';

      case 'create_recurrence':
        final accId =
            _resolveAccountId(store, payload['accountId']?.toString());
        final peerRaw = payload['peerAccountId']?.toString().trim();
        final peerId = (peerRaw != null && peerRaw.isNotEmpty)
            ? _resolveAccountId(store, peerRaw)
            : null;
        final date =
            (payload['startDate'] ?? payload['date'] ?? todayISO()).toString();
        final payee = (payload['payee'] ?? 'Recorrência').toString().trim();
        final freq = (payload['freq'] ?? 'monthly').toString().trim();
        final signedAmt = _extractSignedCents(payload);
        final category = (peerId != null && peerId.isNotEmpty)
            ? 'xfer:$peerId'
            : (payload['category'] ?? 'Outros').toString().trim();
        final memo = (payload['memo'] ?? '').toString().trim();

        store.addTransaction(
          accId: accId,
          date: date,
          payee: payee,
          catSelection: category,
          memo: memo,
          signedAmt: signedAmt,
          mode: 'recurring',
          freq: freq,
        );
        isApplied = true;
        return 'Recorrência "$payee" (${recurrenceFrequencyLabel(freq)}) criada com sucesso.';

      case 'batch_edit_transactions':
        final rawIds = payload['transactionIds'] ?? payload['txIds'];
        final ids = <String>{
          if (rawIds is List)
            ...rawIds.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
        };
        final newCat = payload['newCategory']?.toString().trim();
        final newPayee = payload['newPayee']?.toString().trim();
        final rawTags = payload['tags'];
        final tags = <String>[
          if (rawTags is List)
            ...rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
        ];

        final count = store.batchUpdateTransactions(
          ids: ids,
          payload: BatchTransactionEditPayload(
            applyCategory: newCat != null && newCat.isNotEmpty,
            category: newCat ?? '',
            applyPayee: newPayee != null && newPayee.isNotEmpty,
            payee: newPayee ?? '',
            applyTags: tags.isNotEmpty,
            tagMode: BatchTagMode.add,
            tags: tags,
          ),
        );
        isApplied = true;
        return '$count lançamento(s) organizados em lote.';

      case 'create_prediction':
        final accId =
            _resolveAccountId(store, payload['accountId']?.toString());
        final date = (payload['date'] ?? '${store.month}-28').toString().trim();
        final cat = (payload['category'] ?? 'Outros').toString().trim();
        final absCents = _extractSignedCents(payload).abs();
        String payee = (payload['payee'] ?? 'Previsão $cat').toString().trim();
        if (!isPredictionPayee(payee)) {
          payee = 'Previsão $payee';
        }
        final memo = memoWithBaseTag(
          (payload['memo'] ?? '').toString().trim(),
          absCents,
        );

        store.addTransaction(
          accId: accId,
          date: date,
          payee: payee,
          catSelection: cat,
          memo: memo,
          signedAmt: -absCents,
        );
        isApplied = true;
        return 'Previsão "$payee" criada para $cat.';

      case 'set_budget':
        final cat = (payload['categoryPath'] ?? payload['category'] ?? '')
            .toString()
            .trim();
        final int limitCents;
        if (payload.containsKey('limitCents') ||
            payload.containsKey('amountCents')) {
          final rawLim = payload['limitCents'] ?? payload['amountCents'] ?? 0;
          limitCents = (rawLim is num
                  ? rawLim.toInt()
                  : (int.tryParse(rawLim.toString()) ??
                      (parseCents(rawLim.toString()) ?? 0)))
              .abs();
        } else {
          limitCents = _extractSignedCents(payload).abs();
        }
        if (cat.isNotEmpty && limitCents >= 0) {
          store.setBudget(cat, limitCents);
          isApplied = true;
          return 'Limite mensal de $cat atualizado para ${formatCurrency(limitCents, store.baseCurrency)}.';
        }
        return 'Categoria inválida para limite de gastos.';

      case 'reconcile_document_items':
        final rawItems = payload['items'];
        if (rawItems is! List) return 'Nenhum item para importar.';
        int createdCount = 0;
        int reconciledCount = 0;
        for (final item in rawItems) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          if (map['selected'] == false) continue;

          final matchedId = map['matchedExistingTxId']?.toString();
          if (matchedId != null && matchedId.isNotEmpty) {
            final idx = store.db.txs.indexWhere((t) => t.id == matchedId);
            if (idx != -1 && !store.db.txs[idx].rec) {
              store.toggleReconciled(matchedId);
              reconciledCount++;
            }
          } else {
            final accId =
                _resolveAccountId(store, map['accountId']?.toString());
            final date = (map['dateIso'] ?? map['date'] ?? todayISO()).toString();
            final payee = (map['payee'] ?? 'Documento').toString();
            final signedAmt = _extractSignedCents(map);
            final cat = (map['category'] ?? 'Outros').toString();
            final memo = (map['memo'] ?? '').toString();
            final tags = <String>[
              if (map['tags'] is List)
                ...(map['tags'] as List).map((e) => e.toString()),
            ];
            store.addTransaction(
              accId: accId,
              date: date,
              payee: payee,
              catSelection: cat,
              memo: memo,
              signedAmt: signedAmt,
              tags: tags.isEmpty ? null : tags,
            );
            createdCount++;
          }
        }
        isApplied = true;
        return 'Documento processado: $createdCount novo(s) lançamento(s) e $reconciledCount conciliado(s).';

      default:
        return 'Ação não reconhecida ($type).';
    }
  }
}

class AIAssistantMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final List<AIActionProposal> actions;
  final String? providerLabel;
  final String? attachmentName;
  final bool isOfflineInsight;

  AIAssistantMessage({
    String? id,
    required this.isUser,
    required this.text,
    DateTime? timestamp,
    this.actions = const [],
    this.providerLabel,
    this.attachmentName,
    this.isOfflineInsight = false,
  })  : id = id ?? uid(),
        timestamp = timestamp ?? DateTime.now();
}

class AIAssistantResponse {
  final String reply;
  final List<AIActionProposal> actions;
  final AIQueryFilter? followUpQuery;
  final String providerUsed;
  final bool isOffline;

  const AIAssistantResponse({
    required this.reply,
    this.actions = const [],
    this.followUpQuery,
    required this.providerUsed,
    this.isOffline = false,
  });
}

class CloudAICapabilities {
  final bool managedAvailable;
  final List<String> managedProviders;
  final int dailyLimit;
  final int usedToday;

  const CloudAICapabilities({
    this.managedAvailable = false,
    this.managedProviders = const [],
    this.dailyLimit = 25,
    this.usedToday = 0,
  });

  int get remainingToday => (dailyLimit - usedToday).clamp(0, dailyLimit);

  factory CloudAICapabilities.fromJson(Map<String, dynamic> json) {
    return CloudAICapabilities(
      managedAvailable: json['managedAvailable'] == true,
      managedProviders: (json['managedProviders'] is List)
          ? (json['managedProviders'] as List).map((e) => e.toString()).toList()
          : const [],
      dailyLimit: (json['dailyLimit'] as num?)?.toInt() ?? 25,
      usedToday: (json['usedToday'] as num?)?.toInt() ?? 0,
    );
  }
}

class AIAssistantService {
  AIAssistantService._();
  static final AIAssistantService instance = AIAssistantService._();

  static const MethodChannel _appleChannel =
      MethodChannel('openmoney/apple_intelligence');

  bool? _cachedAppleIntelligenceAvailable;
  bool _nativeListenersRegistered = false;
  String? _lastProviderError;

  String? get lastProviderError => _lastProviderError;

  void initNativeListeners() {
    if (_nativeListenersRegistered || kIsWeb) return;
    _nativeListenersRegistered = true;
    try {
      _appleChannel.setMethodCallHandler((call) async {
        if (call.method == 'onSiriCommand') {
          final args = call.arguments;
          if (args is Map && args['prompt'] != null) {
            final prompt = args['prompt'].toString().trim();
            if (prompt.isNotEmpty) {
              ShortcutUrlService.instance.enqueueAiPrompt(prompt);
            }
          }
        }
        return null;
      });
    } catch (_) {}
  }

  /// Verifica se o dispositivo suporta Apple Intelligence (`FoundationModels`) nativamente.
  Future<bool> isAppleIntelligenceSupported() async {
    if (_cachedAppleIntelligenceAvailable != null) {
      return _cachedAppleIntelligenceAvailable!;
    }
    if (kIsWeb) {
      _cachedAppleIntelligenceAvailable = false;
      return false;
    }
    if (!Platform.isMacOS && !Platform.isIOS) {
      _cachedAppleIntelligenceAvailable = false;
      return false;
    }
    try {
      final res =
          await _appleChannel.invokeMethod<bool>('checkAvailability');
      _cachedAppleIntelligenceAvailable = res ?? true;
      return _cachedAppleIntelligenceAvailable!;
    } catch (_) {
      // Em macOS Desktop, podemos operar via /usr/bin/swift + motor híbrido local
      _cachedAppleIntelligenceAvailable = Platform.isMacOS || Platform.isIOS;
      return _cachedAppleIntelligenceAvailable!;
    }
  }

  /// Consulta as capacidades e cota do OpenMoney Cloud (`/api/ai/capabilities`).
  Future<CloudAICapabilities> fetchCloudCapabilities() async {
    final cloud = CloudSyncService.instance;
    if (!cloud.isAuthenticated) {
      return const CloudAICapabilities();
    }
    try {
      final base = cloud.apiBaseUrl;
      final res = await platformHttpRequest(
        method: 'GET',
        url: '$base/api/ai/capabilities',
        headers: {
          'Authorization': 'Bearer ${cloud.authToken}',
        },
        timeout: const Duration(seconds: 10),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          return CloudAICapabilities.fromJson(decoded);
        }
      }
    } catch (_) {}
    return const CloudAICapabilities();
  }

  /// Testa a conexão com o provedor selecionado e retorna `(ok, message)`.
  Future<({bool ok, String message})> testProviderConnection({
    required AIProviderType provider,
    required String apiKey,
    bool useCloudManaged = false,
  }) async {
    if (provider == AIProviderType.bridge) {
      return (
        ok: true,
        message:
            'Modo Sem Chave ativo! Você pode copiar o contexto com 1 clique e colar a resposta do seu ChatGPT, Claude ou Gemini Web.'
      );
    }

    if (provider == AIProviderType.appleIntelligence) {
      final supported = await isAppleIntelligenceSupported();
      return (
        ok: supported,
        message: supported
            ? 'Apple Intelligence & Motor Local ativos neste dispositivo Apple (100% offline e sem chave).'
            : 'Disponível apenas no macOS e iOS.'
      );
    }

    final cleanKey = apiKey.trim();
    if (!useCloudManaged && cleanKey.isEmpty) {
      return (
        ok: false,
        message: 'Informe sua chave de API para ${provider.label}.'
      );
    }

    _lastProviderError = null;
    final stopwatch = Stopwatch()..start();
    try {
      final testRes = await _callProviderRaw(
        provider: provider,
        apiKey: cleanKey,
        useCloudManaged: useCloudManaged,
        systemPrompt: 'Responda apenas com um JSON: {"reply": "OK", "actions": []}',
        userPrompt: 'Ping de verificação de conexão OpenMoney.',
      );
      stopwatch.stop();
      if (testRes != null && testRes.trim().isNotEmpty) {
        return (
          ok: true,
          message:
              'Conexão com ${provider.label} validada com sucesso (${stopwatch.elapsedMilliseconds} ms)!'
        );
      }
      final specific = _lastProviderError;
      return (
        ok: false,
        message: specific != null && specific.isNotEmpty
            ? 'Erro retornado pela API: $specific'
            : 'Não foi possível autenticar em ${provider.label}. Verifique se a chave está correta e ativa.'
      );
    } catch (e) {
      return (
        ok: false,
        message: 'Falha ao conectar em ${provider.label}: $e'
      );
    }
  }

  /// Constrói a System Prompt contábil estrita com o esquema de ações e contexto.
  static String buildSystemPrompt(Map<String, dynamic> contextSnapshot) {
    final contextJson = jsonEncode(contextSnapshot);
    return '''
Você é a Assistente Financeira Oficial do OpenMoney (especialista em contabilidade pessoal e empresarial, cartões de crédito por competência de vencimento, fluxo de caixa, previsões e conciliação).

DADOS REAIS DO USUÁRIO (SNAPSHOT COMPACTO — TODOS OS VALORES JÁ ESTÃO FORMATADOS NA MOEDA DO USUÁRIO, ex: "R\$ 14.947,90"):
$contextJson

REGRAS OBRIGATÓRIAS DE RESPOSTA:
1. Responda SEMPRE com um objeto JSON válido (sem texto fora do JSON) contendo exatamente estas chaves:
{
  "reply": "Sua explicação em Markdown claro, amigável e objetivo em português brasileiro, citando os valores monetários exatamente como estão formatados no snapshot (ex: R\$ 14.947,90), favorecidos e percentuais da base.",
  "query": null,
  "actions": []
}
2. FORMATAÇÃO MONETÁRIA E PERÍODOS:
   - Todos os valores do snapshot ("income", "expense", "net", "amount", "realBalance", etc.) JÁ ESTÃO em unidades monetárias reais formatadas (ex: "R\$ 14.947,90"). Cite-os diretamente como estão formatados.
   - NUNCA mencione, exiba ou converta valores para "centavos" no texto de "reply".
   - Use "monthlySummary" para análises do mês de referência ("referenceMonth") e "last7DaysSummary" quando o usuário perguntar sobre "esta semana" ou "últimos 7 dias".
3. Se precisar consultar transações específicas que não estão detalhadas no resumo, preencha "query": {"startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD", "accountId": "...", "category": "...", "tag": "...", "searchText": "...", "limit": 35}. Caso contrário, deixe "query": null.
4. Quando o usuário pedir para LANÇAR uma despesa/receita, TRANSFERIR, CRIAR RECORRÊNCIA, CRIAR PREVISÃO, DEFINIR LIMITE (budget) ou ORGANIZAR/RECATEGORIZAR, inclua objetos dentro de "actions" para confirmação em 1 clique:
   - Lançamento:
     {"type": "create_transaction", "summary": "Lançar R\$ 45,90 em Uber (Nubank)", "confidence": 0.95, "payload": {"date": "YYYY-MM-DD", "accountId": "ID_OU_NOME_DA_CONTA", "payee": "Nome Limpo", "category": "Categoria › Subcategoria", "amountCents": -4590, "memo": "", "installments": 1, "tags": ["TagOpcional"]}}
   - Transferência entre contas:
     {"type": "create_transfer", "summary": "Transferir R\$ 500,00 de Conta Corrente para Poupança", "payload": {"date": "YYYY-MM-DD", "fromAccountId": "ID_ORIGEM", "toAccountId": "ID_DESTINO", "amountCents": 50000, "memo": ""}}
   - Recorrência / Assinatura:
     {"type": "create_recurrence", "summary": "Criar recorrência mensal Netflix (R\$ 55,90)", "payload": {"startDate": "YYYY-MM-DD", "accountId": "ID_CONTA", "payee": "Netflix", "category": "Lazer › Streaming", "amountCents": -5590, "freq": "monthly", "memo": ""}}
   - Organização em lote (recategorizar / adicionar tags):
     {"type": "batch_edit_transactions", "summary": "Classificar lançamentos selecionados", "payload": {"transactionIds": ["id1", "id2"], "newCategory": "Categoria", "tags": ["Tag"]}}
   - Envelope de Previsão Orçamentária:
     {"type": "create_prediction", "summary": "Criar Previsão de Alimentação (R\$ 1.500,00)", "payload": {"date": "YYYY-MM-28", "accountId": "ID_CONTA", "payee": "Previsão Alimentação", "category": "Alimentação", "amountCents": -150000}}
   - Limite de Gastos Mensal:
     {"type": "set_budget", "summary": "Definir limite mensal para Alimentação", "payload": {"categoryPath": "Alimentação", "limitCents": 150000}}
5. Use SEMPRE os IDs de contas ("id") e nomes de categorias existentes em "accounts" e "availableCategories" do snapshot quando disponíveis.
6. REGRA DE AUDITORIA E DUPLICIDADES: NUNCA aponte como duplicidade lançamentos já conciliados ("reconciled": true), nem compras parceladas ("isInstallment": true, sufixo "(X/Y)") ou antecipações de parcelas. Para organização da base e busca de duplicidades ou lançamentos sem categoria, confie exclusivamente na lista determinística "organizationOpportunities" fornecida no snapshot.
''';
  }

  /// Processa uma mensagem do usuário (com ou sem anexo), roteando para o provedor ativo
  /// ou executando o motor determinístico local quando offline / sem chave.
  Future<AIAssistantResponse> processUserMessage({
    required MoneyStore store,
    required String userMessage,
    String? focusAccountId,
    String? focusCategory,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentMimeType,
  }) async {
    final provider = AIProviderType.fromId(store.aiProvider);
    final mode = AIConsumptionMode.fromId(store.aiConsumptionMode);
    final apiKey = _apiKeyForProvider(store, provider);
    final useManaged = mode == AIConsumptionMode.cloudManaged &&
        CloudSyncService.instance.isAuthenticated;

    // Se houver documento anexado, processa pelo leitor multimodal/híbrido
    if (attachmentBytes != null &&
        attachmentBytes.isNotEmpty &&
        attachmentName != null) {
      return analyzeDocumentAttachment(
        store: store,
        bytes: attachmentBytes,
        fileName: attachmentName,
        mimeType: attachmentMimeType ?? _guessMimeType(attachmentName),
        userPrompt: userMessage,
        focusAccountId: focusAccountId,
      );
    }

    // 1. Verifica se o comando é um lançamento direto ou auditoria determinística de organização
    final localFastResponse = _tryLocalNaturalLanguageActionOrInsight(
      store: store,
      userMessage: userMessage,
      focusAccountId: focusAccountId,
    );

    final normMsg = OfxReconciliationService.normalizeText(userMessage);
    final isOrganizationAudit = normMsg.contains('organizar') ||
        normMsg.contains('sem categoria') ||
        normMsg.contains('duplicad');
    if (isOrganizationAudit && localFastResponse != null) {
      return localFastResponse;
    }

    final canCallRemoteLLM = (provider != AIProviderType.bridge &&
            mode != AIConsumptionMode.promptBridge) &&
        (useManaged ||
            apiKey.isNotEmpty ||
            provider == AIProviderType.appleIntelligence);

    if (!canCallRemoteLLM) {
      if (localFastResponse != null) {
        return localFastResponse;
      }
      final fallbackReport =
          FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
        store,
        topic: 'overview',
      );
      return AIAssistantResponse(
        reply:
            '$fallbackReport\n\n---\n💡 *Dica:* Para conversar livremente com IA generativa, configure sua chave gratuita do **Google Gemini**, **Claude** ou **ChatGPT** nos Ajustes, ou use o botão **"Copiar Contexto (Modo Sem Chave)"** abaixo.',
        providerUsed: 'Motor Local OpenMoney (Offline)',
        isOffline: true,
      );
    }

    // 2. Monta snapshot compacto e chama o provedor de IA configurado
    final snapshot = FinancialInsightsEngine.buildCompactContextSnapshot(
      store,
      focusMonth: store.month,
      focusAccountId: focusAccountId,
      focusCategory: focusCategory,
    );
    final systemPrompt = buildSystemPrompt(snapshot);

    final rawReply = await _callProviderRaw(
      provider: provider,
      apiKey: apiKey,
      useCloudManaged: useManaged,
      preferredModel: store.aiPreferredModel,
      systemPrompt: systemPrompt,
      userPrompt: userMessage,
    );

    if (rawReply == null || rawReply.trim().isEmpty) {
      if (localFastResponse != null) return localFastResponse;
      final errorSnippet = _lastProviderError != null && _lastProviderError!.isNotEmpty
          ? '\n\n> ⚠️ **Aviso da API / Nuvem:** `$_lastProviderError`\n'
          : '';
      return AIAssistantResponse(
        reply:
            'Não foi possível obter resposta do provedor **${provider.label}** no momento.$errorSnippet\n\n'
            'Confira abaixo o diagnóstico calculado localmente:\n\n'
            '${FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(store, topic: 'overview')}',
        providerUsed: 'Fallback Local OpenMoney',
        isOffline: true,
      );
    }

    var parsed = parseStructuredAIResponse(
      rawReply,
      providerLabel: useManaged ? '${provider.label} (Cloud)' : provider.label,
    );

    // 3. Se a IA solicitou uma consulta local filtrada (tool call), executa e faz o 2º turno
    if (parsed.followUpQuery != null) {
      final queryRows = FinancialInsightsEngine.executeLocalQuery(
        store,
        parsed.followUpQuery!,
      );
      final secondPrompt = '''
Pergunta original do usuário: $userMessage

Resultado da consulta solicitada (${queryRows.length} lançamentos encontrados):
${jsonEncode(queryRows)}

Agora responda de forma completa ao usuário em JSON ("reply" e "actions", com "query": null).
''';
      final secondRaw = await _callProviderRaw(
        provider: provider,
        apiKey: apiKey,
        useCloudManaged: useManaged,
        preferredModel: store.aiPreferredModel,
        systemPrompt: systemPrompt,
        userPrompt: secondPrompt,
      );
      if (secondRaw != null && secondRaw.trim().isNotEmpty) {
        parsed = parseStructuredAIResponse(
          secondRaw,
          providerLabel:
              useManaged ? '${provider.label} (Cloud)' : provider.label,
        );
      }
    }

    // Se o parser local detectou um cartão de lançamento claro e o modelo remoto não retornou actions, mescla a sugestão
    if (parsed.actions.isEmpty &&
        localFastResponse != null &&
        localFastResponse.actions.isNotEmpty) {
      return AIAssistantResponse(
        reply: parsed.reply,
        actions: localFastResponse.actions,
        providerUsed: parsed.providerUsed,
      );
    }

    return parsed;
  }

  /// Analisa um documento anexado (PDF, Imagem de comprovante/fatura ou CSV)
  /// extraindo 1 ou N lançamentos e reconciliando com `store.db.txs`.
  Future<AIAssistantResponse> analyzeDocumentAttachment({
    required MoneyStore store,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String userPrompt = '',
    String? focusAccountId,
  }) async {
    final provider = AIProviderType.fromId(store.aiProvider);
    final mode = AIConsumptionMode.fromId(store.aiConsumptionMode);
    final apiKey = _apiKeyForProvider(store, provider);
    final useManaged = mode == AIConsumptionMode.cloudManaged &&
        CloudSyncService.instance.isAuthenticated;

    // Extrai texto se for CSV/TXT ou via OCR nativo no Desktop
    String extractedText = '';
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.csv') || lowerName.endsWith('.txt')) {
      try {
        extractedText = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
    } else if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      try {
        final tmpDir = Directory.systemTemp;
        final tmpFile =
            File('${tmpDir.path}/om_ai_doc_${DateTime.now().millisecondsSinceEpoch}_$fileName');
        await tmpFile.writeAsBytes(bytes, flush: true);
        extractedText = await LocalOcrService.extractText(tmpFile.path);
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      } catch (_) {}
    }

    final docPrompt = '''
Você é um especialista contábil do OpenMoney. Analise o documento anexado ($fileName) ${userPrompt.trim().isNotEmpty ? 'com a instrução: "$userPrompt"' : ''} e extraia TODOS os lançamentos financeiros encontrados (seja um comprovante único ou uma fatura/extrato com vários itens).

REGRAS CRÍTICAS DE EXTRAÇÃO:
1. NUNCA use nomes de maquininhas de cartão (Cielo, Stone, Getnet, Rede, Safrapay, Laranjinha, PagSeguro) nem frases fiscais (NFC-e, CNPJ, Via Cliente) como nome do estabelecimento ("payee").
2. Ignore valores de tributos (Lei 12.741), troco ou "Pagamento recebido" de fatura anterior.
3. "amount_cents" deve ser inteiro positivo em centavos (ex: R\$ 56,97 = 5697) e "is_expense": true para gastos/compras ou false para depósitos/recebimentos.
4. Se identificar parcela (ex: "03/10" ou "Parc 2/6"), preencha "pn": 3 e "pt": 10.
5. Retorne EXCLUSIVAMENTE um JSON no formato:
{
  "summary": "Explicação resumida do documento lido (total, banco/cartão identificado e quantidade de itens)",
  "detected_bank": "Nome do banco ou cartão se identificado",
  "items": [
    {
      "date": "YYYY-MM-DD",
      "payee": "Nome do Estabelecimento",
      "amount_cents": 5697,
      "is_expense": true,
      "category": "Categoria sugerida",
      "pn": null,
      "pt": null,
      "memo": ""
    }
  ]
}
${extractedText.trim().isNotEmpty ? '\nTEXTO EXTRAÍDO DO DOCUMENTO:\n$extractedText' : ''}
''';

    final base64Attachment =
        (lowerName.endsWith('.csv') || lowerName.endsWith('.txt'))
            ? null
            : base64Encode(bytes);

    String? rawJson;
    if (useManaged ||
        apiKey.isNotEmpty ||
        provider == AIProviderType.appleIntelligence) {
      rawJson = await _callProviderRaw(
        provider: provider,
        apiKey: apiKey,
        useCloudManaged: useManaged,
        preferredModel: store.aiPreferredModel,
        systemPrompt:
            'Extraia os lançamentos financeiros do documento e responda exclusivamente em JSON válido.',
        userPrompt: docPrompt,
        attachmentBase64: base64Attachment,
        attachmentMimeType: mimeType,
      );
    }

    final extractedRawItems = <Map<String, dynamic>>[];
    String docSummary = 'Leitura do documento **$fileName** concluída.';
    String detectedBank = '';

    if (rawJson != null && rawJson.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonMap(rawJson);
      if (decoded != null) {
        if (decoded['summary'] is String &&
            (decoded['summary'] as String).trim().isNotEmpty) {
          docSummary = decoded['summary'].toString().trim();
        }
        detectedBank = (decoded['detected_bank'] ?? '').toString().trim();
        if (decoded['items'] is List) {
          for (final it in (decoded['items'] as List)) {
            if (it is Map) {
              final map = Map<String, dynamic>.from(it);
              if (detectedBank.isNotEmpty &&
                  (map['detected_bank'] == null ||
                      map['detected_bank'].toString().isEmpty)) {
                map['detected_bank'] = detectedBank;
              }
              extractedRawItems.add(map);
            }
          }
        } else if (decoded['payee'] != null &&
            (decoded['amount_cents'] != null ||
                decoded['amountCents'] != null)) {
          extractedRawItems.add(decoded);
        }
      }
    }

    // Fallback heurístico sobre o texto extraído se a IA remota não estiver configurada
    if (extractedRawItems.isEmpty && extractedText.trim().isNotEmpty) {
      extractedRawItems.addAll(_parseExtractedTextFallback(extractedText));
    }

    if (extractedRawItems.isEmpty) {
      return AIAssistantResponse(
        reply:
            'Não foi possível identificar lançamentos estruturados em **$fileName**. Verifique se sua chave de IA multimodal (ex: Google Gemini Flash ou Claude/ChatGPT) está configurada em Ajustes.',
        providerUsed: provider.label,
        isOffline: apiKey.isEmpty && !useManaged,
      );
    }

    final reconciled = FinancialInsightsEngine.reconcileExtractedDocumentItems(
      store,
      rawItems: extractedRawItems,
      defaultAccountId: focusAccountId,
    );

    if (reconciled.length == 1 && !reconciled.first.hasExistingMatch) {
      final it = reconciled.first;
      final acc = store.accById(it.accountId);
      final cur = acc?.effectiveCurrency ?? store.baseCurrency;
      final proposal = AIActionProposal(
        type: 'create_transaction',
        summary:
            'Lançar ${formatCurrency(it.signedAmountCents.abs(), cur)} em ${it.payee} (${acc?.name ?? it.accountId})',
        confidence: 0.96,
        payload: {
          'date': it.dateIso,
          'accountId': it.accountId,
          'payee': it.payee,
          'category': it.category,
          'amountCents': it.signedAmountCents,
          'memo': it.memo,
          'installments': (it.installmentTotal != null &&
                  it.installmentTotal! > 1 &&
                  (it.installmentCurrent ?? 1) == 1)
              ? it.installmentTotal
              : 1,
          if (it.tags.isNotEmpty) 'tags': it.tags,
        },
      );
      return AIAssistantResponse(
        reply:
            '📄 **$docSummary**\n\nIdentifiquei o comprovante de **${it.payee}** no valor de **${formatCurrency(it.signedAmountCents.abs(), cur)}** em **${fmtDate(it.dateIso)}** (${it.category}). Confirme abaixo em 1 clique:',
        actions: [proposal],
        providerUsed: provider.label,
      );
    }

    // Múltiplos itens (fatura ou extrato)
    final newCount = reconciled.where((i) => !i.hasExistingMatch).length;
    final matchedCount = reconciled.where((i) => i.hasExistingMatch).length;
    final proposal = AIActionProposal(
      type: 'reconcile_document_items',
      summary:
          'Importar $newCount novo(s) e conciliar $matchedCount existente(s) de $fileName',
      confidence: 0.94,
      payload: {
        'fileName': fileName,
        'items': reconciled
            .map((i) => {
                  'dateIso': i.dateIso,
                  'payee': i.payee,
                  'amountCents': i.signedAmountCents,
                  'category': i.category,
                  'accountId': i.accountId,
                  'memo': i.memo,
                  'pn': i.installmentCurrent,
                  'pt': i.installmentTotal,
                  'matchedExistingTxId': i.matchedExistingTxId,
                  'isAlreadyReconciled': i.isAlreadyReconciled,
                  'selected': !i.isAlreadyReconciled,
                })
            .toList(),
      },
    );

    return AIAssistantResponse(
      reply:
          '📄 **$docSummary**\n\nExtraí **${reconciled.length}** lançamento(s) do documento:\n'
          '- **$newCount** lançamento(s) inédito(s) prontos para inclusão;\n'
          '- **$matchedCount** lançamento(s) já existente(s) no seu extrato (marcados para conciliação sem duplicar).',
      actions: [proposal],
      providerUsed: provider.label,
    );
  }

  /// Gera o pacote de Prompt Seguro + Contexto para o Modo "Sem Chave" (Nível 3 - Prompt Bridge).
  static String buildExternalPromptPackage(
    MoneyStore store, {
    required String userQuestion,
    String? focusAccountId,
    String? focusCategory,
  }) {
    final snapshot = FinancialInsightsEngine.buildCompactContextSnapshot(
      store,
      focusMonth: store.month,
      focusAccountId: focusAccountId,
      focusCategory: focusCategory,
    );
    final prettyContext =
        const JsonEncoder.withIndent('  ').convert(snapshot);
    final question = userQuestion.trim().isEmpty
        ? 'Analise minhas finanças deste mês, explique os principais aumentos por categoria, avalie minhas faturas de cartão e identifique recorrências ou oportunidades de organização.'
        : userQuestion.trim();

    return '''
Você é minha Assistente Financeira do OpenMoney. Analise meu resumo financeiro real abaixo e responda ao meu pedido:

MEU PEDIDO:
"$question"

DADOS FINANCEIROS COMPACTOS (VALORES JÁ FORMATADOS NA MOEDA DO USUÁRIO):
```json
$prettyContext
```

INSTRUÇÕES:
1. Responda em português de forma clara, analítica e direta, citando os estabelecimentos, categorias e valores monetários formatados (nunca mencione valores em centavos no texto).
2. Se sugerir lançamentos, recategorizações, limites de gastos ou criação de recorrências, inclua ao final um bloco ```json com a estrutura:
```json
{
  "reply": "Resumo da sua análise",
  "actions": [
    {
      "type": "create_transaction",
      "summary": "Descrição curta da ação",
      "payload": {
        "date": "YYYY-MM-DD",
        "accountId": "id_da_conta",
        "payee": "Estabelecimento",
        "category": "Categoria",
        "amountCents": -5000,
        "memo": "",
        "tags": []
      }
    }
  ]
}
```
''';
  }

  static String _sanitizeReplyText(String text) {
    // Remove anotações parentéticas redundantes em centavos caso algum modelo on-device as inclua
    return text
        .replaceAll(
          RegExp(
            r'\s*\(\s*[-+]?(?:R\$\s*)?\d[\d.,\s]*\s*centavos?\s*\)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  /// Interpreta o texto ou JSON colado pelo usuário no Modo "Sem Chave" (Prompt Bridge).
  static AIAssistantResponse parseStructuredAIResponse(
    String rawText, {
    String providerLabel = 'Assistente IA',
  }) {
    final trimmed = rawText.trim();
    final map = _tryDecodeJsonMap(trimmed);
    if (map != null) {
      final reply = _sanitizeReplyText(
        (map['reply'] ?? map['message'] ?? map['summary'] ?? '')
            .toString()
            .trim(),
      );
      final actions = <AIActionProposal>[];
      if (map['actions'] is List) {
        for (final a in (map['actions'] as List)) {
          if (a is Map) {
            actions.add(
              AIActionProposal.fromJson(Map<String, dynamic>.from(a)),
            );
          }
        }
      }
      AIQueryFilter? query;
      if (map['query'] is Map) {
        query = AIQueryFilter.fromJson(
          Map<String, dynamic>.from(map['query'] as Map),
        );
      }
      return AIAssistantResponse(
        reply: reply.isEmpty ? 'Ação pronta para confirmação:' : reply,
        actions: actions,
        followUpQuery: query,
        providerUsed: providerLabel,
      );
    }

    return AIAssistantResponse(
      reply: _sanitizeReplyText(trimmed),
      actions: const [],
      providerUsed: providerLabel,
    );
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
    var clean = raw.trim();
    // Tenta extrair bloco ```json ... ``` se existir
    final fencedMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
            .firstMatch(clean);
    if (fencedMatch != null && fencedMatch.group(1) != null) {
      clean = fencedMatch.group(1)!.trim();
    }

    try {
      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Tenta localizar o primeiro '{' e o último '}'
      final start = clean.indexOf('{');
      final end = clean.lastIndexOf('}');
      if (start != -1 && end > start) {
        try {
          final sub = clean.substring(start, end + 1);
          final decoded = jsonDecode(sub);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }
    return null;
  }

  static String _apiKeyForProvider(MoneyStore store, AIProviderType provider) {
    switch (provider) {
      case AIProviderType.gemini:
        return store.geminiApiKey.trim();
      case AIProviderType.claude:
        return store.claudeApiKey.trim();
      case AIProviderType.openai:
        return store.openaiApiKey.trim();
      case AIProviderType.appleIntelligence:
      case AIProviderType.bridge:
        return '';
    }
  }

  Future<String?> _callProviderRaw({
    required AIProviderType provider,
    required String apiKey,
    required bool useCloudManaged,
    String preferredModel = '',
    required String systemPrompt,
    required String userPrompt,
    String? attachmentBase64,
    String? attachmentMimeType,
  }) async {
    // 1. Apple Intelligence (On-Device FoundationModels via MethodChannel / swift)
    if (provider == AIProviderType.appleIntelligence) {
      return _callAppleIntelligenceLocal(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
    }

    // 2. Se estiver na Web (para Claude/OpenAI que exigem proxy anti-CORS) ou em modo Cloud Managed
    final cloud = CloudSyncService.instance;
    final needsCloudProxy = useCloudManaged ||
        (kIsWeb &&
            (provider == AIProviderType.claude ||
                provider == AIProviderType.openai) &&
            cloud.isAuthenticated);

    if (needsCloudProxy && cloud.isAuthenticated) {
      final cloudRes = await _callCloudflareAIEndpoint(
        provider: provider,
        apiKey: apiKey,
        useManaged: useCloudManaged,
        model: preferredModel,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        attachmentBase64: attachmentBase64,
        attachmentMimeType: attachmentMimeType,
      );
      if (cloudRes != null && cloudRes.trim().isNotEmpty) {
        return cloudRes;
      }
      if (useCloudManaged && apiKey.isEmpty) {
        return null;
      }
    }

    // 3. Chamada direta BYOK ao provedor
    switch (provider) {
      case AIProviderType.gemini:
        return _callGeminiDirect(
          apiKey: apiKey,
          preferredModel: preferredModel,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          attachmentBase64: attachmentBase64,
          attachmentMimeType: attachmentMimeType,
        );
      case AIProviderType.claude:
        return _callClaudeDirect(
          apiKey: apiKey,
          preferredModel: preferredModel,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          attachmentBase64: attachmentBase64,
          attachmentMimeType: attachmentMimeType,
        );
      case AIProviderType.openai:
        return _callOpenAIDirect(
          apiKey: apiKey,
          preferredModel: preferredModel,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          attachmentBase64: attachmentBase64,
          attachmentMimeType: attachmentMimeType,
        );
      case AIProviderType.appleIntelligence:
      case AIProviderType.bridge:
        return null;
    }
  }

  Future<String?> _callCloudflareAIEndpoint({
    required AIProviderType provider,
    required String apiKey,
    required bool useManaged,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    String? attachmentBase64,
    String? attachmentMimeType,
  }) async {
    final cloud = CloudSyncService.instance;
    final base = cloud.apiBaseUrl;
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer ${cloud.authToken}',
        'X-OpenMoney-AI-Provider': provider.id,
        if (!useManaged && apiKey.isNotEmpty) 'X-OpenMoney-AI-Key': apiKey,
      };
      final payload = <String, dynamic>{
        'provider': provider.id,
        'useManaged': useManaged,
        if (model.trim().isNotEmpty) 'model': model.trim(),
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
        if (attachmentBase64 != null && attachmentBase64.isNotEmpty)
          'attachment': {
            'data': attachmentBase64,
            'mimeType': attachmentMimeType ?? 'image/jpeg',
          },
      };
      final res = await platformHttpRequest(
        method: 'POST',
        url: '$base/api/ai/chat',
        headers: headers,
        body: jsonEncode(payload),
        timeout: const Duration(seconds: 40),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['text'] is String) {
          return decoded['text'] as String;
        }
      } else {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded['error'] is String) {
            _lastProviderError = decoded['error'] as String;
          } else {
            _lastProviderError = 'HTTP ${res.statusCode}: ${res.body}';
          }
        } catch (_) {
          _lastProviderError = 'HTTP ${res.statusCode}';
        }
      }
    } catch (e) {
      _lastProviderError = 'Falha na conexão: $e';
    }
    return null;
  }

  Future<String?> _callGeminiDirect({
    required String apiKey,
    String preferredModel = '',
    required String systemPrompt,
    required String userPrompt,
    String? attachmentBase64,
    String? attachmentMimeType,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return null;

    final models = <String>[
      if (preferredModel.trim().isNotEmpty) preferredModel.trim(),
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.5-flash-latest',
      'gemini-flash-latest',
    ];

    for (final model in models) {
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$cleanKey';

      final parts = <Map<String, dynamic>>[
        {'text': '$systemPrompt\n\nPEDIDO DO USUÁRIO:\n$userPrompt'},
      ];
      if (attachmentBase64 != null && attachmentBase64.isNotEmpty) {
        parts.add({
          'inline_data': {
            'mime_type': attachmentMimeType ?? 'image/jpeg',
            'data': attachmentBase64,
          },
        });
      }

      final payload = {
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': {
          'temperature': 0.15,
          'response_mime_type': 'application/json',
        },
      };

      try {
        final res = await platformHttpRequest(
          method: 'POST',
          url: url,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(payload),
          timeout: const Duration(seconds: 35),
        );
        if (res.statusCode != 200) {
          try {
            final decoded = jsonDecode(res.body);
            if (decoded is Map &&
                decoded['error'] is Map &&
                decoded['error']['message'] is String) {
              _lastProviderError =
                  '${decoded['error']['message']} (HTTP ${res.statusCode})';
            } else {
              _lastProviderError = 'HTTP ${res.statusCode}: ${res.body}';
            }
          } catch (_) {
            _lastProviderError = 'HTTP ${res.statusCode}';
          }
          continue;
        }
        final decoded = jsonDecode(res.body);
        final candidates = decoded['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) continue;
        final text =
            candidates.first['content']?['parts']?[0]?['text'] as String?;
        if (text != null && text.trim().isNotEmpty) {
          return text.trim();
        }
      } catch (e) {
        _lastProviderError = 'Falha de requisição: $e';
        continue;
      }
    }
    return null;
  }

  Future<String?> _callClaudeDirect({
    required String apiKey,
    String preferredModel = '',
    required String systemPrompt,
    required String userPrompt,
    String? attachmentBase64,
    String? attachmentMimeType,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return null;

    final models = <String>[
      if (preferredModel.trim().isNotEmpty) preferredModel.trim(),
      'claude-3-7-sonnet-latest',
      'claude-3-5-sonnet-latest',
      'claude-3-5-haiku-latest',
    ];

    for (final model in models) {
      final contentBlocks = <Map<String, dynamic>>[];
      if (attachmentBase64 != null && attachmentBase64.isNotEmpty) {
        final mime = attachmentMimeType ?? 'image/jpeg';
        if (mime == 'application/pdf') {
          contentBlocks.add({
            'type': 'document',
            'source': {
              'type': 'base64',
              'media_type': 'application/pdf',
              'data': attachmentBase64,
            },
          });
        } else {
          contentBlocks.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': mime,
              'data': attachmentBase64,
            },
          });
        }
      }
      contentBlocks.add({
        'type': 'text',
        'text': userPrompt,
      });

      final payload = {
        'model': model,
        'max_tokens': 2048,
        'temperature': 0.15,
        'system': systemPrompt,
        'messages': [
          {
            'role': 'user',
            'content': contentBlocks,
          },
        ],
      };

      try {
        final res = await platformHttpRequest(
          method: 'POST',
          url: 'https://api.anthropic.com/v1/messages',
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'x-api-key': cleanKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode(payload),
          timeout: const Duration(seconds: 35),
        );
        if (res.statusCode != 200) {
          try {
            final decoded = jsonDecode(res.body);
            if (decoded is Map &&
                decoded['error'] is Map &&
                decoded['error']['message'] is String) {
              _lastProviderError =
                  '${decoded['error']['message']} (HTTP ${res.statusCode})';
            } else {
              _lastProviderError = 'HTTP ${res.statusCode}: ${res.body}';
            }
          } catch (_) {
            _lastProviderError = 'HTTP ${res.statusCode}';
          }
          continue;
        }
        final decoded = jsonDecode(res.body);
        final content = decoded['content'] as List?;
        if (content == null || content.isEmpty) continue;
        for (final block in content) {
          if (block is Map && block['type'] == 'text' && block['text'] is String) {
            return (block['text'] as String).trim();
          }
        }
      } catch (e) {
        _lastProviderError = 'Falha de requisição: $e';
        continue;
      }
    }
    return null;
  }

  Future<String?> _callOpenAIDirect({
    required String apiKey,
    String preferredModel = '',
    required String systemPrompt,
    required String userPrompt,
    String? attachmentBase64,
    String? attachmentMimeType,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return null;

    final models = <String>[
      if (preferredModel.trim().isNotEmpty) preferredModel.trim(),
      'gpt-4o-mini',
      'gpt-4o',
    ];

    for (final model in models) {
      final userContent = <Map<String, dynamic>>[
        {'type': 'text', 'text': userPrompt},
      ];
      if (attachmentBase64 != null &&
          attachmentBase64.isNotEmpty &&
          (attachmentMimeType ?? '').startsWith('image/')) {
        userContent.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:$attachmentMimeType;base64,$attachmentBase64',
          },
        });
      }

      final payload = {
        'model': model,
        'temperature': 0.15,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
      };

      try {
        final res = await platformHttpRequest(
          method: 'POST',
          url: 'https://api.openai.com/v1/chat/completions',
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $cleanKey',
          },
          body: jsonEncode(payload),
          timeout: const Duration(seconds: 35),
        );
        if (res.statusCode != 200) {
          try {
            final decoded = jsonDecode(res.body);
            if (decoded is Map &&
                decoded['error'] is Map &&
                decoded['error']['message'] is String) {
              _lastProviderError =
                  '${decoded['error']['message']} (HTTP ${res.statusCode})';
            } else {
              _lastProviderError = 'HTTP ${res.statusCode}: ${res.body}';
            }
          } catch (_) {
            _lastProviderError = 'HTTP ${res.statusCode}';
          }
          continue;
        }
        final decoded = jsonDecode(res.body);
        final choices = decoded['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final text = choices.first['message']?['content'] as String?;
        if (text != null && text.trim().isNotEmpty) {
          return text.trim();
        }
      } catch (e) {
        _lastProviderError = 'Falha de requisição: $e';
        continue;
      }
    }
    return null;
  }

  Future<String?> _callAppleIntelligenceLocal({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (kIsWeb) return null;
    try {
      final res = await _appleChannel.invokeMethod<String>('generateResponse', {
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
      });
      if (res != null && res.trim().isNotEmpty) {
        return res.trim();
      }
    } catch (_) {}
    return null;
  }

  /// Interpretador determinístico local de linguagem natural para comandos de lançamento,
  /// transferências, recorrências e perguntas analíticas (funciona em 0 ms e 100% offline).
  AIAssistantResponse? _tryLocalNaturalLanguageActionOrInsight({
    required MoneyStore store,
    required String userMessage,
    String? focusAccountId,
  }) {
    final text = userMessage.trim();
    if (text.isEmpty) return null;
    final norm = OfxReconciliationService.normalizeText(text);

    // A) Perguntas analíticas diretas (fatura, aumento de categorias, recorrências, organizar)
    if (norm.contains('fatura') &&
        !norm.startsWith('lancar') &&
        !norm.startsWith('gastei') &&
        !norm.startsWith('comprei')) {
      final md = FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
        store,
        topic: 'invoices',
        cardId: focusAccountId,
      );
      return AIAssistantResponse(
        reply: md,
        providerUsed: 'Motor Analítico OpenMoney',
        isOffline: true,
      );
    }

    if ((norm.contains('aumento') ||
            norm.contains('subiu') ||
            norm.contains('subiram') ||
            norm.contains('variacao') ||
            norm.contains('variacoes') ||
            norm.contains('explicar categoria') ||
            norm.contains('gastos por categoria')) &&
        !norm.startsWith('lancar')) {
      final md = FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
        store,
        topic: 'spikes',
      );
      return AIAssistantResponse(
        reply: md,
        providerUsed: 'Motor Analítico OpenMoney',
        isOffline: true,
      );
    }

    if (norm.contains('recorrencia') ||
        norm.contains('assinatura') ||
        norm.contains('mensalidade')) {
      final recs = FinancialInsightsEngine.detectImplicitRecurrences(store);
      final md = FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
        store,
        topic: 'recurrences',
      );
      final proposals = recs.take(4).map((r) {
        final fmtAmt =
            formatCurrency(r.latestAmountCents.abs(), r.currency);
        return AIActionProposal(
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
        );
      }).toList();
      return AIAssistantResponse(
        reply: md,
        actions: proposals,
        providerUsed: 'Detector de Recorrências OpenMoney',
        isOffline: true,
      );
    }

    if (norm.contains('organizar') ||
        norm.contains('sem categoria') ||
        norm.contains('duplicad')) {
      final opps =
          FinancialInsightsEngine.findOrganizationOpportunities(store);
      if (opps.isEmpty) {
        return const AIAssistantResponse(
          reply:
              '✅ Sua base está muito bem organizada! Não encontrei lançamentos sem categoria nem possíveis duplicidades neste mês.',
          providerUsed: 'Auditor de Base OpenMoney',
          isOffline: true,
        );
      }
      final proposals = opps
          .where((o) =>
              o.kind == 'uncategorized' &&
              o.suggestedCategory != null &&
              o.suggestedCategory!.isNotEmpty)
          .take(5)
          .map(
            (o) => AIActionProposal(
              type: 'batch_edit_transactions',
              summary: '${o.title} → ${o.suggestedCategory}',
              payload: {
                'transactionIds': o.transactionIds,
                'newCategory': o.suggestedCategory,
              },
            ),
          )
          .toList();
      final buf = StringBuffer('### 🗂️ Oportunidades de Organização Encontradas\n');
      for (final o in opps.take(8)) {
        buf.writeln('- **${o.title}**: ${o.subtitle}');
      }
      return AIAssistantResponse(
        reply: buf.toString().trim(),
        actions: proposals,
        providerUsed: 'Organizador OpenMoney',
        isOffline: true,
      );
    }

    // B) Lançamento por linguagem natural (ex: "Gastei 45,90 no Uber ontem no Nubank #Viagem")
    final parsedAction = parseNaturalLanguageTransaction(
      store: store,
      text: text,
      defaultAccountId: focusAccountId,
    );
    if (parsedAction != null) {
      return AIAssistantResponse(
        reply:
            'Preparei o lançamento abaixo com base no seu comando. Confira os dados e confirme em 1 clique:',
        actions: [parsedAction],
        providerUsed: 'Assistente OpenMoney',
        isOffline: true,
      );
    }

    return null;
  }

  /// Parser determinístico para comandos em português como:
  /// "Gastei 45,90 no Uber ontem no Nubank #Transporte"
  /// "Parcelei 900 em 3x na Amazon no cartão Itaú"
  /// "Recebi 4500 de Salário hoje na Conta Corrente"
  static AIActionProposal? parseNaturalLanguageTransaction({
    required MoneyStore store,
    required String text,
    String? defaultAccountId,
  }) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();

    final isEntryVerb = lower.startsWith('lancar ') ||
        lower.startsWith('lançar ') ||
        lower.startsWith('lance ') ||
        lower.startsWith('gastei ') ||
        lower.startsWith('paguei ') ||
        lower.startsWith('comprei ') ||
        lower.startsWith('parcelei ') ||
        lower.startsWith('recebi ') ||
        lower.startsWith('ganhei ') ||
        lower.startsWith('deposito ') ||
        lower.startsWith('depósito ');

    if (!isEntryVerb) return null;

    final isIncome = lower.startsWith('recebi ') ||
        lower.startsWith('ganhei ') ||
        lower.startsWith('deposito ') ||
        lower.startsWith('depósito ') ||
        lower.contains(' receita ');

    // Extrai tags (#tag)
    final tags = <String>[];
    var working = trimmed.replaceAllMapped(RegExp(r'#([\wÀ-ÿ-]+)'), (m) {
      final tag = m.group(1)?.trim() ?? '';
      if (tag.isNotEmpty) tags.add(tag);
      return '';
    });

    // Extrai parcelas (ex: "em 3x", "3 parcelas")
    int installments = 1;
    working = working.replaceAllMapped(
      RegExp(r'\b(?:em\s+)?(\d{1,3})\s*(?:x|parcelas?)\b', caseSensitive: false),
      (m) {
        installments = (int.tryParse(m.group(1) ?? '1') ?? 1).clamp(1, 120);
        return '';
      },
    );

    // Extrai data ("ontem", "anteontem", "hoje", ou DD/MM/AAAA, DD/MM)
    String dateIso = todayISO();
    final now = DateTime.now();
    if (RegExp(r'\banteontem\b', caseSensitive: false).hasMatch(working)) {
      final d = now.subtract(const Duration(days: 2));
      dateIso =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      working =
          working.replaceAll(RegExp(r'\banteontem\b', caseSensitive: false), '');
    } else if (RegExp(r'\bontem\b', caseSensitive: false).hasMatch(working)) {
      final d = now.subtract(const Duration(days: 1));
      dateIso =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      working =
          working.replaceAll(RegExp(r'\bontem\b', caseSensitive: false), '');
    } else if (RegExp(r'\bhoje\b', caseSensitive: false).hasMatch(working)) {
      working =
          working.replaceAll(RegExp(r'\bhoje\b', caseSensitive: false), '');
    } else {
      final dateMatch =
          RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b').firstMatch(working);
      if (dateMatch != null) {
        final day = int.tryParse(dateMatch.group(1)!) ?? now.day;
        final mon = int.tryParse(dateMatch.group(2)!) ?? now.month;
        int yr = int.tryParse(dateMatch.group(3) ?? '') ?? now.year;
        if (yr < 100) yr += 2000;
        dateIso =
            '${yr.toString().padLeft(4, '0')}-${mon.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        working = working.replaceFirst(dateMatch.group(0)!, '');
      }
    }

    // Extrai valor monetário (ex: R$ 45,90 ou 1.200,50 ou 45.90 ou 50)
    final amtMatch = RegExp(
      r'(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})|\d+(?:[.,]\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(working);
    if (amtMatch == null) return null;

    final rawAmtStr = amtMatch.group(1)!;
    final cents = (parseCents(rawAmtStr) ?? 0).abs();
    if (cents <= 0) return null;
    working = working.replaceFirst(amtMatch.group(0)!, '');

    // Remove o verbo inicial e palavras de ligação
    working = working
        .replaceFirst(
          RegExp(
            r'^(?:lancar|lançar|lance|gastei|paguei|comprei|parcelei|recebi|ganhei|deposito|depósito)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'^(?:reais|real|brl)\s+', caseSensitive: false), '')
        .trim();

    // Verifica se alguma conta cadastrada foi mencionada na frase
    String? detectedAccId = defaultAccountId;
    for (final acc in store.activeAccounts) {
      final accNorm = OfxReconciliationService.normalizeText(acc.name);
      if (accNorm.length >= 3 &&
          OfxReconciliationService.normalizeText(working).contains(accNorm)) {
        detectedAccId = acc.id;
        working = working.replaceAll(
          RegExp(
            '(?:\\b(?:no|na|pelo|pela|cartao|cartão|conta)\\s+)?${RegExp.escape(acc.name)}',
            caseSensitive: false,
          ),
          '',
        );
        break;
      }
    }

    // Limpa preposições residuais do início/fim para isolar o favorecido
    var payee = working
        .replaceFirst(
          RegExp(r'^(?:no|na|em|de|do|da|com|para)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s+(?:no|na|em|pelo|pela)\s*$', caseSensitive: false),
          '',
        )
        .trim();
    if (payee.isEmpty) {
      payee = isIncome ? 'Receita' : 'Despesa';
    } else {
      payee = payee[0].toUpperCase() + payee.substring(1);
    }

    final hist = store.lastCategoryAndType(payee, isExpense: !isIncome);
    final resolvedAccId = detectedAccId ??
        hist?.accountId ??
        (store.selectedAccountId.isNotEmpty
            ? store.selectedAccountId
            : (store.activeAccounts.firstOrNull?.id ?? 'a1'));
    final category = hist?.category ??
        (store
                .allCategoryPaths(isIncome ? 'Receita' : 'Despesa')
                .firstOrNull ??
            'Outros');

    final signedAmt = isIncome ? cents : -cents;
    final acc = store.accById(resolvedAccId);
    final cur = acc?.effectiveCurrency ?? store.baseCurrency;

    return AIActionProposal(
      type: 'create_transaction',
      summary:
          'Lançar ${formatCurrency(cents, cur)}${installments > 1 ? " ($installments parcelas)" : ""} em $payee (${acc?.name ?? resolvedAccId})',
      confidence: 0.94,
      payload: {
        'date': dateIso,
        'accountId': resolvedAccId,
        'payee': payee,
        'category': category,
        'amountCents': signedAmt,
        'memo': '',
        'installments': installments,
        if (tags.isNotEmpty) 'tags': tags,
      },
    );
  }

  static List<Map<String, dynamic>> _parseExtractedTextFallback(String rawText) {
    final items = <Map<String, dynamic>>[];
    final lines = rawText.split(RegExp(r'\r?\n'));
    final lineRegex = RegExp(
      r'(\d{2}/\d{2}(?:/\d{2,4})?)\s+(.+?)\s+(-?\s*(?:R\$\s*)?\d{1,3}(?:\.\d{3})*,\d{2})',
    );
    final nowYear = DateTime.now().year;

    for (final line in lines) {
      final m = lineRegex.firstMatch(line.trim());
      if (m == null) continue;
      final dParts = m.group(1)!.split('/');
      final day = dParts[0].padLeft(2, '0');
      final mon = dParts[1].padLeft(2, '0');
      var yr = dParts.length >= 3 ? dParts[2] : '$nowYear';
      if (yr.length == 2) yr = '20$yr';
      final dateIso = '$yr-$mon-$day';

      var payee = m.group(2)!.trim();
      int? pn;
      int? pt;
      final instMatch = RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(payee);
      if (instMatch != null) {
        pn = int.tryParse(instMatch.group(1)!);
        pt = int.tryParse(instMatch.group(2)!);
      }

      final amtStr = m.group(3)!.replaceAll('R\$', '').replaceAll(' ', '');
      final isNegative = amtStr.startsWith('-');
      final cents = (parseCents(amtStr) ?? 0).abs();
      if (cents <= 0) continue;

      items.add({
        'date': dateIso,
        'payee': payee,
        'amount_cents': cents,
        'is_expense': !isNegative ? true : true,
        'pn': ?pn,
        'pt': ?pt,
      });
    }
    return items;
  }

  static String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'image/jpeg';
  }
}
