import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/ai_assistant_service.dart';
import 'package:openmoney/services/financial_insights_engine.dart';
import 'package:openmoney/services/shortcut_url_service.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/widgets/ai_assistant_drawer.dart';

void main() {
  group('FinancialInsightsEngine & AIAssistantService Tests', () {
    MoneyStore buildTestStore() {
      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(
            id: 'acc_corrente',
            name: 'Itaú Corrente',
            type: 'Corrente',
            opening: 500000,
          ),
          Account(
            id: 'acc_nubank',
            name: 'Nubank UV',
            type: kCardType,
            opening: 0,
            card: CardConfig(closeDay: 25, dueDay: 5, pay: 'acc_corrente'),
          ),
        ],
        cats: [
          CategoryItem(name: 'Alimentação', type: 'Despesa'),
          CategoryItem(
            name: 'Restaurante',
            parent: 'Alimentação',
            type: 'Despesa',
          ),
          CategoryItem(name: 'Lazer', type: 'Despesa'),
          CategoryItem(name: 'Streaming', parent: 'Lazer', type: 'Despesa'),
          CategoryItem(name: 'Transporte', type: 'Despesa'),
          CategoryItem(
            name: 'Transferencias (D)',
            type: 'Despesa',
            includeInReports: false,
          ),
        ],
        budgets: {
          'Alimentação › Restaurante': 80000, // R$ 800,00
        },
        txs: [
          // Histórico 3 meses anteriores em Alimentação › Restaurante (Média = R$ 400,00 / mês)
          Transaction(
            id: 'tx_aug',
            acc: 'acc_corrente',
            date: '2026-08-15',
            payee: 'Restaurante Silva',
            cat: 'Alimentação › Restaurante',
            amt: -40000,
            rec: true,
          ),
          Transaction(
            id: 'tx_sep',
            acc: 'acc_corrente',
            date: '2026-09-15',
            payee: 'Restaurante Silva',
            cat: 'Alimentação › Restaurante',
            amt: -40000,
            rec: true,
          ),
          Transaction(
            id: 'tx_oct',
            acc: 'acc_corrente',
            date: '2026-10-15',
            payee: 'Restaurante Silva',
            cat: 'Alimentação › Restaurante',
            amt: -40000,
            rec: true,
          ),
          // Mês alvo (2026-11): Spike para R$ 950,00 (+137.5%, acima do budget de R$ 800)
          Transaction(
            id: 'tx_nov_1',
            acc: 'acc_corrente',
            date: '2026-11-10',
            payee: 'Outback Steakhouse',
            cat: 'Alimentação › Restaurante',
            amt: -55000,
            rec: true,
          ),
          Transaction(
            id: 'tx_nov_2',
            acc: 'acc_corrente',
            date: '2026-11-12',
            payee: 'Restaurante Silva',
            cat: 'Alimentação › Restaurante',
            amt: -40000,
            rec: true,
          ),
          // Envelope de previsão (deve ser ignorado no cálculo de gastos reais)
          Transaction(
            id: 'tx_pred',
            acc: 'acc_corrente',
            date: '2026-11-28',
            payee: 'Previsão Alimentação',
            cat: 'Alimentação › Restaurante',
            memo: '[Previsão base: R\$ 1.000,00]',
            amt: -50000,
            rec: false,
          ),
          // Transferência (deve ser ignorada nos spikes de categoria)
          Transaction(
            id: 'tx_xfer',
            acc: 'acc_corrente',
            peer: 'acc_nubank',
            xfer: 'xf_1',
            date: '2026-11-05',
            payee: 'Transferência',
            cat: 'Transferencias (D)',
            amt: -200000,
            rec: true,
          ),
        ],
      );
      store.month = '2026-11';
      store.markIndexesDirty();
      store.rebuildIndexesIfNeeded();
      return store;
    }

    test('explainCategorySpikes calcula aumento percentual, ignora previsões/transferências e aponta Top Drivers', () {
      final store = buildTestStore();
      final spikes = FinancialInsightsEngine.explainCategorySpikes(
        store,
        targetMonth: '2026-11',
      );

      expect(spikes, isNotEmpty);
      final restSpike = spikes.firstWhere(
        (s) => s.categoryPath == 'Alimentação › Restaurante',
      );
      expect(restSpike.currentCents, 95000);
      expect(restSpike.average3MonthsCents, 40000);
      expect(restSpike.deltaVsAverageCents, 55000);
      expect(restSpike.isOverBudget, isTrue);
      expect(restSpike.topDrivers, isNotEmpty);
      expect(restSpike.topDrivers.first.payee, 'Outback Steakhouse');
      expect(restSpike.topDrivers.first.deltaCents, 55000);
    });

    test('analyzeCardInvoice separa compras à vista, parceladas e projeta comprometimento futuro', () {
      final store = buildTestStore();
      store.db.txs.addAll([
        Transaction(
          id: 'c_spot',
          acc: 'acc_nubank',
          date: '2026-10-10',
          payee: 'Uber',
          cat: 'Transporte',
          amt: -5000,
          ik: '2026-11',
          rec: true,
        ),
        Transaction(
          id: 'c_inst_1',
          acc: 'acc_nubank',
          date: '2026-10-12',
          payee: 'Amazon (1/2)',
          cat: 'Lazer',
          amt: -30000,
          ik: '2026-11',
          plan: 'plan_amz',
          pn: 1,
          pt: 2,
          rec: true,
        ),
        Transaction(
          id: 'c_inst_2',
          acc: 'acc_nubank',
          date: '2026-11-12',
          payee: 'Amazon (2/2)',
          cat: 'Lazer',
          amt: -30000,
          ik: '2026-12',
          plan: 'plan_amz',
          pn: 2,
          pt: 2,
          rec: false,
        ),
      ]);
      store.markIndexesDirty();
      store.rebuildIndexesIfNeeded();

      final analysis = FinancialInsightsEngine.analyzeCardInvoice(
        store,
        cardId: 'acc_nubank',
        invoiceKey: '2026-11',
      );

      expect(analysis, isNotNull);
      expect(analysis!.totalInvoiceCents, 35000);
      expect(analysis.spotPurchasesCents, 5000);
      expect(analysis.installmentPurchasesCents, 30000);
      expect(analysis.next3InvoicesCommittedCents['2026-12'], 30000);
    });

    test('detectImplicitRecurrences identifica assinatura mensal, detecta reajuste e ignora compras parceladas', () {
      final store = buildTestStore();
      final now = DateTime.now();
      String fmtIso(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final d1 = fmtIso(now.subtract(const Duration(days: 60)));
      final d2 = fmtIso(now.subtract(const Duration(days: 30)));
      final d3 = fmtIso(now);

      store.db.txs.addAll([
        // Assinatura implícita com reajuste de R$ 39,90 para R$ 55,90
        Transaction(
          id: 'sub_1',
          acc: 'acc_nubank',
          date: d1,
          payee: 'Netflix.com',
          cat: 'Lazer › Streaming',
          amt: -3990,
          rec: true,
        ),
        Transaction(
          id: 'sub_2',
          acc: 'acc_nubank',
          date: d2,
          payee: 'Netflix.com',
          cat: 'Lazer › Streaming',
          amt: -3990,
          rec: true,
        ),
        Transaction(
          id: 'sub_3',
          acc: 'acc_nubank',
          date: d3,
          payee: 'Netflix.com',
          cat: 'Lazer › Streaming',
          amt: -5590,
          rec: true,
        ),
        // Compra parcelada (não deve ser confundida com assinatura)
        Transaction(
          id: 'parc_1',
          acc: 'acc_nubank',
          date: d2,
          payee: 'Loja Apple (1/10)',
          cat: 'Lazer',
          amt: -50000,
          plan: 'p_apple',
          pn: 1,
          pt: 10,
          rec: true,
        ),
        Transaction(
          id: 'parc_2',
          acc: 'acc_nubank',
          date: d3,
          payee: 'Loja Apple (2/10)',
          cat: 'Lazer',
          amt: -50000,
          plan: 'p_apple',
          pn: 2,
          pt: 10,
          rec: true,
        ),
      ]);
      store.markIndexesDirty();

      final candidates =
          FinancialInsightsEngine.detectImplicitRecurrences(store);
      final netflix = candidates
          .where((c) => c.displayPayee.toLowerCase().contains('netflix'))
          .toList();
      final apple = candidates
          .where((c) => c.displayPayee.toLowerCase().contains('apple'))
          .toList();

      expect(netflix, isNotEmpty);
      expect(netflix.first.detectedFrequency, 'monthly');
      expect(netflix.first.hasPriceIncrease, isTrue);
      expect(netflix.first.priceChangeCents, 1600);
      expect(apple, isEmpty);
    });

    test('reconcileExtractedDocumentItems pareia lançamentos já existentes e ignora Pagamento recebido', () {
      final store = buildTestStore();
      final items = FinancialInsightsEngine.reconcileExtractedDocumentItems(
        store,
        defaultAccountId: 'acc_corrente',
        rawItems: [
          {
            'date': '2026-11-10',
            'payee': 'OUTBACK STEAKHOUSE',
            'amount_cents': 55000,
            'is_expense': true,
          },
          {
            'date': '2026-11-15',
            'payee': 'Pagamento recebido',
            'amount_cents': 120000,
            'is_expense': false,
          },
          {
            'date': '2026-11-18',
            'payee': 'Uber Trip',
            'amount_cents': 3490,
            'is_expense': true,
          },
        ],
      );

      // 'Pagamento recebido' foi filtrado; sobram 2 itens (1 conciliado, 1 novo)
      expect(items.length, 2);
      expect(items[0].matchedExistingTxId, 'tx_nov_1');
      expect(items[1].matchedExistingTxId, isNull);
      expect(items[1].signedAmountCents, -3490);
    });

    test('parseNaturalLanguageTransaction extrai valor, conta, parcelas e #tags e executa no MoneyStore', () {
      final store = buildTestStore();
      final proposal = AIAssistantService.parseNaturalLanguageTransaction(
        store: store,
        text: 'Gastei 64,90 no Uber hoje no Nubank UV #Transporte #Viagem',
      );

      expect(proposal, isNotNull);
      expect(proposal!.type, 'create_transaction');
      expect(proposal.payload['accountId'], 'acc_nubank');
      expect(proposal.payload['amountCents'], -6490);
      expect(proposal.payload['tags'], containsAll(['Transporte', 'Viagem']));

      final beforeNonAutoCount =
          store.db.txs.where((t) => t.auto != true).length;
      final msg = proposal.executeOnStore(store);
      expect(msg, contains('registrado'));
      expect(
        store.db.txs.where((t) => t.auto != true).length,
        beforeNonAutoCount + 1,
      );
      expect(store.db.tags, containsAll(['Transporte', 'Viagem']));
    });

    test('ShortcutUrlService.extractAiPromptFromQuery extrai comandos para Siri e Atalhos', () {
      final p = ShortcutUrlService.extractAiPromptFromQuery(
        '?prompt=Gastei%2045,90%20no%20Uber%20hoje',
      );
      expect(p, 'Gastei 45,90 no Uber hoje');
    });

    test('MoneyStore isAiAssistantEnabled master switch ativa e desativa painel e chamadas de abertura', () {
      final store = buildTestStore();
      store.setAiAssistantEnabled(true);
      expect(store.isAiAssistantEnabled, isTrue);

      store.openAiAssistant(initialPrompt: 'Teste');
      expect(store.isAiAssistantPanelOpen, isTrue);
      expect(store.pendingAiInitialPrompt, 'Teste');

      // Desativar desliga o painel imediatamente
      store.setAiAssistantEnabled(false);
      expect(store.isAiAssistantEnabled, isFalse);
      expect(store.isAiAssistantPanelOpen, isFalse);

      // Com assistente desativada, openAiAssistant e toggleAiAssistantPanel não abrem
      store.openAiAssistant(initialPrompt: 'Outro teste');
      expect(store.isAiAssistantPanelOpen, isFalse);
      store.toggleAiAssistantPanel();
      expect(store.isAiAssistantPanelOpen, isFalse);
    });

    test('findOrganizationOpportunities ignora lançamentos já conciliados e parcelas antecipadas na detecção de duplicidades', () {
      final store = buildTestStore();
      store.db.txs.addAll([
        // 1) Dois lançamentos idênticos, mas JÁ CONCILIADOS (rec: true) -> NÃO deve apontar duplicidade
        Transaction(
          id: 'rec_dup_1',
          acc: 'acc_itau',
          date: '2026-11-10',
          payee: 'Padaria Central',
          cat: 'Alimentação',
          amt: -2500,
          rec: true,
        ),
        Transaction(
          id: 'rec_dup_2',
          acc: 'acc_itau',
          date: '2026-11-10',
          payee: 'Padaria Central',
          cat: 'Alimentação',
          amt: -2500,
          rec: true,
        ),
        // 2) Parcelas antecipadas no mesmo mês/data/valor (rec: false) -> NÃO deve apontar duplicidade
        Transaction(
          id: 'antecip_1',
          acc: 'acc_nubank',
          date: '2026-11-12',
          payee: 'Amazon Brasil (3/10)',
          cat: 'Compras',
          amt: -15000,
          rec: false,
          ik: '2026-11',
        ),
        Transaction(
          id: 'antecip_2',
          acc: 'acc_nubank',
          date: '2026-11-12',
          payee: 'Amazon Brasil (4/10)',
          cat: 'Compras',
          amt: -15000,
          rec: false,
          ik: '2026-11',
        ),
        // 3) Duplicidade real não conciliada e não parcelada -> DEVE apontar duplicidade
        Transaction(
          id: 'real_dup_1',
          acc: 'acc_itau',
          date: '2026-11-15',
          payee: 'Farmacia DrogaRaia',
          cat: 'Saúde',
          amt: -8990,
          rec: false,
        ),
        Transaction(
          id: 'real_dup_2',
          acc: 'acc_itau',
          date: '2026-11-15',
          payee: 'Farmacia DrogaRaia',
          cat: 'Saúde',
          amt: -8990,
          rec: false,
        ),
      ]);

      final opps = FinancialInsightsEngine.findOrganizationOpportunities(
        store,
        targetMonth: '2026-11',
      );
      final dups = opps.where((o) => o.kind == 'duplicate').toList();

      expect(dups.length, 1);
      expect(dups.first.transactionIds, containsAll(['real_dup_1', 'real_dup_2']));
    });

    test('buildCompactContextSnapshot e executeLocalQuery entregam valores monetários formatados em moeda (sem centavos brutos)', () {
      final store = buildTestStore();
      final snapshot = FinancialInsightsEngine.buildCompactContextSnapshot(
        store,
        focusMonth: '2026-11',
      );
      final monthly = snapshot['monthlySummary'] as Map<String, dynamic>;
      expect(monthly['expense'], 'R\$ 1.450,00');
      expect(monthly.containsKey('expenseCents'), isFalse);

      final rows = FinancialInsightsEngine.executeLocalQuery(
        store,
        const AIQueryFilter(searchText: 'Outback'),
      );
      expect(rows, isNotEmpty);
      expect(rows.first['amount'], '-R\$ 550,00');
      expect(rows.first.containsKey('amountCents'), isFalse);

      final parsed = AIAssistantService.parseStructuredAIResponse(
        '{"reply": "Você gastou R\$ 14.947,90 (1.494.790 centavos) com saldo de R\$ 18,33 (1.833 centavos).", "actions": []}',
      );
      expect(
        parsed.reply,
        'Você gastou R\$ 14.947,90 com saldo de R\$ 18,33.',
      );
    });

    test('AIProviderType.openrouter e MoneyStore persistem chaves do OpenRouter com sucesso', () {
      final store = buildTestStore();
      expect(AIProviderType.fromId('openrouter'), AIProviderType.openrouter);
      expect(AIProviderType.openrouter.id, 'openrouter');
      expect(AIProviderType.openrouter.label, 'OpenRouter.ai');

      store.setAiAssistantConfig(
        enabled: true,
        provider: 'openrouter',
        openrouterKey: 'sk-or-v1-test-key-123',
      );

      expect(store.aiProvider, 'openrouter');
      expect(store.openrouterApiKey, 'sk-or-v1-test-key-123');
    });

    testWidgets('AiAssistantSidePanel renderiza sem erros de compilação ou estouro de layout', (tester) async {
      final store = buildTestStore();
      store.setAiAssistantEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AiAssistantSidePanel(store: store),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Assistente OpenMoney'), findsOneWidget);
      expect(find.text('Privado'), findsOneWidget);
    });
  });
}
